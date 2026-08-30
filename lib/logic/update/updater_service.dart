import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_info.dart';

const _tag = 'UpdaterService';

/// アップデートの結果。
sealed class UpdateResult {
  const UpdateResult();
}

/// アップデートなし。
class UpdateAlreadyLatest extends UpdateResult {
  const UpdateAlreadyLatest();
}

/// 新しいバージョンが利用可能。
class UpdateAvailable extends UpdateResult {
  const UpdateAvailable(this.info);
  final UpdateInfo info;
}

/// ダウンロード・検証完了。一時ディレクトリに展開済み。
class UpdateReady extends UpdateResult {
  const UpdateReady({
    required this.info,
    required this.appPath,
    required this.helperPath,
  });
  final UpdateInfo info;
  final String appPath;
  final String helperPath;
}

/// エラー。
class UpdateError extends UpdateResult {
  const UpdateError(this.message, [this.stackTrace]);
  final String message;
  final StackTrace? stackTrace;
}

/// 自前アップデート処理。
class UpdaterService {
  UpdaterService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// update-info.json を取得してバージョン比較を行う。
  Future<UpdateResult> checkForUpdate(String updateInfoUrl) async {
    dev.log('=== checkForUpdate START ===', name: _tag);
    dev.log('URL: $updateInfoUrl', name: _tag);

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    dev.log(
      'Current version: v$currentVersion (build $currentBuild)',
      name: _tag,
    );
    dev.log('Package: ${packageInfo.packageName}', name: _tag);

    try {
      dev.log('HTTP GET start (timeout: 15s)...', name: _tag);
      final stopwatch = Stopwatch()..start();
      final response = await _client
          .get(Uri.parse(updateInfoUrl))
          .timeout(const Duration(seconds: 15));
      stopwatch.stop();
      dev.log(
        'HTTP GET done: ${response.statusCode} '
        '(${stopwatch.elapsedMilliseconds}ms, ${response.body.length} bytes)',
        name: _tag,
      );

      if (response.statusCode != 200) {
        dev.log('ERROR: HTTP ${response.statusCode}', name: _tag);
        return UpdateError('HTTP ${response.statusCode}');
      }

      dev.log('Parsing update-info.json...', name: _tag);
      final info = UpdateInfo.fromString(response.body);
      dev.log(
        'Remote version: v${info.version} (build ${info.build})',
        name: _tag,
      );
      dev.log('Remote URL: ${info.url}', name: _tag);
      dev.log('Remote SHA-256: ${info.sha256}', name: _tag);

      final isNewer = info.isNewerThan(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
      );
      dev.log(
        'Version comparison: current=v$currentVersion+$currentBuild, '
        'remote=v${info.version}+${info.build} → ${isNewer ? "NEWER" : "LATEST"}',
        name: _tag,
      );

      if (!isNewer) {
        dev.log('=== checkForUpdate END: LATEST ===', name: _tag);
        return const UpdateAlreadyLatest();
      }

      dev.log('=== checkForUpdate END: AVAILABLE ===', name: _tag);
      return UpdateAvailable(info);
    } on TimeoutException {
      dev.log('ERROR: Timeout after 15s', name: _tag);
      return const UpdateError('タイムアウトしました');
    } on Object catch (e, st) {
      dev.log('ERROR: $e', name: _tag, error: e, stackTrace: st);
      return UpdateError(e.toString(), st);
    }
  }

