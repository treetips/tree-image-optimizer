import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import 'glass_card.dart';

export 'glass_card.dart' show GlassCard;

/// 各画面の上部に表示する画面タイトル。
class ScreenTitle extends StatelessWidget {
  const ScreenTitle({super.key, required this.title});

  /// 画面のタイトル。
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}

/// タイトルと中央揃えを持つセクションカード。
///
/// [GlassCard] を使い、Liquid Glass エフェクトを適用する。
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  /// セクションのタイトル。
  final String title;

  /// セクションの内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// ホバーすると説明を表示する popover アイコン。
class InfoTooltip extends StatelessWidget {
  const InfoTooltip({super.key, required this.text});

  /// ホバーで表示する説明。
  final String text;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: text,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.info,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.info, color: Colors.white, size: 16),
      ),
    );
  }
}
