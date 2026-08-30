import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/convert_config.dart';
import '../../core/models/convert_settings.dart';
import '../../core/models/file_progress.dart';
import '../../core/models/optimize_type.dart';
import '../../core/models/output_format.dart';
import '../../core/models/process_status.dart';
import '../../core/models/target_filter.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/log_service.dart';
import '../usecases/compress_usecase.dart';
import '../usecases/get_target_files_usecase.dart';
import '../usecases/get_upscale_models_usecase.dart';
import '../usecases/notify_completion_usecase.dart';
import '../usecases/upscale_usecase.dart';

/// 変換画面の状態。
class ConvertState {
  const ConvertState({
    this.inputFolderPath,
    this.outputFolderPath,
    this.inputFolderError = false,
    this.outputFolderError = false,
    this.targetFilter = TargetFilter.sevenDays,
    this.scale = 2,
    this.models = const [],
    this.selectedModel = 'realesr-animevideov3-x4',
    this.format = OutputFormat.jpegXl,
    this.optimizeType = OptimizeType.anime,
    this.quality = 80,
    this.parallelCount = 1,
    this.isRunning = false,
    this.fileProgress = const [],
    this.progressPercent = 0,
    this.successCount = 0,
    this.failureCount = 0,
    this.elapsedMinutes = 0,
  });

  final String? inputFolderPath;
  final String? outputFolderPath;
  final bool inputFolderError;
  final bool outputFolderError;
  final TargetFilter targetFilter;
  final int scale;
  final List<String> models;
  final String selectedModel;
  final OutputFormat format;
  final OptimizeType optimizeType;
  final int quality;
  final int parallelCount;
  final bool isRunning;
  final List<FileProgress> fileProgress;
  final double progressPercent;
  final int successCount;
  final int failureCount;
  final double elapsedMinutes;

  /// 変換実行が可能かどうか。
  bool get canRun =>
      !isRunning &&
      inputFolderPath != null &&
      outputFolderPath != null &&
      !inputFolderError &&
      !outputFolderError;

  /// 対象ファイル数。
  int get totalCount => fileProgress.length;

  ConvertState copyWith({
    String? inputFolderPath,
    String? outputFolderPath,
    bool? inputFolderError,
    bool? outputFolderError,
    TargetFilter? targetFilter,
    int? scale,
    List<String>? models,
    String? selectedModel,
    OutputFormat? format,
    OptimizeType? optimizeType,
    int? quality,
    int? parallelCount,
    bool? isRunning,
    List<FileProgress>? fileProgress,
    double? progressPercent,
    int? successCount,
    int? failureCount,
    double? elapsedMinutes,
  }) {
    return ConvertState(
      inputFolderPath: inputFolderPath ?? this.inputFolderPath,
      outputFolderPath: outputFolderPath ?? this.outputFolderPath,
      inputFolderError: inputFolderError ?? this.inputFolderError,
      outputFolderError: outputFolderError ?? this.outputFolderError,
      targetFilter: targetFilter ?? this.targetFilter,
      scale: scale ?? this.scale,
      models: models ?? this.models,
      selectedModel: selectedModel ?? this.selectedModel,
      format: format ?? this.format,
      optimizeType: optimizeType ?? this.optimizeType,
      quality: quality ?? this.quality,
      parallelCount: parallelCount ?? this.parallelCount,
      isRunning: isRunning ?? this.isRunning,
      fileProgress: fileProgress ?? this.fileProgress,
      progressPercent: progressPercent ?? this.progressPercent,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      elapsedMinutes: elapsedMinutes ?? this.elapsedMinutes,
    );
  }
}

/// 変換画面のビューモデル。
class ConvertViewModel extends StateNotifier<ConvertState> {
  ConvertViewModel({
    required this.getTargetFilesUseCase,
    required this.getUpscaleModelsUseCase,
    required this.upscaleUseCase,
    required this.compressUseCase,
    LogService? logService,
    this.settingsRepository,
    this.notifyCompletionUseCase,
    int? processorCount,
  }) : _log = logService,
       _processorCount = processorCount ?? max(1, Platform.numberOfProcessors),
       super(const ConvertState()) {
    final maxParallel = processorCount ?? Platform.numberOfProcessors;
    state = state.copyWith(
      parallelCount: max(1, (maxParallel / 2).floor() - 1),
    );
    _loadModels();
    _loadSettings();
  }

  final GetTargetFilesUseCase getTargetFilesUseCase;
  final GetUpscaleModelsUseCase getUpscaleModelsUseCase;
  final UpscaleUseCase upscaleUseCase;
  final CompressUseCase compressUseCase;
  final LogService? _log;
  final SettingsRepository? settingsRepository;
  final NotifyCompletionUseCase? notifyCompletionUseCase;
  final int _processorCount;

