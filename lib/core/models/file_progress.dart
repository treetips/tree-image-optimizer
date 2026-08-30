import 'process_status.dart';

/// 1ファイル分の進捗を表す。
class FileProgress {
  const FileProgress({
    required this.fileName,
    this.upscaleStatus = ProcessStatus.waiting,
    this.compressStatus = ProcessStatus.waiting,
    this.outputStatus = ProcessStatus.waiting,
  });

  /// 対象ファイルのファイル名。
  final String fileName;

  /// アップスケールの状態。
  final ProcessStatus upscaleStatus;

  /// 圧縮の状態。
  final ProcessStatus compressStatus;

  /// 出力の状態。
  final ProcessStatus outputStatus;

  /// 一連の処理（アップスケール・圧縮・出力）が全て完了したかどうか。
  bool get isDone =>
      outputStatus == ProcessStatus.success ||
      outputStatus == ProcessStatus.failure;

  /// 成功したかどうか。
  bool get isSuccess => outputStatus == ProcessStatus.success;

  FileProgress copyWith({
    String? fileName,
    ProcessStatus? upscaleStatus,
    ProcessStatus? compressStatus,
    ProcessStatus? outputStatus,
  }) {
    return FileProgress(
      fileName: fileName ?? this.fileName,
      upscaleStatus: upscaleStatus ?? this.upscaleStatus,
      compressStatus: compressStatus ?? this.compressStatus,
      outputStatus: outputStatus ?? this.outputStatus,
    );
  }
}
