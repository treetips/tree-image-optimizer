import '../models/output_format.dart';
import '../models/optimize_type.dart';
import '../models/target_filter.dart';

/// 変換処理の設定を表す。
class ConvertConfig {
  const ConvertConfig({
    this.inputFolderPath,
    this.outputFolderPath,
    this.targetFilter = TargetFilter.sevenDays,
    this.scale = 2,
    this.model = 'realesr-animevideov3-x4',
    this.format = OutputFormat.jpegXl,
    this.optimizeType = OptimizeType.anime,
    this.quality = 80,
    this.parallelCount = 1,
  });

  /// 対象フォルダのパス。
  final String? inputFolderPath;

  /// 出力フォルダのパス。
  final String? outputFolderPath;

  /// 対象ファイルの絞り込み条件。
  final TargetFilter targetFilter;

  /// 拡大率。
  final int scale;

  /// アップスケールモデル名。
  final String model;

  /// 出力フォーマット。
  final OutputFormat format;

  /// 最適化種別。
  final OptimizeType optimizeType;

  /// 品質。
  final int quality;

  /// 並列数。
  final int parallelCount;
}