  /// 直近の設定保存のFuture。テスト等で保存完了を待つために使う。
  Future<void> _pendingSave = Future.value();

  /// 直近の設定保存が完了するまで待つ。
  Future<void> waitForSave() => _pendingSave;

  /// CPUコア数の最大値。
  int get maxParallel => _processorCount;

  Future<void> _loadModels() async {
    final models = await getUpscaleModelsUseCase.execute();
    if (!mounted) return;
    final current = state.selectedModel;
    if (!models.contains(current)) {
      state = state.copyWith(
        models: models,
        selectedModel: models.isNotEmpty ? models.first : current,
      );
    } else {
      state = state.copyWith(models: models);
    }
  }

  Future<void> _loadSettings() async {
    final repository = settingsRepository;
    if (repository == null) return;
    final defaults = ConvertSettings.defaults(maxParallel: _processorCount);
    final settings = await repository.loadConvert(
      defaults,
      maxParallel: _processorCount,
    );
    if (!mounted) return;
    state = state.copyWith(
      inputFolderPath: settings.inputFolderPath,
      outputFolderPath: settings.outputFolderPath,
      targetFilter: settings.targetFilter,
      scale: settings.scale,
      selectedModel: settings.model,
      format: settings.format,
      optimizeType: settings.optimizeType,
      quality: settings.quality,
      parallelCount: settings.parallelCount,
    );
  }

  void _saveSettings() {
    final repository = settingsRepository;
    if (repository == null) return;
    final s = state;
    final save = repository.saveConvert(
      ConvertSettings(
        inputFolderPath: s.inputFolderPath,
        outputFolderPath: s.outputFolderPath,
        targetFilter: s.targetFilter,
        scale: s.scale,
        model: s.selectedModel,
        format: s.format,
        optimizeType: s.optimizeType,
        quality: s.quality,
        parallelCount: s.parallelCount,
      ),
    );
    // 保存を直列化し、waitForSave() で全保存の完了を待てるようにする。
    _pendingSave = _pendingSave.then((_) => save);
  }

  void setInputFolderPath(String path) {
    final trimmed = path.trim();
    final exists =
        trimmed.isEmpty ||
        FileSystemEntity.typeSync(trimmed, followLinks: true) !=
            FileSystemEntityType.notFound;
    state = state.copyWith(
      inputFolderPath: path.isEmpty ? null : path,
      inputFolderError: !exists,
    );
    _saveSettings();
  }

  void setOutputFolderPath(String path) {
    final trimmed = path.trim();
    final exists =
        trimmed.isEmpty ||
        FileSystemEntity.typeSync(trimmed, followLinks: true) !=
            FileSystemEntityType.notFound;
    state = state.copyWith(
      outputFolderPath: path.isEmpty ? null : path,
      outputFolderError: !exists,
    );
    _saveSettings();
  }

  void setTargetFilter(TargetFilter filter) {
    state = state.copyWith(targetFilter: filter);
    _saveSettings();
  }

  void setScale(int scale) {
    state = state.copyWith(scale: scale);
    _saveSettings();
  }

  void setSelectedModel(String model) {
    state = state.copyWith(selectedModel: model);
    _saveSettings();
  }

  void setFormat(OutputFormat format) {
    state = state.copyWith(format: format);
    _saveSettings();
  }

  void setOptimizeType(OptimizeType optimizeType) {
    state = state.copyWith(optimizeType: optimizeType);
    _saveSettings();
  }

  void setQuality(int quality) {
    state = state.copyWith(quality: quality);
    _saveSettings();
  }

  void setParallelCount(int parallelCount) {
    state = state.copyWith(parallelCount: parallelCount);
    _saveSettings();
  }

