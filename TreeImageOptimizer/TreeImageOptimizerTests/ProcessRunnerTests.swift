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
}
