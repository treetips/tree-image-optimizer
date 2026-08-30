/// 設定画面の設定値。
class SettingsScreenSettings {
  const SettingsScreenSettings({
    required this.showOsNotification,
    required this.playSound,
    required this.successSound,
    required this.errorSound,
    this.language = '',
  });

  /// アプリ内で定めている初期値。
  factory SettingsScreenSettings.defaults() {
    return const SettingsScreenSettings(
      showOsNotification: false,
      playSound: false,
      successSound: 'assets/sounds/success/decision49.mp3',
      errorSound: 'assets/sounds/error/beep1.mp3',
      language: '',
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

  SettingsScreenSettings copyWith({
    bool? showOsNotification,
    bool? playSound,
    String? successSound,
    String? errorSound,
    String? language,
  }) {
    return SettingsScreenSettings(
      showOsNotification: showOsNotification ?? this.showOsNotification,
      playSound: playSound ?? this.playSound,
      successSound: successSound ?? this.successSound,
      errorSound: errorSound ?? this.errorSound,
      language: language ?? this.language,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'showOsNotification': showOsNotification,
      'playSound': playSound,
      'successSound': successSound,
      'errorSound': errorSound,
      'language': language,
    };
  }
}
