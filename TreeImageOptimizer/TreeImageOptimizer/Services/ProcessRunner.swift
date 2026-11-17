import Darwin
import Foundation

/// 外部コマンドの実行結果。
struct ProcessResult: Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

/// 実行中プロセスの共有状態。キャンセルは別スレッドから届くため、
/// ロックで保護して「起動前」「起動後」のどちらで届いても取りこぼさない。
private final class ProcessExecutionState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var started = false
    private var cancelled = false
    /// 終了処理を始めたか。`onCancel` と起動直後の確認から二重に呼ばれても1回に抑える。
    private var terminating = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// SIGKILLを送る直前に、対象プロセスがまだ生きているか。
    var isTerminationTargetAlive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    func attach(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
    }

    /// 起動が終わったことを記録する。これ以前に終了処理を始めると、
    /// `Process.run()` と `terminate()` が別スレッドで同時に走ってしまう。
    func markStarted() {
        lock.lock()
        defer { lock.unlock() }
        started = true
    }

    func markCancelled() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }

    /// 起動済みで、まだ終了処理を始めていなければ対象プロセスを返す。
    /// 起動前はnilを返し、`run()` の直後の確認に終了処理を任せる。
    func beginTermination() -> Process? {
        lock.lock()
        defer { lock.unlock() }
        guard started, !terminating, let process else { return nil }
        terminating = true
        return process
    }
}

/// 外部コマンドを実行する。Flutter版 `ProcessService` に対応する。
/// 終了コードが0以外の場合は `AppError.processFailed` を投げる。
/// 実行中にタスクがキャンセルされたら子プロセスを終了し、`CancellationError` を投げる（ADR 0054）。
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
        let state = ProcessExecutionState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                // 変換はユーザーが明示的に開始した前景処理なので、QoSを上げて
                // Eコアへ回されにくくする。既定のままではバックグラウンド扱いになり、
                // エンコードが遅いコアに配置されることがある。
                process.qualityOfService = .userInitiated
                if let workingDirectory {
                    process.currentDirectoryURL = URL(
                        fileURLWithPath: workingDirectory, isDirectory: true)
                }
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.terminationHandler = { process in
                    Self.finish(
                        process: process, pipes: (outPipe, errPipe),
                        executable: executable, commandLine: commandLine,
                        cancelled: state.isCancelled, continuation: continuation)
                }
                state.attach(process)
                do {
                    try process.run()
                } catch {
                    AppLogger.shared.error(
                        "process launch failed: \(commandLine): \(error.localizedDescription)")
                    continuation.resume(throwing: AppError.toolMissing("\(executable): \(error)"))
                    return
                }
                // 起動前にキャンセルが届いていた場合は、走り出した子プロセスをすぐ止める。
                // Why not ここで state.markCancelled() を呼ぶか: 既に onCancel が
                // フラグを立てているため、二重に立てる必要はない。
                state.markStarted()
                if state.isCancelled, let process = state.beginTermination() {
                    Self.terminate(process, state: state)
                }
            }
        } onCancel: {
            state.markCancelled()
            if let process = state.beginTermination() {
                Self.terminate(process, state: state)
            }
        }
    }

    /// 子プロセスを終了する。SIGTERMを無視するツールに備えて、猶予後にSIGKILLも送る。
    /// Why not キャンセル時に何もしないか: `sleep` のようなプロセスが終了まで残り、
    /// キャンセルしてもアプリが数十秒待たされてしまうため。
    private static func terminate(_ process: Process, state: ProcessExecutionState) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            // Why not PIDだけでkillするか: 3秒以内に正常終了したPIDが別プロセスへ
            // 再利用されていると、無関係なプロセスを強制終了してしまうため。
            guard state.isTerminationTargetAlive else { return }
            kill(pid, SIGKILL)
        }
    }

    private static func finish(
        process: Process,
        pipes: (out: Pipe, err: Pipe),
        executable: String,
        commandLine: String,
        cancelled: Bool,
        continuation: CheckedContinuation<ProcessResult, Error>
    ) {
        let outData = pipes.out.fileHandleForReading.readDataToEndOfFile()
        let errData = pipes.err.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        if cancelled {
            // 途中まで出力が揃っていても成功として扱わない。呼び出し側は
            // このファイルを「キャンセル」として扱い、出力先へは確定しない。
            AppLogger.shared.info(
                """
                process cancelled: \(commandLine) exit=\(process.terminationStatus) \
                stdout=\(quotedForLog(stdout)) stderr=\(quotedForLog(stderr))
                """)
            continuation.resume(throwing: CancellationError())
            return
        }
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
