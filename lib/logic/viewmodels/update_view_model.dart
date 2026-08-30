import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../update/updater_service.dart';
import '../update/update_info.dart';

const _tag = 'UpdateViewModel';

/// アップデート画面の状態。
class UpdateState {
  const UpdateState({this.status = const UpdateIdle()});

  final UpdateStatus status;

  UpdateState copyWith({UpdateStatus? status}) {
    return UpdateState(status: status ?? this.status);
  }
}

/// アップデートの状態。
sealed class UpdateStatus {
  const UpdateStatus();
}

/// アイドル。
class UpdateIdle extends UpdateStatus {
  const UpdateIdle();
}

/// チェック中。
class UpdateChecking extends UpdateStatus {
  const UpdateChecking();
}

/// 新しいバージョンが見つかった。
class UpdateFound extends UpdateStatus {
  const UpdateFound(this.info);
  final UpdateInfo info;
}

/// ダウンロード中。
class UpdateDownloading extends UpdateStatus {
  const UpdateDownloading(this.progress);
  final double progress;
}

/// インストール準備完了。
class UpdateReadyToInstall extends UpdateStatus {
  const UpdateReadyToInstall({
    required this.info,
    required this.appPath,
    required this.helperPath,
  });
  final UpdateInfo info;
  final String appPath;
  final String helperPath;
}

/// 最新。
class UpdateUpToDate extends UpdateStatus {
  const UpdateUpToDate();
}

/// エラー。
class UpdateFailed extends UpdateStatus {
  const UpdateFailed(this.message);
  final String message;
}

/// アップデート管理ビューモデル。
class UpdateViewModel extends StateNotifier<UpdateState> {
  UpdateViewModel({required this.updaterService}) : super(const UpdateState());

  final UpdaterService updaterService;

  /// アップデートを確認する。
  Future<void> checkForUpdate() async {
    dev.log('=== checkForUpdate START ===', name: _tag);
    dev.log('URL: ${AppConstants.updateInfoUrl}', name: _tag);
    state = state.copyWith(status: const UpdateChecking());

    final result = await updaterService.checkForUpdate(
      AppConstants.updateInfoUrl,
    );

    dev.log('Result: ${result.runtimeType}', name: _tag);

    switch (result) {
      case UpdateAvailable(:final info):
        dev.log('Found: v${info.version} (build ${info.build})', name: _tag);
        state = state.copyWith(status: UpdateFound(info));
      case UpdateAlreadyLatest():
        dev.log('Already latest', name: _tag);
        state = state.copyWith(status: const UpdateUpToDate());
      case UpdateError(:final message):
        dev.log('Error: $message', name: _tag);
        state = state.copyWith(status: UpdateFailed(message));
      case UpdateReady():
        break;
    }

    dev.log('=== checkForUpdate END ===', name: _tag);
  }

  /// ダウンロードを開始する。
  Future<void> download(UpdateInfo info) async {
    dev.log('=== download START ===', name: _tag);
    dev.log('Version: v${info.version}', name: _tag);
    dev.log('URL: ${info.url}', name: _tag);
    state = state.copyWith(status: const UpdateDownloading(0));

    final result = await updaterService.downloadAndPrepare(info);

    dev.log('Result: ${result.runtimeType}', name: _tag);

    switch (result) {
      case UpdateReady(:final info, :final appPath, :final helperPath):
        dev.log(
          'Ready: v${info.version}\n'
          '  appPath: $appPath\n'
          '  helperPath: $helperPath',
          name: _tag,
        );
        state = state.copyWith(
          status: UpdateReadyToInstall(
            info: info,
            appPath: appPath,
            helperPath: helperPath,
          ),
        );
      case UpdateError(:final message):
        dev.log('Error: $message', name: _tag);
        state = state.copyWith(status: UpdateFailed(message));
      default:
        dev.log('Unexpected result: $result', name: _tag);
        state = state.copyWith(status: const UpdateFailed('予期しない結果'));
    }

    dev.log('=== download END ===', name: _tag);
  }

  /// アップデートを適用する（再起動）。
  Future<bool> applyUpdate(UpdateReadyToInstall ready) async {
    dev.log('=== applyUpdate START ===', name: _tag);
    dev.log('Version: ${ready.info}', name: _tag);
    dev.log('App path: ${ready.appPath}', name: _tag);
    dev.log('Helper path: ${ready.helperPath}', name: _tag);

    final success = await updaterService.applyUpdate(
      UpdateReady(
        info: ready.info,
        appPath: ready.appPath,
        helperPath: ready.helperPath,
      ),
    );

    dev.log('Result: $success', name: _tag);
    dev.log('=== applyUpdate END ===', name: _tag);
    return success;
  }
}
