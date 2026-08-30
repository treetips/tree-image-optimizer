import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// アプリケーションが使用する各種パスを提供するサービス。
/// `tools` と `logs` は、各OSのアプリデータディレクトリ配下に配置する。
///
/// - macOS: `~/Library/Application Support/tree-image-optimizer`
/// - Windows: `%APPDATA%/tree-image-optimizer`
/// - Linux: `$XDG_DATA_HOME/tree-image-optimizer`
class PathService {
  PathService({this.baseDirectory});

  /// テスト用に基準ディレクトリを注入できる。
  final Directory? baseDirectory;

  /// OSに応じたアプリデータの基準ディレクトリ。
  Future<Directory> projectDirectory() async {
    if (baseDirectory != null) return baseDirectory!;

    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(
          '$home/Library/Application Support/tree-image-optimizer',
        );
      }
      // フォールバック: getApplicationSupportDirectory() は
      // `.../com.treeimageoptimizer.treeImageOptimizer` を含むため親に戻す
      final support = await getApplicationSupportDirectory();
      return Directory('${support.parent.path}/tree-image-optimizer');
    }
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/tree-image-optimizer');
  }

  /// ログディレクトリ。`<基準>/logs`
  Future<Directory> logsDirectory() async {
    final dir = await projectDirectory();
    return Directory('${dir.path}/logs');
  }

  /// tools ディレクトリ。`<基準>/tools`
  Future<Directory> toolsDirectory() async {
    final dir = await projectDirectory();
    return Directory('${dir.path}/tools');
  }

  /// upscal ディレクトリ。
  Future<Directory> upscalDirectory() async {
    final tools = await toolsDirectory();
    return Directory('${tools.path}/upscal');
  }

  /// upscal の bin ディレクトリ。
  Future<Directory> upscalBinDirectory() async {
    final upscal = await upscalDirectory();
    return Directory('${upscal.path}/bin');
  }

  /// upscayl-bin の実行ファイルパス。
  Future<String> upscalBinPath() async {
    final bin = await upscalBinDirectory();
    final executableName = Platform.isWindows
        ? 'upscayl-bin.exe'
        : 'upscayl-bin';
    return '${bin.path}/$executableName';
  }

  /// upscal の models ディレクトリ。
  Future<Directory> upscalModelsDirectory() async {
    final upscal = await upscalDirectory();
    return Directory('${upscal.path}/models');
  }

  /// jpegoptim の bin ディレクトリ。
  Future<Directory> jpegoptimBinDirectory() async {
    final tools = await toolsDirectory();
    final os = _osName();
    return Directory('${tools.path}/jpegoptim/bin/$os');
  }

  /// jpegoptim の実行ファイルパス。
  Future<String> jpegoptimBinPath() async {
    final bin = await jpegoptimBinDirectory();
    final executableName = Platform.isWindows ? 'jpegoptim.exe' : 'jpegoptim';
    return '${bin.path}/$executableName';
  }

  /// pngoptim の bin ディレクトリ。
  Future<Directory> pngoptimBinDirectory() async {
    final tools = await toolsDirectory();
    final os = _osName();
    return Directory('${tools.path}/pngoptim/bin/$os');
  }

  /// pngoptim の実行ファイルパス。
  Future<String> pngoptimBinPath() async {
    final bin = await pngoptimBinDirectory();
    final executableName = Platform.isWindows ? 'pngoptim.exe' : 'pngoptim';
    return '${bin.path}/$executableName';
  }

  /// libjxl の bin ディレクトリ。
  Future<Directory> libjxlBinDirectory() async {
    final tools = await toolsDirectory();
    final os = _osName();
    return Directory('${tools.path}/libjxl/bin/$os');
  }

  /// cjxl の実行ファイルパス。
  Future<String> cjxlBinPath() async {
    final bin = await libjxlBinDirectory();
    final executableName = Platform.isWindows ? 'cjxl.exe' : 'cjxl';
    return '${bin.path}/$executableName';
  }

  /// libavif の bin ディレクトリ。
  Future<Directory> libavifBinDirectory() async {
    final tools = await toolsDirectory();
    final os = _osName();
    return Directory('${tools.path}/libavif/bin/$os');
  }

  /// avifenc の実行ファイルパス。
  Future<String> avifencBinPath() async {
    final bin = await libavifBinDirectory();
    final executableName = Platform.isWindows ? 'avifenc.exe' : 'avifenc';
    return '${bin.path}/$executableName';
  }

  String _osName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'macos';
  }
}
