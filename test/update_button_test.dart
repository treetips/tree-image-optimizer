import 'dart:io';

import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tree_image_optimizer/app/app.dart';
import 'package:tree_image_optimizer/app/providers.dart';
import 'package:tree_image_optimizer/data/services/tool_installer.dart';
import 'package:tree_image_optimizer/logic/update/updater_service.dart';

class _FakeToolInstaller extends ToolInstaller {
  _FakeToolInstaller() : super();

  @override
  Future<Directory> toolsDirectory() async {
    return Directory.systemTemp.createTempSync('fake_tools');
  }

  @override
  Future<bool> isInstalled() => Future.value(true);

  @override
  Future<void> repairMissingTools({InstallProgress? onProgress}) async {}

  @override
  Future<void> install({InstallProgress? onProgress}) async {}
}

class _FakeUpdaterService extends UpdaterService {
  _FakeUpdaterService() : super();
}

const Duration _pump = Duration(milliseconds: 100);
const Duration _settleTimeout = Duration(seconds: 5);
const EnginePhase _phase = EnginePhase.sendSemanticsUpdate;

Widget _app() {
  return ProviderScope(
    overrides: [
      toolInstallerProvider.overrideWithValue(_FakeToolInstaller()),
      updaterServiceProvider.overrideWithValue(_FakeUpdaterService()),
    ],
    child: const TreeImageOptimizerApp(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .localeTestValue = const Locale(
    'ja',
  );
  testWidgets('About画面に更新確認ボタンがある', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle(_pump, _phase, _settleTimeout);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle(_pump, _phase, _settleTimeout);

    expect(find.text('アップデートを確認'), findsOneWidget);
  });

  testWidgets('標準flutter/materialのMaterialLocalizationsが解決される', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle(_pump, _phase, _settleTimeout);

    final context = tester.element(find.text('画像変換').first);
    final l10n = m.MaterialLocalizations.of(context);
    expect(l10n.modalBarrierDismissLabel, isNotEmpty);
  });

  testWidgets('標準flutter/materialのshowDialogがアプリツリー内でクラッシュしない', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle(_pump, _phase, _settleTimeout);

    final context = tester.element(find.text('画像変換').first);

    final Future<void> dialogFuture = m.showDialog<void>(
      context: context,
      builder: (_) => const m.AlertDialog(title: m.Text('テストダイアログ')),
    );
    await tester.pumpAndSettle(_pump, _phase, _settleTimeout);

    expect(tester.takeException(), isNull);
    expect(find.text('テストダイアログ'), findsOneWidget);

    m.Navigator.of(context).pop();
    await tester.pumpAndSettle(_pump, _phase, _settleTimeout);
    await dialogFuture;
  });
}
