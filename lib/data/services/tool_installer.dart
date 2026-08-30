// ignore_for_file: prefer_initializing_formals
import 'dart:developer' as dev;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:tree_image_optimizer/core/constants/app_constants.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 初回展開の進捗コールバック。完了ファイル数と総ファイル数を渡す。
typedef InstallProgress = void Function(int completed, int total);

/// 同梱アセットから tools を Application Support へ初回展開するサービス。
///
/// ローカルでは `Directory.current/tools`（プロジェクト直下）を優先してコピーし、
/// Release では GitHub Releases の単一 ZIP（`tools-vVERSION.zip`）を
/// ダウンロードして展開する。単一 ZIP にまとめることで CI とアプリの
/// 実装が単純になる。
class ToolInstaller {
  /// 同梱アセット内の tools プレフィックス。
  static const String _assetPrefix = 'tools/';

  /// 実行権限を付与するバイナリ名。
  static const List<String> _executables = [
    'upscayl-bin',
    'cjxl',
    'avifenc',
    'jpegoptim',
    'pngoptim',
  ];

  /// Application Support 内の tools ディレクトリ。
  Future<Directory> toolsDirectory() async {
    final home = Platform.environment['HOME'];
    if (Platform.isMacOS && home != null && home.isNotEmpty) {
      return Directory(
        '$home/Library/Application Support/tree-image-optimizer/tools',
      );
    }
    final support = await getApplicationSupportDirectory();
    if (Platform.isMacOS) {
      return Directory('${support.parent.path}/tree-image-optimizer/tools');
    }
    return Directory('${support.path}/tree-image-optimizer/tools');
  }

  /// 開発環境・同梱ツールの基準ディレクトリ。テスト用に注入できる。
  final String? sourceToolsPath;

  /// ファイルログ用のサービス。`dev.log` と併せてファイルにも出力する。
  final dynamic _logService;

  ToolInstaller({this.sourceToolsPath, dynamic logService})
    : _logService = logService;

  void _log(
    String message, {
    String name = 'ToolInstaller',
    Object? error,
    StackTrace? stackTrace,
  }) {
    dev.log(message, name: name, error: error, stackTrace: stackTrace);
    try {
      // ignore: avoid_dynamic_calls
      _logService?.logger?.info('[$name] $message');
      if (error != null) {
        // ignore: avoid_dynamic_calls
        _logService?.logger?.severe('[$name] $message', error, stackTrace);
      }
    } catch (_) {}
  }

  /// コピー元の tools ディレクトリ候補を返す。
  List<Directory> _sourceCandidates() {
    final result = <Directory>[];
    if (sourceToolsPath != null) {
      result.add(Directory(sourceToolsPath!));
    }
    result.add(Directory('${Directory.current.path}/tools'));
    // Releaseビルドでは app bundle 内の Resources に配置される場合がある
    try {
      final exe = File(Platform.resolvedExecutable);
      final macosDir = exe.parent.path; // .../Contents/MacOS
      result.add(Directory('$macosDir/../Resources/tools'));
      result.add(
        Directory(
          '$macosDir/../Frameworks/App.framework/Versions/A/Resources/flutter_assets/tools',
        ),
      );
      result.add(Directory('$macosDir/../Resources/flutter_assets/tools'));
    } catch (_) {}
    return result;
  }

  /// tools が展開済みかどうか。
  Future<bool> isInstalled() async {
    final dir = await toolsDirectory();
    final os = _osName();
    final required = [
      File(
        '${dir.path}/upscal/bin/${Platform.isWindows ? 'upscayl-bin.exe' : 'upscayl-bin'}',
      ),
      File(
        '${dir.path}/jpegoptim/bin/$os/${Platform.isWindows ? 'jpegoptim.exe' : 'jpegoptim'}',
      ),
      File(
        '${dir.path}/pngoptim/bin/$os/${Platform.isWindows ? 'pngoptim.exe' : 'pngoptim'}',
      ),
      File(
        '${dir.path}/libjxl/bin/$os/${Platform.isWindows ? 'cjxl.exe' : 'cjxl'}',
      ),
      File(
        '${dir.path}/libavif/bin/$os/${Platform.isWindows ? 'avifenc.exe' : 'avifenc'}',
      ),
    ];
    for (final f in required) {
      final exists = f.existsSync();
      _log(
        'isInstalled check: ${f.path} exists=$exists',
        name: 'ToolInstaller',
      );
      if (!exists) return false;
    }
    _log('isInstalled: true dir=${dir.path}', name: 'ToolInstaller');
    return true;
  }

