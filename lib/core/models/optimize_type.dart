import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 最適化種別を表す。
enum OptimizeType {
  anime,
  photo,
  speed,
  quality;

  const OptimizeType();

  /// プルダウンに表示するラベル。
  String label(AppLocalizations l10n) => switch (this) {
    OptimizeType.anime => l10n.optimizeAnime,
    OptimizeType.photo => l10n.optimizePhoto,
    OptimizeType.speed => l10n.optimizeSpeed,
    OptimizeType.quality => l10n.optimizeQuality,
  };
}
