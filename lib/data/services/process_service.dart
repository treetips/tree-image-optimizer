import 'dart:io';

import 'log_service.dart';

/// 外部コマンドを実行するサービス。
/// 実行したコマンドと失敗理由を [LogService] に出力する。
class ProcessService {
  ProcessService({LogService? logService}) : _log = logService;

  final LogService? _log;

  /// [executable] を [arguments] 付きで実行する。
  /// 終了コードが 0 以外の場合は [ProcessException] を投げる。
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final command = '$executable ${arguments.join(' ')}';
    _log?.logger.fine('コマンド実行: $command (dir: $workingDirectory)');

    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );

    if (result.exitCode != 0) {
      _log?.logger.severe(
        'コマンド失敗 (exit=${result.exitCode}): $command',
        ProcessException(
          executable,
          arguments,
          '${result.stdout}\n${result.stderr}',
          result.exitCode,
        ),
        StackTrace.current,
      );
      throw ProcessException(
        executable,
        arguments,
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
    return result;
  }
}
