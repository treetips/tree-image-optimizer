import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/convert_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/compression_service.dart';
import '../data/services/log_service.dart';
import '../data/services/notification_service.dart';
import '../data/services/path_service.dart';
import '../data/services/process_service.dart';
import '../data/services/sound_service.dart';
import '../data/services/tool_installer.dart';
import '../data/services/upscale_service.dart';
import '../logic/usecases/compress_usecase.dart';
import '../logic/usecases/get_target_files_usecase.dart';
import '../logic/usecases/get_upscale_models_usecase.dart';
import '../logic/usecases/notify_completion_usecase.dart';
import '../logic/usecases/upscale_usecase.dart';
import '../logic/update/updater_service.dart';
import '../logic/viewmodels/about_view_model.dart';
import '../logic/viewmodels/convert_view_model.dart';
import '../logic/viewmodels/settings_view_model.dart';
import '../logic/viewmodels/tool_install_view_model.dart';

/// アップデートサービス。
final updaterServiceProvider = Provider<UpdaterService>((ref) {
  return UpdaterService();
});

final pathServiceProvider = Provider<PathService>((ref) {
  return PathService();
});

final toolInstallerProvider = Provider<ToolInstaller>((ref) {
  return ToolInstaller(logService: ref.watch(logServiceProvider));
});

final toolInstallViewModelProvider =
    StateNotifierProvider<ToolInstallViewModel, ToolInstallState>((ref) {
      return ToolInstallViewModel(installer: ref.watch(toolInstallerProvider));
    });

final logServiceProvider = Provider<LogService>((ref) {
  return LogService(pathService: ref.watch(pathServiceProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(logService: ref.watch(logServiceProvider));
});

final soundServiceProvider = Provider<SoundService>((ref) {
  return SoundService(
    logService: ref.watch(logServiceProvider),
    pathService: ref.watch(pathServiceProvider),
  );
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(logService: ref.watch(logServiceProvider));
});

final processServiceProvider = Provider<ProcessService>((ref) {
  return ProcessService(logService: ref.watch(logServiceProvider));
});

final upscaleServiceProvider = Provider<UpscaleService>((ref) {
  return UpscaleService(
    pathService: ref.watch(pathServiceProvider),
    processService: ref.watch(processServiceProvider),
    logService: ref.watch(logServiceProvider),
  );
});

final compressionServiceProvider = Provider<CompressionService>((ref) {
  return CompressionService(
    pathService: ref.watch(pathServiceProvider),
    processService: ref.watch(processServiceProvider),
    logService: ref.watch(logServiceProvider),
  );
});

final convertRepositoryProvider = Provider<ConvertRepository>((ref) {
  return ConvertRepository(
    pathService: ref.watch(pathServiceProvider),
    upscaleService: ref.watch(upscaleServiceProvider),
    compressionService: ref.watch(compressionServiceProvider),
  );
});

final getTargetFilesUseCaseProvider = Provider<GetTargetFilesUseCase>((ref) {
  return GetTargetFilesUseCase(ref.watch(convertRepositoryProvider));
});

final getUpscaleModelsUseCaseProvider = Provider<GetUpscaleModelsUseCase>((
  ref,
) {
  return GetUpscaleModelsUseCase(ref.watch(convertRepositoryProvider));
});

final upscaleUseCaseProvider = Provider<UpscaleUseCase>((ref) {
  return UpscaleUseCase(ref.watch(convertRepositoryProvider));
});

final compressUseCaseProvider = Provider<CompressUseCase>((ref) {
  return CompressUseCase(ref.watch(convertRepositoryProvider));
});

final notifyCompletionUseCaseProvider = Provider<NotifyCompletionUseCase>((
  ref,
) {
  return NotifyCompletionUseCase(
    settingsRepository: ref.watch(settingsRepositoryProvider),
    soundService: ref.watch(soundServiceProvider),
    notificationService: ref.watch(notificationServiceProvider),
  );
});

final convertViewModelProvider =
    StateNotifierProvider<ConvertViewModel, ConvertState>((ref) {
      return ConvertViewModel(
        getTargetFilesUseCase: ref.watch(getTargetFilesUseCaseProvider),
        getUpscaleModelsUseCase: ref.watch(getUpscaleModelsUseCaseProvider),
        upscaleUseCase: ref.watch(upscaleUseCaseProvider),
        compressUseCase: ref.watch(compressUseCaseProvider),
        notifyCompletionUseCase: ref.watch(notifyCompletionUseCaseProvider),
        logService: ref.watch(logServiceProvider),
        settingsRepository: ref.watch(settingsRepositoryProvider),
      );
    });

final settingsViewModelProvider =
    StateNotifierProvider<SettingsViewModel, SettingsState>((ref) {
      return SettingsViewModel(
        settingsRepository: ref.watch(settingsRepositoryProvider),
        soundService: ref.watch(soundServiceProvider),
      );
    });

final aboutViewModelProvider =
    StateNotifierProvider<AboutViewModel, AboutState>((ref) {
      return AboutViewModel();
    });
