import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/models/wallpaper_option.dart';
import 'log_service.dart';
import 'path_service.dart';

/// 壁紙の一覧取得を提供するサービス。
class WallpaperService {
  WallpaperService({
    LogService? logService,
    PathService? pathService,
    this.bundledBaseDir,
    this.userBaseDir,
  }) : _log = logService,
       _pathService = pathService ?? PathService();

  final LogService? _log;
  final PathService _pathService;

  /// 同梱壁紙の基準ディレクトリ。テスト用に注入できる。
  /// デフォルトは `<project>/assets/images/wallpaper`
  final String? bundledBaseDir;

  /// ユーザー壁紙の基準ディレクトリ。テスト用に注入できる。
  /// デフォルトは `$HOME/.config/tree-image-optimizer/wallpaper`
  final String? userBaseDir;

  Future<String> _bundledBaseDir() async {
    if (bundledBaseDir != null) return bundledBaseDir!;

    // 1. PathService の基準ディレクトリ配下
    final projectDir = await _pathService.projectDirectory();
    final inProject = Directory('${projectDir.path}/assets/images/wallpaper');
    if (inProject.existsSync()) return inProject.path;

    // 2. カレントディレクトリ配下
    final inCurrent = Directory(
      '${Directory.current.path}/assets/images/wallpaper',
    );
    if (inCurrent.existsSync()) return inCurrent.path;

    // 3. macOS App.framework の flutter_assets 配下
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final inAssets = Directory(
        '${exeDir.parent.path}/Frameworks/App.framework/Resources/flutter_assets/assets/images/wallpaper',
      );
      if (inAssets.existsSync()) return inAssets.path;
    } catch (_) {}

    return '${Directory.current.path}/assets/images/wallpaper';
  }

  String get _userBaseDir {
    if (userBaseDir != null) return userBaseDir!;
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.config/tree-image-optimizer/wallpaper';
  }

  /// 壁紙選択肢を返す。
  /// 上部に同梱壁紙、その後にユーザー壁紙を配置し、各グループ内でファイル名ソートする。
  Future<List<WallpaperOption>> listWallpapers() async {
    final bundled = await _listBundled();
    final user = await _listUser();

    return [...bundled, ...user];
  }

  Future<List<WallpaperOption>> _listBundled() async {
    final base = await _bundledBaseDir();
    final dir = Directory(base);
    final files = await _listWallpaperFiles(dir);
    if (files.isNotEmpty) {
      return files
          .map(
            (f) => WallpaperOption(
              name: _fileName(f.path),
              source: 'assets/images/wallpaper/${_fileName(f.path)}',
              isBundled: true,
            ),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }

    // ファイルシステムで見つからない場合、AssetManifest から取得
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      const prefix = 'assets/images/wallpaper/';
      final assets = manifest
          .listAssets()
          .where((k) => k.startsWith(prefix) && _isWallpaperFile(k))
          .toList();
      return assets
          .map(
            (k) =>
                WallpaperOption(name: _fileName(k), source: k, isBundled: true),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      _log?.logger.warning('同梱壁紙の取得失敗: $e');
      return const [];
    }
  }

  Future<List<WallpaperOption>> _listUser() async {
    final dir = Directory(_userBaseDir);
    final files = await _listWallpaperFiles(dir);
    return files
        .map(
          (f) => WallpaperOption(
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

  /// フォルダ内の壁紙ファイル一覧を返す。
  /// フォルダが存在しない・権限不足の場合は空リスト。
  Future<List<File>> _listWallpaperFiles(Directory dir) async {
    try {
      if (!await dir.exists()) return const [];
      final result = <File>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (!_isWallpaperFile(entity.path)) continue;
        result.add(entity);
      }
      return result;
    } catch (e) {
      _log?.logger.warning('壁紙フォルダの参照失敗: ${dir.path} $e');
      return const [];
    }
  }

  bool _isWallpaperFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }

  /// 選択中の壁紙が一覧に無い場合やユーザー壁紙が参照不可の場合はフォールバック先を返す。
  /// 仕様: 存在しない/権限不足の場合は同梱壁紙1にフォールバック。
  String resolveSelected(String current, List<WallpaperOption> options) {
    if (options.isEmpty) return current;
    if (options.any((o) => o.source == current)) {
      // ユーザー壁紙の場合はファイル存在確認
      final matched = options.firstWhere((o) => o.source == current);
      if (!matched.isBundled) {
        final file = File(matched.source);
        try {
          if (!file.existsSync()) {
            return _fallback(options);
          }
        } catch (_) {
          return _fallback(options);
        }
      }
      return current;
    }
    return _fallback(options);
  }

  String _fallback(List<WallpaperOption> options) {
    // 同梱壁紙の最初のものを返す。無ければ先頭。
    final bundled = options.where((o) => o.isBundled).toList();
    if (bundled.isNotEmpty) return bundled.first.source;
    return options.first.source;
  }
}
