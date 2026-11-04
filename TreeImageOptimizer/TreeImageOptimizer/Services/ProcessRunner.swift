import Foundation

/// 外部コマンドの実行結果。
struct ProcessResult: Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

/// 外部コマンドを実行する。Flutter版 `ProcessService` に対応する。
/// 終了コードが0以外の場合は `AppError.processFailed` を投げる。
struct ProcessRunner: Sendable {
    func run(
        _ executable: String,
        args: [String] = [],
        workingDirectory: String? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let commandLine = Self.describe(executable: executable, args: args)
        AppLogger.shared.info(
            "process start: \(commandLine) cwd=\(workingDirectory ?? "-")")
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            // 変換はユーザーが明示的に開始した前景処理なので、QoSを上げて
            // Eコアへ回されにくくする。既定のままではバックグラウンド扱いになり、
            // エンコードが遅いコアに配置されることがある。
            process.qualityOfService = .userInitiated
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            }
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.terminationHandler = { _ in
                Self.finish(
                    process: process, pipes: (outPipe, errPipe),
                    executable: executable, commandLine: commandLine, continuation: continuation)
            }
            do {
                try process.run()
            } catch {
                AppLogger.shared.error(
                    "process launch failed: \(commandLine): \(error.localizedDescription)")
                continuation.resume(throwing: AppError.toolMissing("\(executable): \(error)"))
            }
        }
    }

    private static func finish(
        process: Process,
        pipes: (out: Pipe, err: Pipe),
        executable: String,
        commandLine: String,
        continuation: CheckedContinuation<ProcessResult, Error>
    ) {
        let outData = pipes.out.fileHandleForReading.readDataToEndOfFile()
        let errData = pipes.err.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            AppLogger.shared.error(
                """
                process failed: \(commandLine) exit=\(process.terminationStatus) \
                stdout=\(quotedForLog(stdout)) stderr=\(quotedForLog(stderr))
                """)
            continuation.resume(
                throwing: AppError.processFailed(
                    executable: executable,
                    exitCode: process.terminationStatus,
                    output: "\(stdout)\n\(stderr)"
                ))
        } else {
            AppLogger.shared.info(
                """
                process finish: \(commandLine) exit=0 \
                stdout=\(quotedForLog(stdout)) stderr=\(quotedForLog(stderr))
                """)
            continuation.resume(
                returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                ))
        }
    }

    /// ログ用のコマンド表記。空白を含む引数はダブルクォートで囲む。
    static func describe(executable: String, args: [String]) -> String {
        ([executable] + args).map(quotedArgument).joined(separator: " ")
    }

    private static func quotedArgument(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" }) else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// 改行・制御文字を含む出力を1行で読めるようにする。
    static func quotedForLog(_ value: String) -> String {
        guard !value.isEmpty else { return "\"\"" }
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
