import '../../core/models/result.dart';
import 'log_service.dart';
import 'path_service.dart';
import 'process_service.dart';

/// アップスケール処理を実行するサービス。
/// `upscayl-bin` コマンドを利用する。
class UpscaleService {
  UpscaleService({
    required this.pathService,
    required this.processService,
    LogService? logService,
  }) : _log = logService;

  final PathService pathService;
  final ProcessService processService;
  final LogService? _log;

  /// [input] を [scale] 倍、[model] でアップスケールして [output] に出力する。
  Future<Result<void>> upscale({
    required String input,
    required String output,
    required int scale,
    required String model,
  }) async {
    try {
      final binPath = await pathService.upscalBinPath();
      final modelsDir = await pathService.upscalModelsDirectory();
      final binDir = await pathService.upscalBinDirectory();
      _log?.logger.info(
        'アップスケール: input=$input output=$output scale=$scale model=$model '
        'bin=$binPath models=$modelsDir',
      );

      await processService.run(binPath, [
        '-i',
        input,
        '-o',
        output,
        '-s',
        '$scale',
        '-m',
        modelsDir.path,
        '-n',
        model,
      ], workingDirectory: binDir.path);
      return Result.ok(null);
    } on Object catch (error, stackTrace) {
      _log?.logger.severe('アップスケール失敗: $error', error, stackTrace);
      return Result.fail(error);
    }
  }
}
