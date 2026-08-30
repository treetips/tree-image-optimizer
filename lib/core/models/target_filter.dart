import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 対象ファイルの絞り込み条件を表す。
enum TargetFilter {
  oneDay(Duration(days: 1)),
  threeDays(Duration(days: 3)),
  sevenDays(Duration(days: 7)),
  thirtyDays(Duration(days: 30)),
  all(null);

  const TargetFilter(this.duration);

  /// 更新日時から絞り込む期間。`全ファイル` の場合は null。
  final Duration? duration;

  /// プルダウンに表示するラベル。
  String label(AppLocalizations l10n) => switch (this) {
    TargetFilter.oneDay => l10n.targetFilterOneDay,
    TargetFilter.threeDays => l10n.targetFilterThreeDays,
    TargetFilter.sevenDays => l10n.targetFilterSevenDays,
    TargetFilter.thirtyDays => l10n.targetFilterThirtyDays,
    TargetFilter.all => l10n.targetFilterAll,
  };
}
