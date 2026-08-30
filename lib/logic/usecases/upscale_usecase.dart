import '../../core/models/result.dart';
import '../../data/repositories/convert_repository.dart';

/// アップスケール処理を実行するユースケース。
class UpscaleUseCase {
  UpscaleUseCase(this.repository);

  final ConvertRepository repository;

  Future<Result<void>> execute({
    required String input,
    required String output,
    required int scale,
    required String model,
  }) {
    return repository.upscale(
      input: input,
      output: output,
      scale: scale,
      model: model,
    );
  }
}
