import 'package:material_ui/material_ui.dart';

/// デザイン画に準拠したUI用の色定数。
class AppColors {
  AppColors._();

  /// テーブルヘッダー・選択ボタン・プログレスバー等に使う基本の青。
  static const Color primary = Color(0xFF2B5CFF);

  /// 変換実行・アップデート確認などのアクションボタンに使うピンク。
  static const Color action = Color(0xFFF0328C);

  /// サイドバーの背景色。
  static const Color sidebar = Color(0xFFD9E6F8);

  /// サイドバーの選択中アイテムの背景色。
  static const Color sidebarSelected = Color(0xFF4A90E2);

  /// 情報アイコンの背景色。
  static const Color info = Color(0xFF4A90E2);

  /// バリデーションエラー（パス不存在等）に使う赤色。
  static const Color error = Color(0xFFE53935);
}
