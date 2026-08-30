import '../../data/repositories/convert_repository.dart';

/// 利用可能なアップスケールモデル一覧を取得するユースケース。
class GetUpscaleModelsUseCase {
  GetUpscaleModelsUseCase(this.repository);

  final ConvertRepository repository;

  Future<List<String>> execute() {
    return repository.getUpscaleModels();
  }
}
