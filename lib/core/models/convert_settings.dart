import 'dart:math';

import 'optimize_type.dart';
import 'output_format.dart';
import 'target_filter.dart';

/// 変換画面の設定値。
class ConvertSettings {
  const ConvertSettings({
    this.inputFolderPath,
    this.outputFolderPath,
    required this.targetFilter,
    required this.scale,
    required this.model,
    required this.format,
    required this.optimizeType,
    required this.quality,
    required this.parallelCount,
  });

  /// アプリ内で定めている初期値から生成する。
  factory ConvertSettings.defaults({required int maxParallel}) {
    return ConvertSettings(
      targetFilter: TargetFilter.sevenDays,
      scale: 2,
      model: 'realesr-animevideov3-x4',
      format: OutputFormat.jpegXl,
      optimizeType: OptimizeType.anime,
      quality: 80,
      parallelCount: max(1, (maxParallel / 2).floor() - 1),
    );
  }

  /// 入力フォルダのパス。
  final String? inputFolderPath;

  /// 出力フォルダのパス。
  final String? outputFolderPath;

  final TargetFilter targetFilter;
  final int scale;
  final String model;
  final OutputFormat format;
  final OptimizeType optimizeType;
  final int quality;
  final int parallelCount;

  ConvertSettings copyWith({
    String? inputFolderPath,
    String? outputFolderPath,
    TargetFilter? targetFilter,
    int? scale,
    String? model,
    OutputFormat? format,
    OptimizeType? optimizeType,
    int? quality,
    int? parallelCount,
  }) {
    return ConvertSettings(
      inputFolderPath: inputFolderPath ?? this.inputFolderPath,
      outputFolderPath: outputFolderPath ?? this.outputFolderPath,
      targetFilter: targetFilter ?? this.targetFilter,
      scale: scale ?? this.scale,
      model: model ?? this.model,
      format: format ?? this.format,
      optimizeType: optimizeType ?? this.optimizeType,
      quality: quality ?? this.quality,
      parallelCount: parallelCount ?? this.parallelCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (inputFolderPath != null) 'inputFolderPath': inputFolderPath,
      if (outputFolderPath != null) 'outputFolderPath': outputFolderPath,
      'targetFilter': targetFilter.name,
      'scale': scale,
      'model': model,
      'format': format.name,
      'optimizeType': optimizeType.name,
      'quality': quality,
      'parallelCount': parallelCount,
    };
  }
}
