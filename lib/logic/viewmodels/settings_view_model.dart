import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/settings_screen_settings.dart';
import '../../core/models/sound_option.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/sound_service.dart';

/// 設定画面の状態。
class SettingsState {
  const SettingsState({
    this.upscalBinVersion = AppConstants.upscalBinVersion,
    this.upscalModelsVersion = '',
    this.jpegVersion = AppConstants.jpegVersion,
    this.pngVersion = AppConstants.pngVersion,
    this.jpegXlVersion = AppConstants.jpegXlVersion,
    this.av1Version = AppConstants.av1Version,
    this.showOsNotification = false,
    this.playSound = false,
    this.successSound = '',
    this.errorSound = '',
    this.language = '',
    this.successSounds = const [],
    this.errorSounds = const [],
  });

  /// upscal-bin のバージョン。
  final String upscalBinVersion;

  /// upscal models のバージョン（GitHub Releasesで管理されていないため空）。
  final String upscalModelsVersion;

  /// JPEG (jpegoptim) のバージョン。
  final String jpegVersion;

  /// PNG (pngoptim) のバージョン。
  final String pngVersion;

  /// JPEG XL のバージョン。
  final String jpegXlVersion;

  /// AV1 のバージョン。
  final String av1Version;

  final bool showOsNotification;
  final bool playSound;
  final String successSound;
  final String errorSound;

  /// 選択された表示言語（BCP 47）。空文字は「環境設定に従う」を意味する。
  final String language;

  final List<SoundOption> successSounds;
  final List<SoundOption> errorSounds;

  SettingsState copyWith({
    bool? showOsNotification,
    bool? playSound,
    String? successSound,
    String? errorSound,
    String? language,
    List<SoundOption>? successSounds,
    List<SoundOption>? errorSounds,
  }) {
    return SettingsState(
      upscalBinVersion: upscalBinVersion,
      upscalModelsVersion: upscalModelsVersion,
      jpegVersion: jpegVersion,
      pngVersion: pngVersion,
      jpegXlVersion: jpegXlVersion,
      av1Version: av1Version,
      showOsNotification: showOsNotification ?? this.showOsNotification,
      playSound: playSound ?? this.playSound,
      successSound: successSound ?? this.successSound,
      errorSound: errorSound ?? this.errorSound,
      language: language ?? this.language,
      successSounds: successSounds ?? this.successSounds,
      errorSounds: errorSounds ?? this.errorSounds,
    );
  }
}

/// 設定画面のビューモデル。
class SettingsViewModel extends StateNotifier<SettingsState> {
  SettingsViewModel({this.settingsRepository, this.soundService})
    : super(const SettingsState()) {
    _load();
  }

  final SettingsRepository? settingsRepository;
  final SoundService? soundService;

  Future<void> _load() async {
    final repository = settingsRepository;
    if (repository != null) {
      final settings = await repository.loadSettings(
        SettingsScreenSettings.defaults(),
      );
      if (!mounted) return;
      state = state.copyWith(
        showOsNotification: settings.showOsNotification,
        playSound: settings.playSound,
        successSound: settings.successSound,
        errorSound: settings.errorSound,
        language: settings.language,
      );
    }

    final service = soundService;
    if (service != null) {
      final successSounds = await service.listSounds(success: true);
      final errorSounds = await service.listSounds(success: false);
      if (!mounted) return;
      state = state.copyWith(
        successSounds: successSounds,
        errorSounds: errorSounds,
        successSound: _resolveSelected(state.successSound, successSounds),
        errorSound: _resolveSelected(state.errorSound, errorSounds),
      );
    }
  }

  /// 選択中のサウンドが一覧に無い場合は先頭の選択肢で補正する。
  String _resolveSelected(String current, List<SoundOption> options) {
    if (options.isEmpty) return current;
    if (options.any((o) => o.source == current)) return current;
    return options.first.source;
  }

  void _save() {
    final repository = settingsRepository;
    if (repository == null) return;
    final s = state;
    repository.saveSettings(
      SettingsScreenSettings(
        showOsNotification: s.showOsNotification,
        playSound: s.playSound,
        successSound: s.successSound,
        errorSound: s.errorSound,
        language: s.language,
      ),
    );
  }

  void setShowOsNotification(bool value) {
    state = state.copyWith(showOsNotification: value);
    _save();
  }

  void setPlaySound(bool value) {
    state = state.copyWith(playSound: value);
    _save();
  }

  void setSuccessSound(String value) {
    state = state.copyWith(successSound: value);
    _save();
  }

  void setErrorSound(String value) {
    state = state.copyWith(errorSound: value);
    _save();
  }

  /// 成功時のサウンドを再生する。
  Future<void> playSuccessSound() async {
    final source = state.successSound;
    if (source.isEmpty) return;
    await soundService?.play(source);
  }

  /// 失敗時のサウンドを再生する。
  Future<void> playErrorSound() async {
    final source = state.errorSound;
    if (source.isEmpty) return;
    await soundService?.play(source);
  }

  /// 表示言語（BCP 47）を変更して保存する。空文字は「環境設定に従う」。
  void setLanguage(String value) {
    state = state.copyWith(language: value);
    _save();
  }
}
