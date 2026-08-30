import 'dart:developer' as dev;

import 'package:material_ui/material_ui.dart';

import 'updater_service.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

const _tag = 'UpdateActions';

/// 結果ダイアログを表示する。
Future<void> _showResultDialog(
  BuildContext context,
  UpdateResult result,
) async {
  if (!context.mounted) return;

  final l10n = AppLocalizations.of(context)!;

  String title;
  String body;

  switch (result) {
    case UpdateAlreadyLatest():
      title = l10n.latest;
      body = l10n.latestMsg;
    case UpdateAvailable(:final info):
      title = l10n.updateAvailable;
      body = l10n.updateAvailableMsg(info.version);
    case UpdateReady(:final info):
      title = l10n.downloadComplete;
      body = l10n.downloadCompleteMsg(info.version);
    case UpdateError(:final message):
      title = l10n.updateCheckFailed;
      body = message;
  }

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.ok),
        ),
      ],
    ),
  );
}

/// 手動更新チェック（macOSメニュー用）。
///
/// チェック → 確認 → ダウンロード+インストール の1ステップフロー。
Future<void> runManualUpdateCheck({
  required BuildContext context,
  required UpdaterService updaterService,
  required String updateInfoUrl,
}) async {
  dev.log('=== runManualUpdateCheck START ===', name: _tag);
  dev.log('updateInfoUrl: $updateInfoUrl', name: _tag);

  dev.log('[1/2] Checking for update...', name: _tag);
  final result = await updaterService.checkForUpdate(updateInfoUrl);
  dev.log('[1/2] Result: ${result.runtimeType}', name: _tag);

  if (!context.mounted) {
    dev.log('ERROR: context unmounted after check', name: _tag);
    return;
  }

  final l10n = AppLocalizations.of(context)!;

  if (result case UpdateAvailable(:final info)) {
    dev.log('Update available: v${info.version}', name: _tag);

    // インストール確認。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmInstall),
        content: Text(l10n.confirmInstallMsg(info.version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.install),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );

    dev.log('User confirmed: $confirmed', name: _tag);

    if (confirmed != true || !context.mounted) {
      dev.log('Cancelled or unmounted', name: _tag);
      return;
    }

    // ダウンロード + インストール。
    dev.log('[2/2] Downloading and installing...', name: _tag);
    final downloadResult = await updaterService.downloadAndPrepare(info);
    dev.log('[2/2] Result: ${downloadResult.runtimeType}', name: _tag);

    if (!context.mounted) {
      dev.log('ERROR: context unmounted after download', name: _tag);
      return;
    }

    if (downloadResult case UpdateReady()) {
      dev.log(
        'Ready to install: v${downloadResult.info.version} '
        '(appPath: ${downloadResult.appPath})',
        name: _tag,
      );
      await updaterService.applyUpdate(downloadResult);
    } else {
      dev.log('Download failed: $downloadResult', name: _tag);
      await _showResultDialog(context, downloadResult);
    }
  } else {
    dev.log('No update available: $result', name: _tag);
    await _showResultDialog(context, result);
  }

  dev.log('=== runManualUpdateCheck END ===', name: _tag);
}

/// 起動時・バックグラウンドの自動更新チェック。
///
/// 結果は UI に反映せず、ログのみ記録する。
Future<void> runBackgroundUpdateCheck({
  required UpdaterService updaterService,
  required String updateInfoUrl,
}) async {
  dev.log('=== runBackgroundUpdateCheck START ===', name: _tag);
  dev.log('updateInfoUrl: $updateInfoUrl', name: _tag);

  final result = await updaterService.checkForUpdate(updateInfoUrl);

  switch (result) {
    case UpdateAvailable(:final info):
      dev.log('Background update available: v${info.version}', name: _tag);
    case UpdateAlreadyLatest():
      dev.log('Background: already latest', name: _tag);
    case UpdateError(:final message):
      dev.log('Background check failed: $message', name: _tag);
    case UpdateReady():
      break;
  }

  dev.log('=== runBackgroundUpdateCheck END ===', name: _tag);
}
