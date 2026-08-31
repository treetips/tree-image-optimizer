import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 出力フォーマットを表す。
enum OutputFormat {
  jpeg,
  png,
  jpegXl,
  av1,
  webp;

  const OutputFormat();

  /// プルダウンに表示するラベル。
  String label(AppLocalizations l10n) => switch (this) {
    OutputFormat.jpeg => l10n.formatJpeg,
    OutputFormat.png => l10n.formatPng,
    OutputFormat.jpegXl => l10n.formatJpegXl,
    OutputFormat.av1 => l10n.formatAv1,
    OutputFormat.webp => l10n.formatWebp,
  };

  /// 出力ファイルの拡張子。
  String get extension => switch (this) {
    OutputFormat.jpeg => '.jpg',
    OutputFormat.png => '.png',
    OutputFormat.jpegXl => '.jxl',
    OutputFormat.av1 => '.avif',
    OutputFormat.webp => '.webp',
  };
}
