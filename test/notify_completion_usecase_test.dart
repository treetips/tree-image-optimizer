import 'dart:ui';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tree_image_optimizer/core/models/settings_screen_settings.dart';
import 'package:tree_image_optimizer/data/repositories/settings_repository.dart';
import 'package:tree_image_optimizer/data/services/notification_service.dart';
import 'package:tree_image_optimizer/data/services/sound_service.dart';
import 'package:tree_image_optimizer/logic/usecases/notify_completion_usecase.dart';

class _FakeSoundService extends SoundService {
  String? playedSource;

  @override
  Future<void> play(String source) async {
    playedSource = source;
  }
}

class _FakeNotificationService extends NotificationService {
  String? shownTitle;
  String? shownBody;

  @override
  Future<void> show({required String title, required String body}) async {
    shownTitle = title;
    shownBody = body;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .localeTestValue = const Locale(
    'ja',
  );
  late Directory tempDir;
  late SettingsRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('notify_test');
    repository = SettingsRepository(configDirectory: tempDir);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('サウンドと通知の両方が有効な場合に再生と表示が行われる', () async {
    await repository.saveSettings(
      SettingsScreenSettings.defaults().copyWith(
        showOsNotification: true,
        playSound: true,
        successSound: 'assets/sounds/success/decision49.mp3',
        errorSound: 'assets/sounds/error/beep1.mp3',
      ),
    );

    final sound = _FakeSoundService();
    final notification = _FakeNotificationService();
    final useCase = NotifyCompletionUseCase(
      settingsRepository: repository,
      soundService: sound,
      notificationService: notification,
    );

    await useCase.execute(allSuccess: true);

    expect(sound.playedSource, 'assets/sounds/success/decision49.mp3');
    expect(notification.shownTitle, 'Tree Image Optimizer');
    expect(notification.shownBody, '🟢 変換処理が成功しました。');
  });

  test('失敗時は失敗サウンドと失敗通知になる', () async {
    await repository.saveSettings(
      SettingsScreenSettings.defaults().copyWith(
        showOsNotification: true,
        playSound: true,
        successSound: 'assets/sounds/success/decision49.mp3',
        errorSound: 'assets/sounds/error/beep1.mp3',
      ),
    );

    final sound = _FakeSoundService();
    final notification = _FakeNotificationService();
    final useCase = NotifyCompletionUseCase(
      settingsRepository: repository,
      soundService: sound,
      notificationService: notification,
    );

    await useCase.execute(allSuccess: false);

    expect(sound.playedSource, 'assets/sounds/error/beep1.mp3');
    expect(notification.shownBody, '🔴 変換処理が失敗しました。');
  });

  test('無効な場合は何も実行されない', () async {
    await repository.saveSettings(SettingsScreenSettings.defaults());

    final sound = _FakeSoundService();
    final notification = _FakeNotificationService();
    final useCase = NotifyCompletionUseCase(
      settingsRepository: repository,
      soundService: sound,
      notificationService: notification,
    );

    await useCase.execute(allSuccess: true);

    expect(sound.playedSource, isNull);
    expect(notification.shownTitle, isNull);
  });
}
