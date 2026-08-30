import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tree_image_optimizer/core/models/optimize_type.dart';
import 'package:tree_image_optimizer/core/models/output_format.dart';
import 'package:tree_image_optimizer/core/models/process_status.dart';
import 'package:tree_image_optimizer/core/models/result.dart';
import 'package:tree_image_optimizer/core/models/target_filter.dart';
import 'package:tree_image_optimizer/data/repositories/convert_repository.dart';
import 'package:tree_image_optimizer/data/repositories/settings_repository.dart';
import 'package:tree_image_optimizer/data/services/compression_service.dart';
import 'package:tree_image_optimizer/data/services/notification_service.dart';
import 'package:tree_image_optimizer/data/services/sound_service.dart';
import 'package:tree_image_optimizer/logic/usecases/notify_completion_usecase.dart';
import 'package:tree_image_optimizer/data/services/path_service.dart';
import 'package:tree_image_optimizer/data/services/process_service.dart';
import 'package:tree_image_optimizer/data/services/upscale_service.dart';
import 'package:tree_image_optimizer/logic/usecases/compress_usecase.dart';
import 'package:tree_image_optimizer/logic/usecases/get_target_files_usecase.dart';
import 'package:tree_image_optimizer/logic/usecases/get_upscale_models_usecase.dart';
import 'package:tree_image_optimizer/logic/usecases/upscale_usecase.dart';
import 'package:tree_image_optimizer/logic/viewmodels/convert_view_model.dart';

ConvertRepository _fakeRepository() {
  final pathService = PathService();
  return ConvertRepository(
    pathService: pathService,
    upscaleService: UpscaleService(
      pathService: pathService,
      processService: ProcessService(),
    ),
    compressionService: CompressionService(
      pathService: pathService,
      processService: ProcessService(),
    ),
  );
}

class _FakeGetTargetFilesUseCase extends GetTargetFilesUseCase {
  _FakeGetTargetFilesUseCase(this.files) : super(_fakeRepository());
  final List<String> files;

  @override
  Future<Result<List<String>>> execute(String folderPath, TargetFilter filter) {
    return Future.value(Result.ok(files));
  }
}

class _FakeGetUpscaleModelsUseCase extends GetUpscaleModelsUseCase {
  _FakeGetUpscaleModelsUseCase() : super(_fakeRepository());

  @override
  Future<List<String>> execute() {
    return Future.value(const ['realesr-animevideov3-x4', '4xHFA2k']);
  }
}

class _FakeUpscaleUseCase extends UpscaleUseCase {
  _FakeUpscaleUseCase({this.shouldFail = false}) : super(_fakeRepository());
  final bool shouldFail;

  @override
  Future<Result<void>> execute({
    required String input,
    required String output,
    required int scale,
    required String model,
  }) {
    if (shouldFail) return Future.value(Result.fail('upscale error'));
    File(output).writeAsStringSync('upscaled');
    return Future.value(Result.ok(null));
  }
}

class _FakeCompressUseCase extends CompressUseCase {
  _FakeCompressUseCase({this.shouldFail = false}) : super(_fakeRepository());
  final bool shouldFail;

  @override
  Future<Result<void>> execute({
    required String input,
    required String output,
    required OutputFormat format,
    required OptimizeType optimizeType,
    required int quality,
    required int threads,
  }) {
    if (shouldFail) return Future.value(Result.fail('compress error'));
    File(output).writeAsStringSync('compressed');
    return Future.value(Result.ok(null));
  }
}

class _FakeNotifyCompletionUseCase extends NotifyCompletionUseCase {
  _FakeNotifyCompletionUseCase()
    : super(
        settingsRepository: SettingsRepository(
          configDirectory: Directory(
            '${Directory.systemTemp.path}/unused_notify',
          ),
        ),
        soundService: SoundService(),
        notificationService: NotificationService(),
      );

  final List<bool> calls = [];

  @override
  Future<void> execute({required bool allSuccess}) async {
    calls.add(allSuccess);
  }
}

