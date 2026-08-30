import '../../core/models/result.dart';
import '../../core/models/target_filter.dart';
import '../../data/repositories/convert_repository.dart';

/// 対象ファイル一覧を取得するユースケース。
class GetTargetFilesUseCase {
  GetTargetFilesUseCase(this.repository);

  final ConvertRepository repository;

  Future<Result<List<String>>> execute(String folderPath, TargetFilter filter) {
    return repository.getTargetFiles(folderPath, filter);
  }
}
