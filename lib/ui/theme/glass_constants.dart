import 'dart:ui';

import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_ui/material_ui.dart';

/// Liquid Glass エフェクトの共通定数。
///
/// 数値はここで一元管理し、`GlassCard` / `HomeShell` 等は
/// この定数を参照する。`BackdropFilter` 用の旧定数と
/// `liquid_glass_easy` 用の `LiquidGlassStyle` を併記する。
abstract final class GlassConstants {
  /// ブラーの強さ（旧 BackdropFilter / 新 LiquidGlass 共通）。
  static const double blurSigma = 8;

  // ── サイドバー ──

  /// サイドバーの背景色。
  static const Color sidebarBaseColor = Color(0xFFD9E6F8);

  /// サイドバーの背景透明度。
  static const double sidebarOpacity = 0.10;

  /// サイドバーのグラデーション（上）。
  static const double sidebarGradientTop = 0.08;

  /// サイドバーのグラデーション（下）。
  static const double sidebarGradientBottom = 0.02;

  /// サイドバーのボーダー色。
  static const Color sidebarBorderColor = Colors.grey;

  /// サイドバーのボーダー透明度。
  static const double sidebarBorderOpacity = 0.50;

  /// サイドバーの角丸。
  static const double sidebarCornerRadius = 0;

  /// サイドバーのボーダー幅。
  static const double sidebarBorderWidth = 1.5;

  /// サイドバーの屈折歪み強度。
  static const double sidebarDistortion = 0.06;

  /// サイドバーの歪み帯幅。
  static const double sidebarDistortionWidth = 20;

  // ── カード ──

  /// カードの背景色。
  static const Color cardBaseColor = Colors.white;

  /// カードの背景透明度。
  static const double cardOpacity = 0.15;

  /// カードのボーダー色。
  static const Color cardBorderColor = Colors.white;

  /// カードのボーダー透明度。
  static const double cardBorderOpacity = 0.30;

  /// カードのグラデーション（上）。
  static const double cardGradientTop = 0.25;

  /// カードのグラデーション（下）。
  static const double cardGradientBottom = 0.08;

  /// カードの角丸。
  static const double cardCornerRadius = 12;

  /// カードのボーダー幅。
  static const double cardBorderWidth = 1.5;

  /// カードの屈折歪み強度。
  static const double cardDistortion = 0.10;

  /// カードの歪み帯幅。
  static const double cardDistortionWidth = 28;

  /// カードの色収差。
  static const double cardChromaticAberration = 0.002;

  // ── ボタン ──

  /// ボタンの高さ（サンプル画像のような薄いピル形状にするため 44→38）。
  static const double buttonHeight = 38;

  /// ボタンの角丸（ピル形状 = height/2）。
  static const double buttonCornerRadius = 19;

  /// ボタンのボーダー幅。
  static const double buttonBorderWidth = 1.0;

  /// ボタンの屈折歪み強度（公式サンプルのような繊細な屈折）。
  static const double buttonDistortion = 0.07;

  /// ボタンの歪み帯幅。
  static const double buttonDistortionWidth = 22;

  /// ボタンの色収差。
  static const double buttonChromaticAberration = 0.002;

  // ── 先頭に戻るボタン ──

  /// 先頭に戻るボタンのサイズ（丸形）。
  static const double backToTopSize = 48;

  /// 先頭に戻るボタンの角丸（丸形 = size/2）。
  static const double backToTopCornerRadius = 24;

  // ── 計算プロパティ（旧 BackdropFilter 用） ──

  /// サイドバーの背景色（透明度付き）。
  static Color get sidebarColor =>
      sidebarBaseColor.withValues(alpha: sidebarOpacity);

  /// サイドバーのボーダー色（透明度付き）。
  static Color get sidebarBorder =>
      sidebarBorderColor.withValues(alpha: sidebarBorderOpacity);

  /// カードの背景色（透明度付き）。
  static Color get cardColor => cardBaseColor.withValues(alpha: cardOpacity);

  /// カードのボーダー色（透明度付き）。
  static Color get cardBorder =>
      cardBorderColor.withValues(alpha: cardBorderOpacity);