  /// 変換処理を実行する。
  Future<void> runConversion() async {
    final input = state.inputFolderPath;
    final output = state.outputFolderPath;
    if (input == null || output == null) return;

    state = state.copyWith(
      isRunning: true,
      fileProgress: const [],
      progressPercent: 0,
      successCount: 0,
      failureCount: 0,
      elapsedMinutes: 0,
    );

    final stopwatch = Stopwatch()..start();
    var success = 0;
    var failure = 0;

    final config = ConvertConfig(
      inputFolderPath: input,
      outputFolderPath: output,
      targetFilter: state.targetFilter,
      scale: state.scale,
      model: state.selectedModel,
      format: state.format,
      optimizeType: state.optimizeType,
      quality: state.quality,
      parallelCount: state.parallelCount,
    );

    try {
      _log?.logger.info(
        '変換開始: input=$input output=$output filter=${config.targetFilter.name} '
        'scale=${config.scale} model=${config.model} format=${config.format.name} '
        'type=${config.optimizeType.name} quality=${config.quality} '
        'parallel=${config.parallelCount}',
      );
      final filesResult = await getTargetFilesUseCase.execute(
        input,
        config.targetFilter,
      );
      if (filesResult.isFail) {
        throw filesResult.asFail ?? '対象ファイルの取得に失敗しました。';
      }
      final files = filesResult.value;
      _log?.logger.info('対象ファイル ${files.length}件');

      final progressList = files
          .map((f) => FileProgress(fileName: _fileName(f)))
          .toList();
      state = state.copyWith(fileProgress: progressList);

      await _processParallel(files.length, config, (index) {
        return _processFile(index, files[index], config).then((ok) {
          if (ok) {
            success++;
          } else {
            failure++;
          }
          final percent = (success + failure) / files.length * 100;
          state = state.copyWith(
            progressPercent: percent,
            successCount: success,
            failureCount: failure,
          );
        });
      });
    } finally {
      stopwatch.stop();
      final allSuccess = success > 0 && failure == 0;
      if (success + failure > 0) {
        _log?.logger.info('変換完了: 成功=$success 失敗=$failure');
        await notifyCompletionUseCase?.execute(allSuccess: allSuccess);
      }
      state = state.copyWith(
        isRunning: false,
        elapsedMinutes: stopwatch.elapsedMilliseconds / 60000,
      );
    }
  }

  Future<void> _processParallel(
    int fileCount,
    ConvertConfig config,
    Future<void> Function(int index) task,
  ) async {
    final queue = <int>[];
    final active = <Future<void>>[];

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final index = queue.removeAt(0);
        await task(index);
      }
    }

    for (var i = 0; i < fileCount; i++) {
      queue.add(i);
    }
    final workers = min(config.parallelCount, fileCount);
    for (var i = 0; i < workers; i++) {
      active.add(worker());
    }
    await Future.wait(active);
  }

  Future<bool> _processFile(
    int index,
    String filePath,
    ConvertConfig config,
  ) async {
    var ok = true;
    try {
      final file = File(filePath);
      _updateStatus(index, upscale: ProcessStatus.running);
      final tempDir = await Directory.systemTemp.createTemp('tree_image');
      final baseName = file.path.split(Platform.pathSeparator).last;
      final nameWithoutExt = baseName.split('.').first;
      final upscaledPath = '${tempDir.path}/$nameWithoutExt.png';

      final upscaleResult = await upscaleUseCase.execute(
        input: file.path,
        output: upscaledPath,
        scale: config.scale,
        model: config.model,
      );
      if (upscaleResult.isFail) {
        _updateStatus(index, upscale: ProcessStatus.failure);
        throw upscaleResult.asFail ?? 'アップスケールに失敗しました。';
      }
      _updateStatus(index, upscale: ProcessStatus.success);

      _updateStatus(index, compress: ProcessStatus.running);
      final outputPath = '${tempDir.path}/$baseName${config.format.extension}';
      final compressResult = await compressUseCase.execute(
        input: upscaledPath,
        output: outputPath,
        format: config.format,
        optimizeType: config.optimizeType,
        quality: config.quality,
        threads: config.parallelCount,
      );
      if (compressResult.isFail) {
        _updateStatus(index, compress: ProcessStatus.failure);
        throw compressResult.asFail ?? '圧縮に失敗しました。';
      }
      _updateStatus(index, compress: ProcessStatus.success);

      _updateStatus(index, output: ProcessStatus.running);
      final outputDir = Directory(config.outputFolderPath!);
      await outputDir.create(recursive: true);
      final destination =
          '${config.outputFolderPath!}/$nameWithoutExt${config.format.extension}';
      await File(outputPath).copy(destination);
      _updateStatus(index, output: ProcessStatus.success);
    } catch (error, stackTrace) {
      _log?.logger.severe('ファイル処理失敗: $filePath', error, stackTrace);
      ok = false;
    }
    return ok;
  }

  void _updateStatus(
    int index, {
    ProcessStatus? upscale,
    ProcessStatus? compress,
    ProcessStatus? output,
  }) {
    if (index < 0 || index >= state.fileProgress.length) return;
    final current = state.fileProgress[index];
    final updated = current.copyWith(
      upscaleStatus: upscale,
      compressStatus: compress,
      outputStatus: output,
    );
    state = state.copyWith(
      fileProgress: _replaceAt(state.fileProgress, index, updated),
    );
  }

  List<FileProgress> _replaceAt(
    List<FileProgress> list,
    int index,
    FileProgress value,
  ) {
    final copy = [...list];
    copy[index] = value;
    return copy;
  }

  String _fileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }
}
