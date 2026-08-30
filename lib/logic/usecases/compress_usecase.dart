import '../../core/models/optimize_type.dart';
import '../../core/models/output_format.dart';
import '../../core/models/result.dart';
import '../../data/repositories/convert_repository.dart';

/// 圧縮処理を実行するユースケース。
class CompressUseCase {
  CompressUseCase(this.repository);

  final ConvertRepository repository;

  Future<Result<void>> execute({
    required String input,
    required String output,
    required OutputFormat format,
    required OptimizeType optimizeType,
    required int quality,
    required int threads,
  }) {
    return repository.compress(
      input: input,
      output: output,
      format: format,
      optimizeType: optimizeType,
      quality: quality,
      threads: threads,
    );
  }
}
