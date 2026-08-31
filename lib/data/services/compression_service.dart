import 'dart:io';

import 'package:image/image.dart' as img;

import '../../core/models/optimize_type.dart';
import '../../core/models/output_format.dart';
import '../../core/models/result.dart';
import 'log_service.dart';
import 'path_service.dart';
import 'process_service.dart';

/// JPEG の最適化種別ごとのパラメータ。
class _JpegParams {
  const _JpegParams(this.quality);

  /// 圧縮品質 (0-100)。最適化種別で固定。
  final int quality;
}

/// PNG の最適化種別ごとのパラメータ。
class _PngParams {
  const _PngParams(this.quality);

  /// 圧縮品質 (0-100)。最適化種別で固定。
  final int quality;
}

/// JPEG XL の最適化種別ごとのパラメータ。
class _JxlParams {
  const _JxlParams(this.effort, this.extraOpts);

  final int effort;
  final List<String> extraOpts;
}

/// AV1 の最適化種別ごとのパラメータ。
class _AvifParams {
  const _AvifParams(this.speed, this.yuv, this.aomOpts);

  final int speed;
  final int yuv;
  final List<String> aomOpts;
}

/// WebP の最適化種別ごとのパラメータ。
class _WebpParams {
  const _WebpParams(this.preset, this.method);

  /// プリセット。`default` | `photo` | `picture` | `drawing` | `icon` | `text`
  final String preset;

  /// 圧縮メソッド (0=fast .. 6=slowest)。
  final int method;
}

/// 画像圧縮処理を実行するサービス。
/// `jpegoptim` / `pngoptim` / `cjxl` / `avifenc` / `cwebp` コマンドを利用する。
class CompressionService {
  CompressionService({
    required this.pathService,
    required this.processService,
    LogService? logService,
  }) : _log = logService;

  final PathService pathService;
  final ProcessService processService;
  final LogService? _log;

  static const Map<OptimizeType, _JpegParams> _jpegParams = {
    OptimizeType.anime: _JpegParams(75),
    OptimizeType.photo: _JpegParams(80),
    OptimizeType.speed: _JpegParams(60),
    OptimizeType.quality: _JpegParams(95),
  };

  static const Map<OptimizeType, _PngParams> _pngParams = {
    OptimizeType.anime: _PngParams(75),
    OptimizeType.photo: _PngParams(80),
    OptimizeType.speed: _PngParams(60),
    OptimizeType.quality: _PngParams(95),
  };

  static const Map<OptimizeType, _JxlParams> _jxlParams = {
    OptimizeType.anime: _JxlParams(7, ['--lossless_jpeg=0']),
    OptimizeType.photo: _JxlParams(7, ['--lossless_jpeg=0']),
    OptimizeType.speed: _JxlParams(7, ['--lossless_jpeg=0']),
    OptimizeType.quality: _JxlParams(9, ['--lossless_jpeg=0']),
  };

  static const Map<OptimizeType, _AvifParams> _avifParams = {
    OptimizeType.anime: _AvifParams(3, 444, [
      '-a',
      'end-usage=q',
      '-a',
      'cq-level=20',
    ]),
    OptimizeType.photo: _AvifParams(4, 420, [
      '-a',
      'end-usage=q',
      '-a',
      'cq-level=22',
    ]),
    OptimizeType.speed: _AvifParams(8, 420, []),
    OptimizeType.quality: _AvifParams(4, 444, [
      '-a',
      'end-usage=q',
      '-a',
      'cq-level=16',
    ]),
  };

  static const Map<OptimizeType, _WebpParams> _webpParams = {
    OptimizeType.anime: _WebpParams('drawing', 4),
    OptimizeType.photo: _WebpParams('photo', 4),
    OptimizeType.speed: _WebpParams('default', 0),
    OptimizeType.quality: _WebpParams('photo', 6),
  };

