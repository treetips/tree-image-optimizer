import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tree_image_optimizer/data/services/path_service.dart';

void main() {
  group('PathService', () {
    late Directory baseDir;
    late PathService pathService;

    setUp(() {
      baseDir = Directory.systemTemp.createTempSync('path_service_test');
      pathService = PathService(baseDirectory: baseDir);
    });

    tearDown(() {
      baseDir.deleteSync(recursive: true);
    });

    test('基準ディレクトリは注入された基準ディレクトリ', () async {
      final dir = await pathService.projectDirectory();
      expect(dir.path, baseDir.path);
    });

    test('ツールディレクトリは基準ディレクトリ直下の tools', () async {
      final tools = await pathService.toolsDirectory();
      expect(tools.path, '${baseDir.path}/tools');

      final upscalBin = await pathService.upscalBinDirectory();
      expect(upscalBin.path, '${tools.path}/upscal/bin');

      final models = await pathService.upscalModelsDirectory();
      expect(models.path, '${tools.path}/upscal/models');
    });

    test('ログディレクトリは基準ディレクトリ直下の logs', () async {
      final logs = await pathService.logsDirectory();
      expect(logs.path, '${baseDir.path}/logs');
    });
  });
}
