import 'dart:io';

import '../../core/models/optimize_type.dart';
import '../../core/models/output_format.dart';
import '../../core/models/result.dart';
import '../../core/models/target_filter.dart';
import '../services/compression_service.dart';
import '../services/path_service.dart';
import '../services/upscale_service.dart';

/// 変換処理に関するデータアクセスを提供するリポジトリ。
class ConvertRepository {
  ConvertRepository({
    required this.pathService,
    required this.upscaleService,
    required this.compressionService,
  });

  final PathService pathService;
  final UpscaleService upscaleService;
  final CompressionService compressionService;

  static const List<String> _supportedExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
  ];

  /// [folderPath] 内の対象ファイル一覧を返す。
  /// [filter] に応じて更新日時で絞り込む。
  Future<Result<List<String>>> getTargetFiles(
    String folderPath,
    TargetFilter filter,
  ) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        return Result.fail('指定されたフォルダが存在しません: $folderPath');
      }

      final now = DateTime.now();
      final files = <String>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final ext = entity.path.toLowerCase();
        if (!_supportedExtensions.any(ext.endsWith)) continue;

        if (filter.duration != null) {
          final stat = await entity.stat();
          if (now.difference(stat.modified).compareTo(filter.duration!) > 0) {
            continue;
          }
        }
        files.add(entity.path);
      }
      files.sort();
      return Result.ok(files);
    } on Object catch (error) {
      return Result.fail(error);
    }
  }

  /// 利用可能なアップスケールモデル一覧を返す。
  Future<List<String>> getUpscaleModels() async {
    try {
      final modelsDir = await pathService.upscalModelsDirectory();
      if (!await modelsDir.exists()) {
        return const ['realesr-animevideov3-x4'];
      }

      final models = <String>{};
      await for (final entity in modelsDir.list()) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.bin')) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        models.add(name.replaceAll('.bin', ''));
      }
      final list = models.toList()..sort();
      return list.isNotEmpty ? list : const ['realesr-animevideov3-x4'];
    } catch (_) {
      return const ['realesr-animevideov3-x4'];
    }
  }

  /// [input] をアップスケールして [output] に出力する。
  Future<Result<void>> upscale({
    required String input,
    required String output,
    required int scale,
    required String model,
  }) {
    return upscaleService.upscale(
      input: input,
      output: output,
      scale: scale,
      model: model,
    );
  }

  /// [input] を圧縮して [output] に出力する。
  Future<Result<void>> compress({
    required String input,
    required String output,
    required OutputFormat format,
    required OptimizeType optimizeType,
    required int quality,
    required int threads,
  }) {
    return compressionService.compress(
      input: input,
      output: output,
      format: format,
      optimizeType: optimizeType,
      quality: quality,
      threads: threads,
    );
  }
}
