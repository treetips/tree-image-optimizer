import 'dart:io';

import 'package:logging/logging.dart';

import 'path_service.dart';

/// ログ出力を提供するサービス。
/// `~/Library/Application Support/tree-image-optimizer/logs/app.${yyyyMMdd}.log`
/// に日付ごとのファイルで出力し、最大30日分でローテートする。
class LogService {
  LogService({PathService? pathService})
    : _pathService = pathService ?? PathService();

  final PathService _pathService;
  final Logger _logger = Logger('app');
  Future<void> _writeQueue = Future.value();

  /// アプリケーションロガー。
  Logger get logger => _logger;

  /// ログ出力を初期化する。アプリ起動時に一度呼び出すこと。
  Future<void> init() async {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      _writeQueue = _writeQueue.then((_) => _write(record));
    });
    await _rotate();
    _logger.info('--- ログ開始 ---');
  }

  Future<void> _write(LogRecord record) async {
    try {
      final logsDir = await _pathService.logsDirectory();
      await logsDir.create(recursive: true);
      final file = File('${logsDir.path}/app.${_dateString(record.time)}.log');
      final buffer = StringBuffer();
      buffer.writeln(
        '[${_timestamp(record.time)}] [${record.level.name}] ${record.message}',
      );
      if (record.error != null) {
        buffer.writeln('  error: $record.error');
        if (record.stackTrace != null) {
          buffer.writeln(record.stackTrace);
        }
      }
      await file.writeAsString(buffer.toString(), mode: FileMode.append);
    } catch (_) {
      // ログ失敗時は握りつぶす。
    }
  }

  /// 30日より古いログファイルを削除する。
  Future<void> _rotate() async {
    try {
      final logsDir = await _pathService.logsDirectory();
      if (!await logsDir.exists()) return;
      final now = DateTime.now();
      await for (final entity in logsDir.list()) {
        if (entity is! File) continue;
        final m = RegExp(
          r'^app\.(\d{8})\.log$',
        ).firstMatch(entity.path.split(Platform.pathSeparator).last);
        if (m == null) continue;
        final fileDate = _parseDate(m[1]!);
        if (fileDate != null && now.difference(fileDate).inDays > 30) {
          await entity.delete();
        }
      }
    } catch (_) {
      // ローテート失敗時は握りつぶす。
    }
  }

  String _dateString(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}';

  DateTime? _parseDate(String yyyymmdd) {
    if (yyyymmdd.length != 8) return null;
    final year = int.tryParse(yyyymmdd.substring(0, 4));
    final month = int.tryParse(yyyymmdd.substring(4, 6));
    final day = int.tryParse(yyyymmdd.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  String _timestamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}