void main() {
  late Directory tempDir;
  late Directory inputDir;
  late Directory outputDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tree_image_test');
    inputDir = Directory('${tempDir.path}/input')..createSync();
    outputDir = Directory('${tempDir.path}/output')..createSync();
  });
  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  ConvertViewModel buildViewModel({
    bool upscaleFails = false,
    bool compressFails = false,
    SettingsRepository? settingsRepository,
    NotifyCompletionUseCase? notifyCompletionUseCase,
  }) {
    return ConvertViewModel(
      getTargetFilesUseCase: _FakeGetTargetFilesUseCase([
        '${inputDir.path}/aaa.png',
        '${inputDir.path}/bbb.png',
      ]),
      getUpscaleModelsUseCase: _FakeGetUpscaleModelsUseCase(),
      upscaleUseCase: _FakeUpscaleUseCase(shouldFail: upscaleFails),
      compressUseCase: _FakeCompressUseCase(shouldFail: compressFails),
      settingsRepository: settingsRepository,
      notifyCompletionUseCase: notifyCompletionUseCase,
      processorCount: 4,
    );
  }

  group('ConvertViewModel', () {
    test('初期状態では実行ボタンが非活性', () {
      final vm = buildViewModel();
      expect(vm.state.canRun, isFalse);
      vm.dispose();
    });

    test('対象ファイルの初期値は7日以内', () {
      final vm = buildViewModel();
      expect(vm.state.targetFilter, TargetFilter.sevenDays);
      vm.dispose();
    });

    test('対象・出力フォルダ選択後に実行可能になる', () async {
      final vm = buildViewModel();
      vm.setInputFolderPath(inputDir.path);
      vm.setOutputFolderPath(outputDir.path);
      expect(vm.state.canRun, isTrue);
      vm.dispose();
    });

    test('初期並列数はCPUコア数の半分マイナス1', () {
      final vm = buildViewModel();
      expect(vm.state.parallelCount, 1); // (4 / 2) - 1 = 1
      expect(vm.maxParallel, 4);
      vm.dispose();
    });

    test('変換成功時に進捗率と成功件数が更新される', () async {
      final vm = buildViewModel();
      vm.setInputFolderPath(inputDir.path);
      vm.setOutputFolderPath(outputDir.path);

      await vm.runConversion();

      expect(vm.state.isRunning, isFalse);
      expect(vm.state.progressPercent, 100);
      expect(vm.state.successCount, 2);
      expect(vm.state.failureCount, 0);
      expect(vm.state.fileProgress.length, 2);
      expect(vm.state.fileProgress.first.outputStatus, ProcessStatus.success);

      // 出力ファイルは拡張子(.jxl)が付与されたファイル名で出力される。
      expect(File('${outputDir.path}/aaa.jxl').existsSync(), isTrue);
      expect(File('${outputDir.path}/bbb.jxl').existsSync(), isTrue);
      vm.dispose();
    });

    test('失敗時に失敗件数が更新される', () async {
      final vm = buildViewModel(upscaleFails: true);
      vm.setInputFolderPath(inputDir.path);
      vm.setOutputFolderPath(outputDir.path);

      await vm.runConversion();

      expect(vm.state.progressPercent, 100);
      expect(vm.state.failureCount, 2);
      expect(vm.state.successCount, 0);
      vm.dispose();
    });

    test('圧縮失敗時も失敗としてカウントされる', () async {
      final vm = buildViewModel(compressFails: true);
      vm.setInputFolderPath(inputDir.path);
      vm.setOutputFolderPath(outputDir.path);

      await vm.runConversion();

      expect(vm.state.failureCount, 2);
      expect(vm.state.successCount, 0);
      vm.dispose();
    });

    test('設定ファイルの値を起動時に復元する', () async {
      final settingsDir = Directory('${tempDir.path}/settings1');
      final repo = SettingsRepository(configDirectory: settingsDir);
      final file = File(
        '${settingsDir.path}/.config/tree-image-optimizer/settings.json',
      );
      file.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'convert': {
            'inputFolderPath': '/tmp/in',
            'outputFolderPath': '/tmp/out',
            'targetFilter': 'oneDay',
            'scale': 3,
            'model': '4xHFA2k',
            'format': 'av1',
            'optimizeType': 'photo',
            'quality': 90,
            'parallelCount': 2,
          },
        }),
      );

      final vm = buildViewModel(settingsRepository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vm.state.inputFolderPath, '/tmp/in');
      expect(vm.state.outputFolderPath, '/tmp/out');
      expect(vm.state.targetFilter, TargetFilter.oneDay);
      expect(vm.state.scale, 3);
      expect(vm.state.selectedModel, '4xHFA2k');
      expect(vm.state.format, OutputFormat.av1);
      expect(vm.state.optimizeType, OptimizeType.photo);
      expect(vm.state.quality, 90);
      expect(vm.state.parallelCount, 2);
      vm.dispose();
    });

    test('設定変更時に設定ファイルが更新される', () async {
      final settingsDir = Directory('${tempDir.path}/settings2');
      final repo = SettingsRepository(configDirectory: settingsDir);

      final vm = buildViewModel(settingsRepository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 各保存を逐次完了させてから次へ進む。
      vm.setScale(4);
      await vm.waitForSave();
      vm.setFormat(OutputFormat.av1);
      await vm.waitForSave();
      vm.setInputFolderPath('/tmp/input');
      await vm.waitForSave();
      vm.setOutputFolderPath('/tmp/output');
      await vm.waitForSave();

      final file = File(
        '${settingsDir.path}/.config/tree-image-optimizer/settings.json',
      );
      final json = jsonDecode(file.readAsStringSync());
      expect(json['convert']['scale'], 4);
      expect(json['convert']['format'], 'av1');
      expect(json['convert']['inputFolderPath'], '/tmp/input');
      expect(json['convert']['outputFolderPath'], '/tmp/output');
      vm.dispose();
    });

    test('全成功時は成功として完了通知を実行する', () async {
      final notify = _FakeNotifyCompletionUseCase();
      final vm = buildViewModel(notifyCompletionUseCase: notify);
      vm.setInputFolderPath(inputDir.path);
      vm.setOutputFolderPath(outputDir.path);

      await vm.runConversion();

      expect(notify.calls, [true]);
      vm.dispose();
    });

    test('失敗時は失敗として完了通知を実行する', () async {
      final notify = _FakeNotifyCompletionUseCase();
      final vm = buildViewModel(
        upscaleFails: true,
        notifyCompletionUseCase: notify,
      );
      vm.setInputFolderPath(inputDir.path);
      vm.setOutputFolderPath(outputDir.path);

      await vm.runConversion();

      expect(notify.calls, [false]);
      vm.dispose();
    });
  });
}
