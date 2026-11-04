import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("AppLogger")
struct AppLoggerTests {
    func makeDirectory() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("設定したディレクトリへ日付ファイルで追記する")
    func writesDailyFile() throws {
        let directory = try makeDirectory()
        let logger = AppLogger()
        logger.configure(directoryURL: directory)
        logger.info("hello")
        logger.error("failed")

        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        let log = try #require(
            files.first { $0.lastPathComponent.hasPrefix("app.") && $0.pathExtension == "log" })
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("[INFO] hello"))
        #expect(text.contains("[ERROR] failed"))
    }

    @Test("保持期間を超えたログファイルを削除する")
    func removesExpiredLogs() throws {
        let directory = try makeDirectory()
        let old = directory.appendingPathComponent("app.20000101.log", isDirectory: false)
        FileManager.default.createFile(atPath: old.path, contents: Data("old".utf8))
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-10 * 24 * 60 * 60)],
            ofItemAtPath: old.path)

        let logger = AppLogger()
        logger.configure(directoryURL: directory, retentionDays: 3)

        #expect(!FileManager.default.fileExists(atPath: old.path))
    }
}
