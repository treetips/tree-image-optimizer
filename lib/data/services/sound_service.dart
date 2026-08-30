import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/models/sound_option.dart';
import 'log_service.dart';
import 'path_service.dart';

/// サウンドの一覧取得と再生を提供するサービス。
class SoundService {
  SoundService({
    LogService? logService,
    PathService? pathService,
    this.bundledBaseDir,
    this.userBaseDir,
  }) : _log = logService,
       _pathService = pathService ?? PathService();

  final LogService? _log;
  final PathService _pathService;

  /// 同梱サウンドの基準ディレクトリ。テスト用に注入できる。
  /// デフォルトは `<project>/assets/sounds`
  final String? bundledBaseDir;

  /// ユーザーサウンドの基準ディレクトリ。テスト用に注入できる。
  /// デフォルトは `$HOME/.config/tree-image-optimizer/sounds`
  final String? userBaseDir;

  Future<String> _bundledBaseDir() async {
    if (bundledBaseDir != null) return bundledBaseDir!;

    // 1. PathService の基準ディレクトリ配下
    final projectDir = await _pathService.projectDirectory();
    final inProject = Directory('${projectDir.path}/assets/sounds');
    if (inProject.existsSync()) return inProject.path;

    // 2. カレントディレクトリ配下
    final inCurrent = Directory('${Directory.current.path}/assets/sounds');
    if (inCurrent.existsSync()) return inCurrent.path;

    // 3. macOS App.framework の flutter_assets 配下
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final inAssets = Directory(
        '${exeDir.parent.path}/Frameworks/App.framework/Resources/flutter_assets/assets/sounds',
      );
      if (inAssets.existsSync()) return inAssets.path;
    } catch (_) {}

    return '${Directory.current.path}/assets/sounds';
  }

  String get _userBaseDir {
    if (userBaseDir != null) return userBaseDir!;
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.config/tree-image-optimizer/sounds';
  }

  /// 成功・失敗それぞれのサウンド選択肢を返す。
  /// 上部に同梱サウンド、その後にユーザーサウンドを配置する。
  Future<List<SoundOption>> listSounds({required bool success}) async {
    final folder = success ? 'success' : 'error';

    final bundled = await _listBundled(folder);
    final user = await _listUser(folder);

    return [...bundled, ...user];
  }

  Future<List<SoundOption>> _listBundled(String folder) async {
    final base = await _bundledBaseDir();
    final dir = Directory('$base/$folder');
    final files = await _listSoundFiles(dir);
    if (files.isNotEmpty) {
      return files
          .map(
            (f) => SoundOption(
              name: _fileName(f.path),
              source: 'assets/sounds/$folder/${_fileName(f.path)}',
              isBundled: true,
            ),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }

    // ファイルシステムで見つからない場合、AssetManifest から取得
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final prefix = 'assets/sounds/$folder/';
      final assets = manifest
          .listAssets()
          .where((k) => k.startsWith(prefix) && _isSoundFile(k))
          .toList();
      return assets
          .map(
            (k) => SoundOption(name: _fileName(k), source: k, isBundled: true),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return const [];
    }
  }

  Future<List<SoundOption>> _listUser(String folder) async {
    final dir = Directory('$_userBaseDir/$folder');
    final files = await _listSoundFiles(dir);
    return files
        .map(
          (f) => SoundOption(
            name: _fileName(f.path),
            source: f.path,
            isBundled: false,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  String _fileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  /// フォルダ内の音声ファイル一覧を返す。
  /// フォルダが存在しない場合は空リスト。
  Future<List<File>> _listSoundFiles(Directory dir) async {
    if (!await dir.exists()) return const [];
    final result = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!_isSoundFile(entity.path)) continue;
      result.add(entity);
    }
    return result;
  }

  bool _isSoundFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.ogg');
  }

  /// [source] を再生する。同梱サウンドはアセット、ユーザーサウンドはファイルパスから再生する。
  Future<void> play(String source) async {
    final player = AudioPlayer();
    try {
      if (source.startsWith('assets/')) {
        await player.setAsset(source);
      } else {
        await player.setFilePath(source);
      }
      await player.play();
      _log?.logger.info('サウンド再生: $source');
    } catch (error) {
      _log?.logger.warning('サウンド再生失敗: $source $error');
    } finally {
      await player.dispose();
    }
  }
}
