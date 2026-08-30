import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/glass_constants.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 共通の Liquid Glass ボタン。
///
/// 各画面で `LiquidGlassLens` を直接使わず、このコンポーネント経由で
/// スタイルを一元管理する。`GlassConstants` のボタン用スタイルを使用する。
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.width = double.infinity,
    this.height = GlassConstants.buttonHeight,
  });

  /// ボタンのラベル。
  final String label;

  /// 先頭アイコン。`isLoading` 時は非表示になる。
  final IconData? icon;

  /// タップ時のコールバック。`null` の場合は無効状態。
  final VoidCallback? onPressed;

  /// ローディング中かどうか。`true` の場合はインジケータを表示する。
  final bool isLoading;

  /// ボタンの幅。デフォルトは `double.infinity`。
  final double? width;

  /// ボタンの高さ。
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final style = enabled
        ? GlassConstants.runButtonLiquidStyle
        : GlassConstants.runButtonDisabledLiquidStyle;

    return SizedBox(
      width: width,
      height: height,
      child: LiquidGlassLens(
        style: style,
        touch: enabled ? const LiquidGlassTouch(flex: LiquidGlassFlex()) : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(
              GlassConstants.buttonCornerRadius,
            ),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black87,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 18, color: Colors.black87),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: TextStyle(
                            color: enabled ? Colors.black87 : Colors.black45,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 変換実行用の特殊化（絵文字付きラベルを扱う）。
class GlassRunButton extends StatelessWidget {
  const GlassRunButton({
    super.key,
    required this.canRun,
    required this.isRunning,
    required this.onPressed,
  });

  final bool canRun;
  final bool isRunning;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: AppLocalizations.of(context)!.runConversion,
      isLoading: isRunning,
      onPressed: canRun && !isRunning ? onPressed : null,
      width: double.infinity,
    );
  }
}