  /// ZIP をダウンロードし、SHA-256 を検証して一時ディレクトリに展開する。
  Future<UpdateResult> downloadAndPrepare(UpdateInfo info) async {
    dev.log('=== downloadAndPrepare START ===', name: _tag);
    dev.log('Download URL: ${info.url}', name: _tag);
    dev.log('Expected SHA-256: ${info.sha256}', name: _tag);

    try {
      // Step 1: ダウンロード開始。
      dev.log('[Step 1/5] Starting download...', name: _tag);
      final request = http.Request('GET', Uri.parse(info.url));
      final response = await _client
          .send(request)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        dev.log(
          'ERROR: Download failed HTTP ${response.statusCode}',
          name: _tag,
        );
        return UpdateError('Download failed: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      dev.log(
        'HTTP ${response.statusCode}, '
        'Content-Length: ${contentLength != null ? "${(contentLength / 1024 / 1024).toStringAsFixed(1)}MB" : "unknown"}',
        name: _tag,
      );

      // Step 2: ストリーム受信 + SHA-256 計算。
      dev.log('[Step 2/5] Receiving data...', name: _tag);
      final bytes = <int>[];
      var totalBytes = 0;
      final completer = Completer<void>();
      final downloadStopwatch = Stopwatch()..start();

      response.stream.listen(
        (chunk) {
          bytes.addAll(chunk);
          totalBytes += chunk.length;
          if (contentLength != null && contentLength > 0) {
            final percent = (totalBytes / contentLength * 100).toStringAsFixed(
              0,
            );
            if (totalBytes % (1024 * 1024) < chunk.length ||
                totalBytes == contentLength) {
              dev.log(
                '  Progress: $percent% '
                '(${(totalBytes / 1024 / 1024).toStringAsFixed(1)}/'
                '${(contentLength / 1024 / 1024).toStringAsFixed(1)}MB)',
                name: _tag,
              );
            }
          }
        },
        onDone: () => completer.complete(),
        onError: (Object e) => completer.completeError(e),
      );
      await completer.future;
      downloadStopwatch.stop();

      dev.log(
        'Download complete: ${(totalBytes / 1024 / 1024).toStringAsFixed(1)}MB '
        'in ${downloadStopwatch.elapsedMilliseconds}ms '
        '(${(totalBytes / 1024 / 1024 / (downloadStopwatch.elapsedMilliseconds / 1000)).toStringAsFixed(1)}MB/s)',
        name: _tag,
      );

      // Step 3: SHA-256 検証。
      dev.log('[Step 3/5] Verifying SHA-256...', name: _tag);
      final verifyStopwatch = Stopwatch()..start();
      final digest = sha256.convert(bytes);
      final hex = digest.toString();
      verifyStopwatch.stop();
      dev.log(
        'Computed SHA-256: $hex (${verifyStopwatch.elapsedMilliseconds}ms)',
        name: _tag,
      );

      if (hex != info.sha256) {
        dev.log(
          'ERROR: SHA-256 MISMATCH!\n'
          '  Expected: ${info.sha256}\n'
          '  Got:      $hex',
          name: _tag,
        );
        return UpdateError(
          'SHA-256 mismatch: expected ${info.sha256}, got $hex',
        );
      }
      dev.log('SHA-256 verified OK', name: _tag);

      // Step 4: ZIP を展開。
      dev.log('[Step 4/5] Extracting...', name: _tag);
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory(
        '${tempDir.path}/tree-image-optimizer-update',
      );
      dev.log('Temp directory: ${updateDir.path}', name: _tag);

      if (await updateDir.exists()) {
        dev.log('Cleaning previous update directory...', name: _tag);
        await updateDir.delete(recursive: true);
      }
      await updateDir.create(recursive: true);
      dev.log('Created update directory', name: _tag);

      final zipFile = File('${updateDir.path}/update.zip');
      final writeStopwatch = Stopwatch()..start();
      await zipFile.writeAsBytes(bytes, flush: true);
      writeStopwatch.stop();
      dev.log(
        'ZIP saved: ${zipFile.path} '
        '(${(await zipFile.length()) / 1024 / 1024}MB, ${writeStopwatch.elapsedMilliseconds}ms)',
        name: _tag,
      );

      final unzipStopwatch = Stopwatch()..start();
      final result = await Process.run('unzip', [
        '-o',
        zipFile.path,
        '-d',
        updateDir.path,
      ]);
      unzipStopwatch.stop();

      if (result.exitCode != 0) {
        dev.log(
          'ERROR: unzip failed (exit ${result.exitCode})\n'
          '  stdout: ${result.stdout}\n'
          '  stderr: ${result.stderr}',
          name: _tag,
        );
        return UpdateError('unzip failed: ${result.stderr}');
      }
      dev.log(
        'Extracted to: ${updateDir.path} (${unzipStopwatch.elapsedMilliseconds}ms)',
        name: _tag,
      );

      // 展開後のディレクトリ構造をログ出力。
      await _logDirectoryContents(updateDir.path, 'Extracted contents');

      // Step 5: .app バンドルを検索。
      dev.log('[Step 5/5] Finding .app bundle...', name: _tag);
      final appPath = await _findAppBundle(updateDir.path);
      if (appPath == null) {
        dev.log('ERROR: .app bundle not found in archive', name: _tag);
        return UpdateError('.app bundle not found in archive');
      }
      dev.log('Found .app: $appPath', name: _tag);

      // .app の Info.plist を確認。
      await _logAppInfo(appPath);

      // helper を配置。
      final helperPath = '${updateDir.path}/updater_helper';
      await _writeHelperScript(helperPath);
      dev.log('Helper written: $helperPath', name: _tag);

      dev.log('=== downloadAndPrepare END: READY ===', name: _tag);
      return UpdateReady(info: info, appPath: appPath, helperPath: helperPath);
    } on TimeoutException {
      dev.log('ERROR: Download timed out', name: _tag);
      return const UpdateError('Download timed out');
    } on Object catch (e, st) {
      dev.log('ERROR: $e', name: _tag, error: e, stackTrace: st);
      return UpdateError(e.toString(), st);
    }
  }

