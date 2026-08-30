import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import '../../core/models/settings_screen_settings.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/sound_service.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 変換完了時の通知・サウンド再生を実行するユースケース。
class NotifyCompletionUseCase {
  NotifyCompletionUseCase({
    required this.settingsRepository,
    required this.soundService,
    required this.notificationService,
  });

  final SettingsRepository settingsRepository;
  final SoundService soundService;
  final NotificationService notificationService;

  /// プラットフォームのロケールから対応する AppLocalizations を解決する。
  ///
  /// 未対応の言語の場合は日本語へフォールバックする。
  AppLocalizations _resolveLocalizations() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final languageCode = dispatcher.locale.languageCode;
    final locale = switch (languageCode) {
      'ja' => const ui.Locale('ja'),
      'en' => const ui.Locale('en'),
      _ => const ui.Locale('ja'),
    };
    return lookupAppLocalizations(locale);
  }

  /// [allSuccess] が true なら成功、false なら失敗として扱う。
  /// 設定画面の `変換終了時のアクション` に従ってOS通知とサウンドを実行する。
  Future<void> execute({required bool allSuccess}) async {
    final settings = await settingsRepository.loadSettings(
      SettingsScreenSettings.defaults(),
    );

    if (settings.playSound) {
      await soundService.play(
        allSuccess ? settings.successSound : settings.errorSound,
      );
    }

    if (settings.showOsNotification) {
      final l10n = _resolveLocalizations();
      await notificationService.show(
        title: l10n.appTitle,
        body: allSuccess ? l10n.notifySuccess : l10n.notifyFailure,
      );
    }
  }
}