  /// [input] を [format]・[optimizeType]・[quality] に従って圧縮し、[output] に出力する。
  Future<Result<void>> compress({
    required String input,
    required String output,
    required OutputFormat format,
    required OptimizeType optimizeType,
    required int quality,
    required int threads,
  }) async {
    try {
      switch (format) {
        case OutputFormat.jpeg:
          await _compressJpeg(input, output, optimizeType);
        case OutputFormat.png:
          await _compressPng(input, output, optimizeType);
        case OutputFormat.jpegXl:
          await _compressJpegXl(input, output, optimizeType, quality, threads);
        case OutputFormat.av1:
          await _compressAv1(input, output, optimizeType, quality);
        case OutputFormat.webp:
          await _compressWebp(input, output, optimizeType, quality);
      }
      return Result.ok(null);
    } on Object catch (error, stackTrace) {
      _log?.logger.severe('圧縮失敗(${format.name}): $error', error, stackTrace);
      return Result.fail(error);
    }
  }

  Future<void> _compressJpeg(
    String input,
    String output,
    OptimizeType optimizeType,
  ) async {
    final binPath = await pathService.jpegoptimBinPath();
    final binDir = await pathService.jpegoptimBinDirectory();
    final params = _jpegParams[optimizeType]!;
    _log?.logger.info(
      '圧縮(JPEG): input=$input output=$output type=${optimizeType.name} '
      'quality=${params.quality} bin=$binPath',
    );

    // PNG 等の入力を JPEG に変換する。jpegoptim は JPEG 入力のみ対応のため、
    // Dart の image パッケージで一旦 JPEG を生成してから jpegoptim で最適化する。
    _log?.logger.fine('JPEG中間生成: $input -> $output (quality=100)');
    try {
      await _convertToJpeg(input, output);
      final intermediateSize = await File(output).length();
      _log?.logger.info('JPEG中間生成完了: $output ${intermediateSize}bytes');
    } on Object catch (e, st) {
      _log?.logger.severe('JPEG中間生成失敗: $input -> $output', e, st);
      rethrow;
    }

    final outputDir = File(output).parent.path;
    final args = ['-m${params.quality}', '-o', '-d', outputDir, output];
    _log?.logger.info(
      'jpegoptim実行: $binPath ${args.join(' ')} (dir: ${binDir.path})',
    );
    try {
      await processService.run(binPath, args, workingDirectory: binDir.path);
      final outSize = await File(output).length();
      _log?.logger.info('jpegoptim完了: $output ${outSize}bytes');
    } on Object catch (e, st) {
      _log?.logger.warning('jpegoptim失敗、フォールバックで再エンコード: $e');
      _log?.logger.severe('jpegoptim失敗詳細', e, st);
      // フォールバック: Dart の image パッケージで指定品質で再エンコードする。
      try {
        final bytes = await File(output).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) throw Exception('フォールバック decode 失敗: $output');
        final jpegBytes = img.encodeJpg(decoded, quality: params.quality);
        await File(output).writeAsBytes(jpegBytes);
        _log?.logger.info(
          'フォールバックJPEG生成完了: $output ${jpegBytes.length}bytes quality=${params.quality}',
        );
      } on Object catch (fallbackError, fallbackSt) {
        _log?.logger.severe('フォールバック失敗', fallbackError, fallbackSt);
        rethrow;
      }
    }
  }

  Future<void> _convertToJpeg(String input, String output) async {
    final bytes = await File(input).readAsBytes();
    _log?.logger.fine('画像デコード: $input ${bytes.length}bytes');
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('画像のデコードに失敗しました: $input');
    }
    _log?.logger.fine('画像デコード成功: ${decoded.width}x${decoded.height}');
    // jpegoptim で再圧縮するため、ここでは最高品質で JPEG を生成する。
    final jpegBytes = img.encodeJpg(decoded, quality: 100);
    await File(output).writeAsBytes(jpegBytes);
    _log?.logger.fine(
      'JPEGエンコード完了: $output ${jpegBytes.length}bytes quality=100',
    );
  }

  Future<void> _compressPng(
    String input,
    String output,
    OptimizeType optimizeType,
  ) async {
    final binPath = await pathService.pngoptimBinPath();
    final binDir = await pathService.pngoptimBinDirectory();
    final params = _pngParams[optimizeType]!;
    _log?.logger.info(
      '圧縮(PNG): input=$input output=$output type=${optimizeType.name} '
      'quality=${params.quality} bin=$binPath',
    );

    _log?.logger.fine('PNG中間生成: $input -> $output');
    try {
      await _convertToPng(input, output);
      final intermediateSize = await File(output).length();
      _log?.logger.info('PNG中間生成完了: $output ${intermediateSize}bytes');
    } on Object catch (e, st) {
      _log?.logger.severe('PNG中間生成失敗: $input -> $output', e, st);
      rethrow;
    }

    final args = [output, '-o', output, '--quality', '${params.quality}'];
    _log?.logger.info(
      'pngoptim実行: $binPath ${args.join(' ')} (dir: ${binDir.path})',
    );
    try {
      await processService.run(binPath, args, workingDirectory: binDir.path);
      final outSize = await File(output).length();
      _log?.logger.info('pngoptim完了: $output ${outSize}bytes');
    } on Object catch (e, st) {
      _log?.logger.warning('pngoptim失敗、フォールバックで再エンコード: $e');
      _log?.logger.severe('pngoptim失敗詳細', e, st);
      try {
        final bytes = await File(output).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) throw Exception('フォールバック decode 失敗: $output');
        final pngBytes = img.encodePng(decoded);
        await File(output).writeAsBytes(pngBytes);
        _log?.logger.info('フォールバックPNG生成完了: $output ${pngBytes.length}bytes');
      } on Object catch (fallbackError, fallbackSt) {
        _log?.logger.severe('フォールバック失敗', fallbackError, fallbackSt);
        rethrow;
      }
    }
  }

  Future<void> _convertToPng(String input, String output) async {
    final bytes = await File(input).readAsBytes();
    _log?.logger.fine('画像デコード: $input ${bytes.length}bytes');
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('画像のデコードに失敗しました: $input');
    }
    _log?.logger.fine('画像デコード成功: ${decoded.width}x${decoded.height}');
    final pngBytes = img.encodePng(decoded);
    await File(output).writeAsBytes(pngBytes);
    _log?.logger.fine('PNGエンコード完了: $output ${pngBytes.length}bytes');
  }

  Future<void> _compressJpegXl(
    String input,
    String output,
    OptimizeType optimizeType,
    int quality,
    int threads,
  ) async {
    final binPath = await pathService.cjxlBinPath();
    final binDir = await pathService.libjxlBinDirectory();
    final params = _jxlParams[optimizeType]!;
    _log?.logger.info(
      '圧縮(JPEG XL): input=$input output=$output type=${optimizeType.name} '
      'quality=$quality bin=$binPath',
    );

    await processService.run(binPath, [
      input,
      output,
      '--distance=${_qualityToDistance(quality)}',
      '-e',
      '${params.effort}',
      '--num_threads=$threads',
      ...params.extraOpts,
    ], workingDirectory: binDir.path);
  }

  Future<void> _compressAv1(
    String input,
    String output,
    OptimizeType optimizeType,
    int quality,
  ) async {
    final binPath = await pathService.avifencBinPath();
    final binDir = await pathService.libavifBinDirectory();
    final params = _avifParams[optimizeType]!;
    _log?.logger.info(
      '圧縮(AV1): input=$input output=$output type=${optimizeType.name} '
      'quality=$quality bin=$binPath',
    );

    await processService.run(binPath, [
      '--speed',
      '${params.speed}',
      '-q',
      '$quality',
      '-y',
      '${params.yuv}',
      ...params.aomOpts,
      input,
      output,
    ], workingDirectory: binDir.path);
  }

  Future<void> _compressWebp(
    String input,
    String output,
    OptimizeType optimizeType,
    int quality,
  ) async {
    final binPath = await pathService.cwebpBinPath();
    final binDir = await pathService.libwebpBinDirectory();
    final params = _webpParams[optimizeType]!;
    _log?.logger.info(
      '圧縮(WebP): input=$input output=$output type=${optimizeType.name} '
      'quality=$quality preset=${params.preset} method=${params.method} bin=$binPath',
    );

    await processService.run(binPath, [
      '-preset',
      params.preset,
      '-q',
      '$quality',
      '-m',
      '${params.method}',
      '-mt',
      input,
      '-o',
      output,
    ], workingDirectory: binDir.path);
  }

  /// 品質 (1-100) を JPEG XL の距離 (0-25) に変換する。
  /// 100 はロスレス相当 (0)、80 は視覚的にほぼロスレス相当 (約1.0) となる。
  double _qualityToDistance(int quality) {
    final q = quality.clamp(1, 100);
    if (q >= 100) return 0;
    return (100 - q) * 0.1;
  }
}
