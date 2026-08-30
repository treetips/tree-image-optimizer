import 'dart:ui';

import 'package:material_ui/material_ui.dart';

/// Apple Liquid Glass 風のガラスエフェクトを適用するウィジェット。
///
/// `BackdropFilter` を使い、背景をブラーしてガラス風の見た目を実現する。
/// テスト環境でも安全に動作する。
class GlassEffect extends StatelessWidget {
  const GlassEffect({
    super.key,
    required this.child,
    this.sigmaX = 10,
    this.sigmaY = 10,
    this.tint = const Color(0x18FFFFFF),
  });

  final Widget child;
  final double sigmaX;
  final double sigmaY;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
        child: ColoredBox(color: tint, child: child),
      ),
    );
  }
}

/// ガラス背景のコンテナ。
///
/// `ClipRRect` + `BackdropFilter` で frosted glass を実現する。
/// テスト環境でも安全に動作する。
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.tint = const Color(0x18FFFFFF),
    this.borderColor,
    this.borderWidth = 1,
    this.borderRadius = 12,
    this.padding,
    this.margin,
    this.sigmaX = 12,
    this.sigmaY = 12,
  });

  final Widget child;
  final Color tint;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double sigmaX;
  final double sigmaY;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
          child: Container(
            decoration: BoxDecoration(
              color: tint,
              border: Border.all(
                color: borderColor ?? const Color(0x30FFFFFF),
                width: borderWidth,
              ),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ),
        ),
      ),
    );
  }
}
