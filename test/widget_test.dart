import 'dart:io';

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tree_image_optimizer/app/app.dart';
import 'package:tree_image_optimizer/app/providers.dart';
import 'package:tree_image_optimizer/data/services/tool_installer.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .localeTestValue = const Locale(
    'ja',
  );
  testWidgets('アプリが起動する', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          toolInstallerProvider.overrideWithValue(_FakeToolInstaller()),
        ],
        child: const TreeImageOptimizerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('画像変換'), findsWidgets);
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });
}