  /// 共通の ImageFilter.blur を返す。
  static ImageFilter get blur =>
      ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma);

  // ── LiquidGlass 用スタイル（一元管理） ──

  /// サイドバー用 LiquidGlassStyle。
  static const LiquidGlassStyle sidebarLiquidStyle = LiquidGlassStyle(
    shape: LiquidGlassShape.roundedRectangle(
      cornerRadius: sidebarCornerRadius,
      borderWidth: sidebarBorderWidth,
      borderColor: Color(0x80B0B0B0),
      lightIntensity: 0.8,
      borderType: OpticalBorder(borderSaturation: 1.0, ambientIntensity: 0.8),
    ),
    appearance: LiquidGlassAppearance(
      color: Color(0x1AD9E6F8),
      blur: LiquidGlassBlur(sigmaX: blurSigma, sigmaY: blurSigma),
      saturation: 1.1,
    ),
    refraction: LiquidGlassRefraction(
      distortion: sidebarDistortion,
      distortionWidth: sidebarDistortionWidth,
      chromaticAberration: 0.002,
    ),
  );

  /// カード用 LiquidGlassStyle（通知のようなグラス感）。
  static const LiquidGlassStyle cardLiquidStyle = LiquidGlassStyle(
    shape: LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: cardCornerRadius,
      borderWidth: cardBorderWidth,
      borderColor: Color(0x33FFFFFF),
      lightIntensity: 1.2,
      lightColor: Color(0xCCFFFFFF),
      borderType: OpticalBorder(borderSaturation: 1.5, ambientIntensity: 1.2),
    ),
    appearance: LiquidGlassAppearance(
      color: Color(0x1AFFFFFF),
      blur: LiquidGlassBlur(sigmaX: 16, sigmaY: 16),
      saturation: 1.15,
      shadow: LiquidGlassShadow(
        blur: 12,
        opacity: 0.18,
        offset: Offset(0, 6),
        cornerRadius: cardCornerRadius,
      ),
    ),
    refraction: LiquidGlassRefraction(
      distortion: 0.14,
      distortionWidth: 32,
      chromaticAberration: 0.004,
      refractionMode: LiquidGlassRefractionMode.shapeRefraction,
    ),
  );

  /// 変換実行ボタン用 LiquidGlassStyle（背景透明＋強いピンクの細いボーダー＋ピンクグロウ）。
  static const LiquidGlassStyle runButtonLiquidStyle = LiquidGlassStyle(
    shape: LiquidGlassShape.roundedRectangle(
      cornerRadius: buttonCornerRadius,
      borderWidth: 1.0,
      borderColor: Color(0xE6FF6BA8),
      lightIntensity: 1.3,
      lightColor: Color(0xCCFFFFFF),
      borderType: OpticalBorder(borderSaturation: 1.8, ambientIntensity: 1.3),
    ),
    appearance: LiquidGlassAppearance(
      color: Color(0x00000000),
      blur: LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
      saturation: 1.1,
      shadow: LiquidGlassShadow(
        blur: 20,
        opacity: 0.5,
        color: Color(0xFFF0328C),
        offset: Offset(0, 0),
        cornerRadius: buttonCornerRadius,
      ),
    ),
    refraction: LiquidGlassRefraction(
      distortion: buttonDistortion,
      distortionWidth: buttonDistortionWidth,
      chromaticAberration: buttonChromaticAberration,
      refractionMode: LiquidGlassRefractionMode.shapeRefraction,
    ),
  );

  /// 変換実行ボタン無効時用 LiquidGlassStyle（さらに薄く）。
  static const LiquidGlassStyle runButtonDisabledLiquidStyle = LiquidGlassStyle(
    shape: LiquidGlassShape.roundedRectangle(
      cornerRadius: buttonCornerRadius,
      borderWidth: buttonBorderWidth,
      borderColor: Color(0x1AFFFFFF),
      lightIntensity: 0.5,
      borderType: OpticalBorder(borderSaturation: 0.7, ambientIntensity: 0.5),
    ),
    appearance: LiquidGlassAppearance(
      color: Color(0x0DFFFFFF),
      blur: LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
      saturation: 0.7,
      shadow: LiquidGlassShadow(
        blur: 6,
        opacity: 0.1,
        offset: Offset(0, 3),
        cornerRadius: buttonCornerRadius,
      ),
    ),
    refraction: LiquidGlassRefraction(
      distortion: 0.03,
      distortionWidth: buttonDistortionWidth,
      chromaticAberration: 0.001,
    ),
  );

  /// アップデート確認ボタン用 LiquidGlassStyle（同様に背景透明＋強いピンクボーダー＋ピンクグロウ）。
  static const LiquidGlassStyle updateButtonLiquidStyle = LiquidGlassStyle(
    shape: LiquidGlassShape.roundedRectangle(
      cornerRadius: buttonCornerRadius,
      borderWidth: 1.0,
      borderColor: Color(0xE6FF6BA8),
      lightIntensity: 1.3,
      lightColor: Color(0xCCFFFFFF),
      borderType: OpticalBorder(borderSaturation: 1.8, ambientIntensity: 1.3),
    ),
    appearance: LiquidGlassAppearance(
      color: Color(0x00000000),
      blur: LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
      saturation: 1.1,
      shadow: LiquidGlassShadow(
        blur: 20,
        opacity: 0.5,
        color: Color(0xFFF0328C),
        offset: Offset(0, 0),
        cornerRadius: buttonCornerRadius,
      ),
    ),
    refraction: LiquidGlassRefraction(
      distortion: buttonDistortion,
      distortionWidth: buttonDistortionWidth,
      chromaticAberration: buttonChromaticAberration,
    ),
  );

  /// 画面の先頭に戻るボタン用 LiquidGlassStyle（丸形・透明グラス＋ピンクグロウ）。
  static const LiquidGlassStyle backToTopLiquidStyle = LiquidGlassStyle(
    shape: LiquidGlassShape.roundedRectangle(
      cornerRadius: backToTopCornerRadius,
      borderWidth: 1.0,
      borderColor: Color(0x66FF6BA8),
      lightIntensity: 1.1,
      lightColor: Color(0xCCFFFFFF),
      borderType: OpticalBorder(borderSaturation: 1.4, ambientIntensity: 1.0),
    ),
    appearance: LiquidGlassAppearance(
      color: Color(0x00000000),
      blur: LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
      saturation: 1.1,
      shadow: LiquidGlassShadow(
        blur: 16,
        opacity: 0.35,
        color: Color(0xFFF0328C),
        offset: Offset(0, 0),
        cornerRadius: backToTopCornerRadius,
      ),
    ),
    refraction: LiquidGlassRefraction(
      distortion: 0.08,
      distortionWidth: 24,
      chromaticAberration: 0.003,
      refractionMode: LiquidGlassRefractionMode.shapeRefraction,
    ),
  );
}
