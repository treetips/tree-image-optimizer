import 'dart:ui';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tree_image_optimizer/core/models/convert_settings.dart';
import 'package:tree_image_optimizer/core/models/optimize_type.dart';
import 'package:tree_image_optimizer/core/models/output_format.dart';
import 'package:tree_image_optimizer/core/models/settings_screen_settings.dart';
import 'package:tree_image_optimizer/core/models/target_filter.dart';
import 'package:tree_image_optimizer/data/repositories/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .localeTestValue = const Locale(
    'ja',
  );
  late Directory tempDir;
  late SettingsRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('settings_test');
    repository = SettingsRepository(configDirectory: tempDir);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  final defaults = ConvertSettings.defaults(maxParallel: 4);

  File settingsFile() =>
      File('${tempDir.path}/.config/tree-image-optimizer/settings.json');

  void writeSettings(Map<String, dynamic> json) {
    final file = settingsFile();
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode({'convert': json}));
  }

  group('SettingsRepository', () {
    test('ファイルが無い場合は初期値を保存して返す', () async {
      final settings = await repository.loadConvert(defaults, maxParallel: 4);

      expect(settings.targetFilter, TargetFilter.sevenDays);
      expect(settings.scale, 2);
      expect(settings.model, 'realesr-animevideov3-x4');
      expect(settings.format, OutputFormat.jpegXl);
      expect(settings.optimizeType, OptimizeType.anime);
      expect(settings.quality, 80);
      expect(settings.parallelCount, 1);

      expect(settingsFile().existsSync(), isTrue);
      final json = jsonDecode(settingsFile().readAsStringSync());
      // トップレベルは画面ごとのキーで、変換画面は convert 配下に保存される。
      expect(json['convert']['targetFilter'], 'sevenDays');
      expect(json['convert']['scale'], 2);
    });

    test('保存した設定値を読み込める', () async {
      await repository.saveConvert(
        defaults.copyWith(
          inputFolderPath: '/tmp/input',
          outputFolderPath: '/tmp/output',
          targetFilter: TargetFilter.oneDay,
          scale: 4,
          model: '4xHFA2k',
          format: OutputFormat.av1,
          optimizeType: OptimizeType.quality,
          quality: 95,
          parallelCount: 3,
        ),
      );

      final settings = await repository.loadConvert(defaults, maxParallel: 4);

      expect(settings.inputFolderPath, '/tmp/input');
      expect(settings.outputFolderPath, '/tmp/output');
      expect(settings.targetFilter, TargetFilter.oneDay);
      expect(settings.scale, 4);
      expect(settings.model, '4xHFA2k');
      expect(settings.format, OutputFormat.av1);
      expect(settings.optimizeType, OptimizeType.quality);
      expect(settings.quality, 95);
      expect(settings.parallelCount, 3);
    });

    test('存在しない設定値は初期値で補正され、ファイルが更新される', () async {
      writeSettings({
        'targetFilter': 'unknown_filter',
        'scale': 99,
        'model': '',
        'format': 'unknown_format',
        'optimizeType': 'anime',
        'quality': -1,
        'parallelCount': 0,
      });

      final settings = await repository.loadConvert(defaults, maxParallel: 4);

      expect(settings.targetFilter, TargetFilter.sevenDays);
      expect(settings.scale, 4); // 範囲外(99)は上限にクランプ
      expect(settings.model, 'realesr-animevideov3-x4');
      expect(settings.format, OutputFormat.jpegXl);
      expect(settings.optimizeType, OptimizeType.anime);
      expect(settings.quality, 1); // 範囲外(-1)は下限にクランプ
      expect(settings.parallelCount, 1); // 範囲外(0)は下限にクランプ

      final json = jsonDecode(settingsFile().readAsStringSync());
      expect(json['convert']['targetFilter'], 'sevenDays');
      expect(json['convert']['scale'], 4);
    });

    test('並列数はCPUコア数を超えないよう補正される', () async {
      writeSettings({
        'targetFilter': 'sevenDays',
        'scale': 2,
        'model': 'realesr-animevideov3-x4',
        'format': 'jpegXl',
        'optimizeType': 'anime',
        'quality': 80,
        'parallelCount': 99,
      });

      final settings = await repository.loadConvert(defaults, maxParallel: 4);

      expect(settings.parallelCount, 4);
    });

    test('設定画面の設定を保存・読み込みできる', () async {
      final defaults = SettingsScreenSettings.defaults();

      await repository.saveSettings(
        defaults.copyWith(
          showOsNotification: true,
          playSound: true,
          successSound: 'assets/sounds/success/decision49.mp3',
          errorSound: '/tmp/error.wav',
        ),
      );

      final settings = await repository.loadSettings(defaults);

      expect(settings.showOsNotification, isTrue);
      expect(settings.playSound, isTrue);
      expect(settings.successSound, 'assets/sounds/success/decision49.mp3');
      expect(settings.errorSound, '/tmp/error.wav');
    });

    test('convert と settings のキーが共存できる', () async {
      await repository.saveConvert(defaults.copyWith(scale: 3));
      await repository.saveSettings(
        SettingsScreenSettings.defaults().copyWith(playSound: true),
      );

      final json = jsonDecode(settingsFile().readAsStringSync());
      expect(json['convert']['scale'], 3);
      expect(json['settings']['playSound'], isTrue);

      final convert = await repository.loadConvert(defaults, maxParallel: 4);
      expect(convert.scale, 3);

      final settings = await repository.loadSettings(
        SettingsScreenSettings.defaults(),
      );
      expect(settings.playSound, isTrue);
    });
  });
}