  /// アップデートを適用する。UpdaterHelper を起動してアプリを終了する。
  Future<bool> applyUpdate(UpdateReady ready) async {
    dev.log('=== applyUpdate START ===', name: _tag);
    dev.log('New version: ${ready.info}', name: _tag);
    dev.log('New .app path: ${ready.appPath}', name: _tag);
    dev.log('Helper path: ${ready.helperPath}', name: _tag);

    try {
      // 実行中の .app パスを取得。
      final executablePath = Platform.resolvedExecutable;
      dev.log('Current executable: $executablePath', name: _tag);

      final appDir = _findAppContainer(executablePath);
      if (appDir == null) {
        dev.log(
          'ERROR: Cannot determine current .app path from: $executablePath',
          name: _tag,
        );
        return false;
      }
      dev.log('Current .app: $appDir', name: _tag);

      // helper の実行権限を確認。
      final helperFile = File(ready.helperPath);
      if (!await helperFile.exists()) {
        dev.log('ERROR: Helper not found: ${ready.helperPath}', name: _tag);
        return false;
      }

      // helper のログファイルを事前にクリーンアップ。
      // helper スクリプトは /tmp/tree-image-optimizer-updater-<appName>.log に書き出す。
      final tempDir = Directory.systemTemp;
      await for (final f in tempDir.list()) {
        if (f is File && f.path.contains('tree-image-optimizer-updater-')) {
          await f.delete();
        }
      }

      // helper を起動: helper <old_app_path> <new_app_path>
      dev.log(
        'Starting helper: ${ready.helperPath} "$appDir" "${ready.appPath}"',
        name: _tag,
      );
      final process = await Process.start(ready.helperPath, [
        appDir,
        ready.appPath,
      ]);
      dev.log('Helper started (pid=${process.pid})', name: _tag);

      // helper の stdout/stderr を監視。
      process.stdout
          .transform(utf8.decoder)
          .listen((line) => dev.log('[helper:out] $line', name: _tag));
      process.stderr
          .transform(utf8.decoder)
          .listen((line) => dev.log('[helper:err] $line', name: _tag));

      // 少し待ってから helper のログファイルを確認。
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // ログファイルを探す (アプリ名が分からない場合があるためワイルドカード)。
      final logFiles = <File>[];
      await for (final f in Directory.systemTemp.list()) {
        if (f is File && f.path.contains('tree-image-optimizer-updater-')) {
          logFiles.add(f);
        }
      }
      if (logFiles.isNotEmpty) {
        final logContent = await logFiles.first.readAsString();
        dev.log('Helper log:\n$logContent', name: _tag);
      }

      // アプリを終了。
      dev.log('Exiting app to allow replacement...', name: _tag);
      dev.log('=== applyUpdate END: EXITING ===', name: _tag);
      exit(0);
    } on Object catch (e, st) {
      dev.log(
        'ERROR: Failed to apply update: $e',
        name: _tag,
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// .app バンドルを見つける。
  Future<String?> _findAppBundle(String dir) async {
    dev.log('Searching for .app in: $dir', name: _tag);
    final result = await Process.run('find', [
      dir,
      '-name',
      '*.app',
      '-maxdepth',
      '2',
    ]);
    if (result.exitCode != 0) {
      dev.log('find failed: ${result.stderr}', name: _tag);
      return null;
    }
    final lines = (result.stdout as String).trim().split('\n');
    dev.log('find results: ${lines.length} match(es)', name: _tag);
    for (final line in lines) {
      if (line.isNotEmpty) dev.log('  Found: $line', name: _tag);
    }
    return lines.isNotEmpty ? lines.first : null;
  }

  /// 実行ファイルパスから .app コンテナディレクトリを特定する。
  String? _findAppContainer(String executablePath) {
    final marker = '.app/Contents/MacOS/';
    final idx = executablePath.indexOf(marker);
    if (idx < 0) {
      dev.log(
        'Cannot find .app container marker in: $executablePath',
        name: _tag,
      );
      return null;
    }
    final container = executablePath.substring(0, idx + '.app'.length);
    dev.log('App container: $container', name: _tag);
    return container;
  }

  /// ディレクトリの内容をログ出力する。
  Future<void> _logDirectoryContents(String dir, String label) async {
    try {
      final result = await Process.run('find', [dir, '-maxdepth', '3']);
      if (result.exitCode == 0) {
        final contents = (result.stdout as String).trim();
        dev.log('$label:\n$contents', name: _tag);
      }
    } on Object catch (e) {
      dev.log('Failed to list directory $dir: $e', name: _tag);
    }
  }

  /// .app の Info.plist 情報をログ出力する。
  Future<void> _logAppInfo(String appPath) async {
    try {
      final plistPath = '$appPath/Contents/Info.plist';
      final result = await Process.run('defaults', ['read', plistPath]);
      if (result.exitCode == 0) {
        dev.log('Info.plist:\n${result.stdout}', name: _tag);
      } else {
        dev.log('Failed to read Info.plist: ${result.stderr}', name: _tag);
      }
    } on Object catch (e) {
      dev.log('Failed to read app info: $e', name: _tag);
    }
  }

  /// updater_helper スクリプトを書き出す。
  Future<void> _writeHelperScript(String path) async {
    // helper スクリプトは以下の手順で .app を差し替える:
    // 1. 旧アプリの実行ファイル名を取得 (例: "Tree Image Optimizer")
    // 2. その名前で pgrep してプロセス終了を待つ (helper 自身を誤マッチしない)
    // 3. 旧 .app を削除し、新しい .app をコピー
    // 4. 新しい .app を起動
    final script = r'''#!/bin/bash

OLD_APP="$1"
NEW_APP="$2"

# アプリ名を取得してログファイル名に使用。
APP_NAME=$(defaults read "$OLD_APP/Contents/Info.plist" CFBundleName 2>/dev/null || echo "unknown")
LOG_FILE="/tmp/tree-image-optimizer-updater-${APP_NAME}.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "START"
log "OLD_APP: $1"
log "NEW_APP: $2"

OLD_APP="$1"
NEW_APP="$2"

if [ -z "$OLD_APP" ] || [ -z "$NEW_APP" ]; then
  log "ERROR: Missing arguments"
  exit 1
fi

if [ ! -d "$OLD_APP" ]; then
  log "ERROR: OLD_APP does not exist: $OLD_APP"
  exit 1
fi

if [ ! -d "$NEW_APP" ]; then
  log "ERROR: NEW_APP does not exist: $NEW_APP"
  exit 1
fi

# 旧アプリの実行ファイル名を取得 (例: "Tree Image Optimizer")。
# helper 自身のプロセス名とは異なるため、pgrep で誤マッチしない。
EXEC_NAME=$(defaults read "$OLD_APP/Contents/Info.plist" CFBundleExecutable 2>/dev/null || echo "")
log "Executable name: '$EXEC_NAME'"

if [ -n "$EXEC_NAME" ]; then
  log "Waiting for process '$EXEC_NAME' to exit (max 30s)..."
  for i in $(seq 1 30); do
    # pgrep -x: 完全一致マッチ。helper 自身は "bash" なのでマッチしない。
    if ! pgrep -x "$EXEC_NAME" > /dev/null 2>&1; then
      log "Process exited after ${i}s"
      sleep 1
      break
    fi
    log "Still running... (${i}/30)"
    sleep 1
  done
else
  log "No executable name found, waiting 3s..."
  sleep 3
fi

# 旧 .app を削除。
log "Removing old app: $OLD_APP"
rm -rf "$OLD_APP"
if [ -d "$OLD_APP" ]; then
  log "ERROR: Failed to remove old app"
  exit 1
fi
log "Old app removed"

# 新しい .app をコピー。
log "Copying new app: $NEW_APP -> $OLD_APP"
cp -R "$NEW_APP" "$OLD_APP"
if [ ! -d "$OLD_APP" ]; then
  log "ERROR: Failed to copy new app"
  exit 1
fi
log "New app installed"

# 起動。
log "Launching: $OLD_APP"
open "$OLD_APP"

log "DONE"
''';
    await File(path).writeAsString(script, mode: FileMode.write);
    await Process.run('chmod', ['+x', path]);
  }
}
