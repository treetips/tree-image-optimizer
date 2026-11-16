import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    @Test("正常終了時は出力を返す")
    func succeeds() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run("/bin/echo", args: ["hello"], workingDirectory: nil)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("hello"))
    }

    @Test("異常終了時はprocessFailedを投げる")
    func failsOnNonZeroExit() async {
        let runner = ProcessRunner()
        await #expect(throws: AppError.self) {
            try await runner.run("/usr/bin/false", args: [], workingDirectory: nil)
        }
    }

    @Test("存在しない実行ファイルはtoolMissingを投げる")
    func missingExecutable() async {
        let runner = ProcessRunner()
        await #expect(throws: AppError.self) {
            try await runner.run("/nonexistent/bin/foobar", args: [], workingDirectory: nil)
        }
    }

    @Test("キャンセル時は実行中の子プロセスを終了してCancellationErrorを投げる")
    func cancelsRunningProcess() async {
        let runner = ProcessRunner()
        let task = Task { try await runner.run("/bin/sleep", args: ["30"], workingDirectory: nil) }
        // プロセスが起動するのを待ってからキャンセルする。
        try? await Task.sleep(nanoseconds: 300_000_000)
        let started = Date()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("CancellationErrorを期待したが、処理が成功してしまった")
        } catch is CancellationError {
            // 期待どおり
        } catch {
            Issue.record("CancellationError以外のエラーが返った: \(error)")
        }
        // 30秒待たされず、SIGKILLの猶予内で終わること。
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
