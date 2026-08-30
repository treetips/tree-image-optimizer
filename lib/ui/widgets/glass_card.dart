import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/glass_constants.dart';

/// Liquid Glass エフェクトを持つカード。
///
/// 共通のガラス効果をまとめるベースコンポーネント。
/// 設定値は [GlassConstants] で一元管理する。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    this.margin,
    this.borderRadius = GlassConstants.cardCornerRadius,
  });

  /// カードの内容。
  final Widget child;

  /// カード内のパディング。
  final EdgeInsetsGeometry padding;

  /// カード外のマージン。
  final EdgeInsetsGeometry? margin;

  /// 角の丸み。
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final style = borderRadius == GlassConstants.cardCornerRadius
        ? GlassConstants.cardLiquidStyle
        : LiquidGlassStyle(
            shape: LiquidGlassShape.continuousRoundedRectangle(
              cornerRadius: borderRadius,
              borderWidth: GlassConstants.cardBorderWidth,
              borderColor: const Color(0x4DFFFFFF),
              lightIntensity: 1.0,
              lightColor: const Color(0xB2FFFFFF),
              borderType: const OpticalBorder(
                borderSaturation: 1.2,
                ambientIntensity: 1.0,
              ),
            ),
            appearance: const LiquidGlassAppearance(
              color: Color(0x26FFFFFF),
              blur: LiquidGlassBlur(
                sigmaX: GlassConstants.blurSigma,
                sigmaY: GlassConstants.blurSigma,
              ),
              saturation: 1.0,
            ),
            refraction: const LiquidGlassRefraction(
              distortion: GlassConstants.cardDistortion,
              distortionWidth: GlassConstants.cardDistortionWidth,
              chromaticAberration: GlassConstants.cardChromaticAberration,
            ),
          );

    return Container(
      margin: margin,
      child: LiquidGlassLens(
        style: style,
        child: Container(padding: padding, child: child),
      ),
    );
  }
}

/// タイトルと中央揃えを持つ GlassCard。
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