  String _osName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'macos';
  }

  /// 起動時に各バイナリの存在を個別に確認し、欠損時はフォルダごと削除して
  /// 再取得する。5バイナリそれぞれと `upscal/models` の空チェックを行う。
  /// ローカルでは `Directory.current/tools` を優先し、Release では
  /// GitHub Releases の単一 ZIP をダウンロードする。
  /// ツールがインストールされたアプリバージョンを記録する。
  /// 次回起動時に現在のバージョンと比較し、不一致なら強制再取得するために使う。
  Future<void> _markInstalled() async {
    try {
      final toolsDir = await toolsDirectory();
      final marker = File('${toolsDir.path}/.installed_version');
      final version = await _currentVersion();
      await marker.writeAsString(version);
    } on Object catch (_) {}
  }

  Future<void> repairMissingTools({InstallProgress? onProgress}) async {
    final toolsDir = await toolsDirectory();
    await toolsDir.create(recursive: true);
    final os = _osName();

    // 所定のパスに tools が存在すればダウンロードしない（仕様）。
    // 不足しているバイナリ／モデルがある場合のみ個別に再取得する。
    // バージョンが変わっても既存の tools が利用可能なら再ダウンロードは行わない。

    final checks = [
      _ToolCheck(
        name: 'upscal',
        folder: 'upscal',
        binary:
            'upscal/bin/${Platform.isWindows ? 'upscayl-bin.exe' : 'upscayl-bin'}',
      ),
      _ToolCheck(
        name: 'jpegoptim',
        folder: 'jpegoptim',
        binary:
            'jpegoptim/bin/$os/${Platform.isWindows ? 'jpegoptim.exe' : 'jpegoptim'}',
      ),
      _ToolCheck(
        name: 'pngoptim',
        folder: 'pngoptim',
        binary:
            'pngoptim/bin/$os/${Platform.isWindows ? 'pngoptim.exe' : 'pngoptim'}',
      ),
      _ToolCheck(
        name: 'libjxl',
        folder: 'libjxl',
        binary: 'libjxl/bin/$os/${Platform.isWindows ? 'cjxl.exe' : 'cjxl'}',
      ),
      _ToolCheck(
        name: 'libavif',
        folder: 'libavif',
        binary:
            'libavif/bin/$os/${Platform.isWindows ? 'avifenc.exe' : 'avifenc'}',
      ),
    ];

    // 欠損しているフォルダを収集し、単一 ZIP のダウンロードは1回だけ行う
    final missingFolders = <String>[];
    for (final c in checks) {
      final binaryFile = File('${toolsDir.path}/${c.binary}');
      final exists = binaryFile.existsSync();
      _log(
        'check ${c.name}: ${binaryFile.path} exists=$exists',
        name: 'ToolInstaller',
      );
      if (exists) {
        _log('skip ${c.name}: binary exists', name: 'ToolInstaller');
        continue;
      }
      missingFolders.add(c.folder);
      final folder = Directory('${toolsDir.path}/${c.folder}');
      if (await folder.exists()) {
        _log(
          'delete folder ${folder.path} (binary missing: ${c.name})',
          name: 'ToolInstaller',
        );
        try {
          await folder.delete(recursive: true);
          _log('deleted ${folder.path}', name: 'ToolInstaller');
        } on Object catch (e, st) {
          _log(
            'failed to delete ${folder.path}: $e',
            name: 'ToolInstaller',
            error: e,
            stackTrace: st,
          );
        }
      }
    }

    // 欠損がある場合は単一 ZIP をダウンロードして展開（ローカルに tools があればそちらを優先）
    if (missingFolders.isNotEmpty) {
      _log(
        'missing folders: $missingFolders, attempting to restore',
        name: 'ToolInstaller',
      );
      // ローカルに tools があればそこからコピー（開発環境）
      bool restoredFromLocal = false;
      for (final folder in missingFolders) {
        for (final candidate in _sourceCandidates()) {
          final src = Directory('${candidate.path}/$folder');
          if (await src.exists()) {
            _log(
              'copyToolFolder from candidate $src for $folder',
              name: 'ToolInstaller',
            );
            final dest = Directory('${toolsDir.path}/$folder');
            await dest.create(recursive: true);
            await _copyDirectory(src, dest, onProgress);
            restoredFromLocal = true;
            break;
          }
        }
        if (restoredFromLocal) break;
      }
      // ローカルに無ければ単一 ZIP をダウンロード
      if (!restoredFromLocal) {
        // 欠損フォルダが複数あっても単一 ZIP を1回だけダウンロード
        await _downloadAndExtractToolsZip(onProgress);
      } else {
        // ローカルから1つでも復元できた場合は残りもローカルから
        for (final folder in missingFolders) {
          final dest = Directory('${toolsDir.path}/$folder');
          if (await dest.exists()) continue;
          await _copyToolFolder(folder, onProgress);
        }
      }
    }

    // upscal/models は1ファイルも存在しなければフォルダごと削除して再取得
    final modelsDir = Directory('${toolsDir.path}/upscal/models');
    final hasModels = await _hasAnyFile(modelsDir);
    _log(
      'check upscal models: ${modelsDir.path} hasFiles=$hasModels',
      name: 'ToolInstaller',
    );
    if (!hasModels) {
      if (await modelsDir.exists()) {
        _log(
          'delete models folder ${modelsDir.path} (empty)',
          name: 'ToolInstaller',
        );
        try {
          await modelsDir.delete(recursive: true);
          _log('deleted ${modelsDir.path}', name: 'ToolInstaller');
        } on Object catch (e, st) {
          _log(
            'failed to delete ${modelsDir.path}: $e',
            name: 'ToolInstaller',
            error: e,
            stackTrace: st,
          );
        }
      }
      _log('reinstall upscal/models', name: 'ToolInstaller');
      // models も単一 ZIP に含まれるため、既にダウンロード済みなら再利用
      final modelsDest = Directory('${toolsDir.path}/upscal/models');
      if (!await modelsDest.exists() || !await _hasAnyFile(modelsDest)) {
        // ローカルから試す
        bool restored = false;
        for (final candidate in _sourceCandidates()) {
          final src = Directory('${candidate.path}/upscal/models');
          if (await src.exists() && await _hasAnyFile(src)) {
            await _copyDirectory(src, modelsDest, onProgress);
            restored = true;
            break;
          }
        }
        if (!restored) {
          // アセットまたはダウンロードから
          await _copyToolFolder('upscal/models', onProgress);
        }
      }
      _log('reinstalled upscal/models', name: 'ToolInstaller');
    } else {
      _log('skip upscal/models: has files', name: 'ToolInstaller');
    }
    await _markInstalled();
  }

  Future<bool> _hasAnyFile(Directory dir) async {
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(recursive: false)) {
      if (entity is File) return true;
      if (entity is Directory) {
        if (await _hasAnyFile(entity)) return true;
      }
    }
    return false;
  }

  /// 単一 ZIP（tools-vVERSION.zip）を GitHub Releases からダウンロードして展開する
  Future<void> _downloadAndExtractToolsZip(InstallProgress? onProgress) async {
    final version = await _currentVersion();
    final url =
        'https://github.com/treetips/tree-image-optimizer/releases/download/v$version/tools-v$version.zip';
    _log('downloading tools zip from $url', name: 'ToolInstaller');
    final toolsDir = await toolsDirectory();
    final parent = toolsDir.parent;
    await parent.create(recursive: true);
    final tmpZip = File('${parent.path}/tools-v$version.zip.tmp');
    final destZip = File('${parent.path}/tools-v$version.zip');

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      _log(
        'download response: status=${response.statusCode} '
        'content-length(header)=${response.headers['content-length']}',
        name: 'ToolInstaller',
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download tools: ${response.statusCode} $url',
        );
      }
      // リダイレクト応答では contentLength が取れない場合があるため、
      // ヘッダからも取得する。
      final total =
          response.contentLength ??
          int.tryParse(response.headers['content-length'] ?? '') ??
          0;
      var received = 0;
      final sink = tmpZip.openWrite();
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        // total が 0（長さ不明）でも受信バイトを通知し、UI で動作中表示する。
        onProgress?.call(received, total);
      }
      await sink.close();
      client.close();

      // SHA256 の検証（期待値との照合）。
      // アプリにピン留めした期待ハッシュと一致しなければ、改ざん・破損の
      // 可能性があるため展開せずに破棄して失敗とする（fail-safe）。
      final bytes = await tmpZip.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      _log('downloaded tools zip sha256=$digest', name: 'ToolInstaller');
      final expected = AppConstants.toolsSha256;
      if (expected.isNotEmpty && digest != expected) {
        _log(
          'tools zip SHA-256 MISMATCH: expected=$expected got=$digest',
          name: 'ToolInstaller',
        );
        try {
          await tmpZip.delete();
        } catch (_) {}
        throw Exception(
          'tools zip SHA-256 mismatch: expected $expected, got $digest',
        );
      }
      _log('tools zip SHA-256 verified OK', name: 'ToolInstaller');

      await tmpZip.rename(destZip.path);
      _log('downloaded to ${destZip.path}', name: 'ToolInstaller');

      // ZIP を展開（tools/ プレフィックスを保持）
      final archiveBytes = await destZip.readAsBytes();
      final archive = ZipDecoder().decodeBytes(archiveBytes);
      for (final file in archive) {
        final outPath = '${parent.path}/${file.name}';
        if (file.isFile) {
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
          if (Platform.isMacOS || Platform.isLinux) {
            final name = outFile.path.split(Platform.pathSeparator).last;
            if (_executables.contains(name)) {
              await Process.run('chmod', ['+x', outFile.path]);
            }
          }
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      _log('extracted tools zip to ${parent.path}', name: 'ToolInstaller');
      try {
        await destZip.delete();
      } catch (_) {}
    } on Object catch (e, st) {
      _log(
        'failed to download tools zip: $e',
        name: 'ToolInstaller',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<String> _currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } on Object catch (_) {
      return '0.0.14';
    }
  }

  Future<void> _copyToolFolder(
    String relativeFolder,
    InstallProgress? onProgress,
  ) async {
    // 1. 開発環境の候補からコピー（ローカル優先）
    for (final candidate in _sourceCandidates()) {
      final src = Directory('${candidate.path}/$relativeFolder');
      if (await src.exists()) {
        _log('copyToolFolder from candidate $src', name: 'ToolInstaller');
        final dest = Directory(
          '${(await toolsDirectory()).path}/$relativeFolder',
        );
        await dest.create(recursive: true);
        await _copyDirectory(src, dest, onProgress);
        _log(
          'copyToolFolder from candidate done: $relativeFolder',
          name: 'ToolInstaller',
        );
        return;
      }
    }

    // 2. アセットバンドルからコピー
    _log(
      'copyToolFolder from AssetManifest: $relativeFolder',
      name: 'ToolInstaller',
    );
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final prefix = '$_assetPrefix$relativeFolder/';
      final keys =
          manifest.listAssets().where((k) => k.startsWith(prefix)).toList()
            ..sort();
      _log(
        'AssetManifest keys for $relativeFolder: ${keys.length}',
        name: 'ToolInstaller',
      );
      if (keys.isNotEmpty) {
        final toolsDir = await toolsDirectory();
        for (var i = 0; i < keys.length; i++) {
          final relative = keys[i].substring(_assetPrefix.length);
          final dest = File('${toolsDir.path}/$relative');
          await dest.parent.create(recursive: true);
          final data = await rootBundle.load(keys[i]);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          await dest.writeAsBytes(bytes, flush: true);
          if (Platform.isMacOS || Platform.isLinux) {
            final name = dest.path.split(Platform.pathSeparator).last;
            if (_executables.contains(name)) {
              await Process.run('chmod', ['+x', dest.path]);
            }
          }
          onProgress?.call(i + 1, keys.length);
        }
        _log(
          'copyToolFolder from AssetManifest done: $relativeFolder',
          name: 'ToolInstaller',
        );
        return;
      }
      _log(
        'no assets found for $relativeFolder (prefix=$prefix)',
        name: 'ToolInstaller',
      );
    } on Object catch (e, st) {
      _log(
        'AssetManifest failed for $relativeFolder: $e',
        name: 'ToolInstaller',
        error: e,
        stackTrace: st,
      );
    }

    // 3. GitHub Releases の単一 ZIP からダウンロード（Release 環境）
    _log(
      'try download single tools zip for $relativeFolder',
      name: 'ToolInstaller',
    );
    await _downloadAndExtractToolsZip(onProgress);
  }

  /// 同梱アセットから tools を展開する。
  Future<void> install({InstallProgress? onProgress}) async {
    final toolsDir = await toolsDirectory();
    _log('install start: toolsDir=${toolsDir.path}', name: 'ToolInstaller');
    await toolsDir.create(recursive: true);

    // 1. 開発環境ではプロジェクト直下の tools からコピーする。
    for (final candidate in _sourceCandidates()) {
      final exists = await candidate.exists();
      _log(
        'candidate check: ${candidate.path} exists=$exists',
        name: 'ToolInstaller',
      );
      if (exists) {
        _log('copy from candidate: ${candidate.path}', name: 'ToolInstaller');
        await _copyDirectory(candidate, toolsDir, onProgress);
        _log('copy from candidate done', name: 'ToolInstaller');
        return;
      }
    }

    // 2. アセットバンドルから展開する。
    _log(
      'copy from AssetManifest: prefix=$_assetPrefix',
      name: 'ToolInstaller',
    );
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final keys =
          manifest
              .listAssets()
              .where((k) => k.startsWith(_assetPrefix))
              .toList()
            ..sort();
      _log('AssetManifest keys=${keys.length}', name: 'ToolInstaller');
      if (keys.isNotEmpty) {
        for (var index = 0; index < keys.length; index++) {
          final relative = keys[index].substring(_assetPrefix.length);
          final dest = File('${toolsDir.path}/$relative');
          await dest.parent.create(recursive: true);

          final data = await rootBundle.load(keys[index]);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          await dest.writeAsBytes(bytes, flush: true);

          if (Platform.isMacOS || Platform.isLinux) {
            final name = dest.path.split(Platform.pathSeparator).last;
            if (_executables.contains(name)) {
              await Process.run('chmod', ['+x', dest.path]);
            }
          }

          onProgress?.call(index + 1, keys.length);
        }
        return;
      }
      _log('AssetManifest empty, will try download', name: 'ToolInstaller');
    } on Object catch (e, st) {
      _log(
        'AssetManifest failed: $e',
        name: 'ToolInstaller',
        error: e,
        stackTrace: st,
      );
    }

    // 3. 単一 ZIP をダウンロード
    await _downloadAndExtractToolsZip(onProgress);
    await _markInstalled();
  }

  Future<void> _copyDirectory(
    Directory source,
    Directory dest,
    InstallProgress? onProgress,
  ) async {
    final files = <File>[];
    await _collectFiles(source, files);
    final total = files.length;

    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final relative = file.path.substring(source.path.length + 1);
      final target = File('${dest.path}/$relative');
      await target.parent.create(recursive: true);
      await file.copy(target.path);

      if (Platform.isMacOS || Platform.isLinux) {
        final name = target.path.split(Platform.pathSeparator).last;
        if (_executables.contains(name)) {
          await Process.run('chmod', ['+x', target.path]);
        }
      }

      onProgress?.call(index + 1, total);
    }
  }

  Future<void> _collectFiles(Directory dir, List<File> out) async {
    await for (final entity in dir.list()) {
      if (entity is File) {
        out.add(entity);
      } else if (entity is Directory) {
        await _collectFiles(entity, out);
      }
    }
  }
}

class _ToolCheck {
  const _ToolCheck({
    required this.name,
    required this.folder,
    required this.binary,
  });

  final String name;
  final String folder;
  final String binary;
}
