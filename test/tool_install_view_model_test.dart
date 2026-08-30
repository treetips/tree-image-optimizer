import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tree_image_optimizer/data/services/tool_installer.dart';
import 'package:tree_image_optimizer/logic/viewmodels/tool_install_view_model.dart';

class _FakeInstaller extends ToolInstaller {
  _FakeInstaller({this.installed = false, this.fail = false}) : super();

  final bool installed;
  final bool fail;

  @override
  Future<bool> isInstalled() => Future.value(installed);

  @override
  Future<void> repairMissingTools({InstallProgress? onProgress}) async {
    if (fail) throw 'インストール失敗';
    if (!installed) {
      for (var i = 1; i <= 3; i++) {
        onProgress?.call(i, 3);
      }
    }
  }

  @override
  Future<void> install({InstallProgress? onProgress}) async {
    if (fail) throw 'インストール失敗';
    for (var i = 1; i <= 3; i++) {
      onProgress?.call(i, 3);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .localeTestValue = const Locale(
    'ja',
  );
  test('ツールが展開済みなら即 ready になる', () async {
    final vm = ToolInstallViewModel(installer: _FakeInstaller(installed: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.state.status, ToolInstallStatus.ready);
    vm.dispose();
  });

  test('未展開なら展開後に ready になる', () async {
    final vm = ToolInstallViewModel(installer: _FakeInstaller());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.state.status, ToolInstallStatus.ready);
    expect(vm.state.total, 3);
    expect(vm.state.completed, 3);
    vm.dispose();
  });

  test('展開失敗時は failure になる', () async {
    final vm = ToolInstallViewModel(installer: _FakeInstaller(fail: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vm.state.status, ToolInstallStatus.failure);
    vm.dispose();
  });
}
