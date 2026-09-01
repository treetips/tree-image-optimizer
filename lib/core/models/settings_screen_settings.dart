import 'dart:ui';

/// 設定画面の設定値。
class SettingsScreenSettings {
  const SettingsScreenSettings({
    required this.showOsNotification,
    required this.playSound,
    required this.successSound,
    required this.errorSound,
    this.language = '',
    this.wallpaper = 'assets/images/wallpaper/wallpaper1.jpg',
    this.wallpaperOpacity = 1.0,
    this.wallpaperBackgroundColor = '#FFFFFF',
  });

  /// アプリ内で定めている初期値。
  factory SettingsScreenSettings.defaults() {
    return const SettingsScreenSettings(
      showOsNotification: false,
      playSound: false,
      successSound: 'assets/sounds/success/decision49.mp3',
      errorSound: 'assets/sounds/error/beep1.mp3',
      language: '',
      wallpaper: 'assets/images/wallpaper/wallpaper1.jpg',
      wallpaperOpacity: 1.0,
      wallpaperBackgroundColor: '#FFFFFF',
    );
  }

  /// OSの通知を表示するかどうか。
  final bool showOsNotification;

  /// サウンドを再生するかどうか。
  final bool playSound;

  /// 成功時のサウンドの再生ソース。
  final String successSound;

  /// 失敗時のサウンドの再生ソース。
  final String errorSound;

  /// 選択された表示言語（BCP 47）。空文字は「環境設定に従う」を意味する。
  final String language;

  /// 背景画像のパス。
  /// 同梱壁紙はアセットパス、ユーザー壁紙は絶対パス。
  final String wallpaper;

  /// 背景画像の透明度 (0.0〜1.0)。
  final double wallpaperOpacity;

  /// 背景色 (hex, 例: #FFFFFF)。
  final String wallpaperBackgroundColor;

  SettingsScreenSettings copyWith({
    bool? showOsNotification,
    bool? playSound,
    String? successSound,
    String? errorSound,
    String? language,
    String? wallpaper,
    double? wallpaperOpacity,
    String? wallpaperBackgroundColor,
  }) {
    return SettingsScreenSettings(
      showOsNotification: showOsNotification ?? this.showOsNotification,
      playSound: playSound ?? this.playSound,
      successSound: successSound ?? this.successSound,
      errorSound: errorSound ?? this.errorSound,
      language: language ?? this.language,
      wallpaper: wallpaper ?? this.wallpaper,
      wallpaperOpacity: wallpaperOpacity ?? this.wallpaperOpacity,
      wallpaperBackgroundColor:
          wallpaperBackgroundColor ?? this.wallpaperBackgroundColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'showOsNotification': showOsNotification,
      'playSound': playSound,
      'successSound': successSound,
      'errorSound': errorSound,
      'language': language,
      'wallpaper': wallpaper,
      'wallpaperOpacity': wallpaperOpacity,
      'wallpaperBackgroundColor': wallpaperBackgroundColor,
    };
  }

  /// 背景色を [Color] に変換する。不正な値の場合は白を返す。
  Color get wallpaperBackgroundColorValue {
    return _parseColor(wallpaperBackgroundColor) ?? const Color(0xFFFFFFFF);
  }

  static Color? _parseColor(String hex) {
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(v);
  }
}
