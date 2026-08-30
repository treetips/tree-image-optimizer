import 'dart:async';
import 'dart:developer' as dev;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/constants/app_constants.dart';
import 'logic/update/update_actions.dart';

/// ログのタグ。
const _tag = 'Main';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  dev.log('App starting...', name: _tag);

  final container = ProviderContainer();
  await container.read(logServiceProvider).init();
  await container.read(notificationServiceProvider).init();
  dev.log('Services initialized', name: _tag);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TreeImageOptimizerApp(),
    ),
  );
  dev.log('runApp completed', name: _tag);

  // 起動時の自動更新チェック (非同期・ダイアログなし)。
  final updaterService = container.read(updaterServiceProvider);
  unawaited(
    runBackgroundUpdateCheck(
      updaterService: updaterService,
      updateInfoUrl: AppConstants.updateInfoUrl,
    ),
  );
}
