import Foundation
import Testing

@testable import TreeImageOptimizer

/// 一括変換の共有ジョブ層のテスト。実行状態（進捗・結果）の生成を検証する。
@MainActor
@Suite("ConvertJobStore")
struct ConvertJobStoreTests {
    @Test("進捗表の行生成（ファイル名・変換前後のパス・初期値）")
    func makeRows() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        let inputDirectory = base.appendingPathComponent("input", isDirectory: true)
        let outputDirectory = base.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let files = ["aaa.jpg", "b.c.png"].map {
            inputDirectory.appendingPathComponent($0, isDirectory: false)
        }

        let rows = ConvertJobStore.makeRows(
            files: files, format: .webp, outputDirectory: outputDirectory)

        #expect(rows.count == 2)
        #expect(rows.map(\.fileName) == ["aaa.jpg", "b.c.png"])
        #expect(rows.map(\.sourcePath) == files.map(\.path))
        // 出力名は拡張子直前ではなく最初のドットで切る既存仕様に一致する。
        #expect(
            rows.map(\.outputPath) == [
                outputDirectory.appendingPathComponent("aaa.webp").path,
                outputDirectory.appendingPathComponent("b.webp").path
            ])
        #expect(rows.allSatisfy { $0.upscale == .waiting && $0.compress == .waiting && $0.output == .waiting })
    }
    @Test("失敗行があるときだけ再実行可能と判定する")
    func canRetryFailed() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let store = ConvertJobStore(paths: AppPaths(baseURL: base))
        store.rows = [
            FileRow(fileName: "ok.png", upscale: .success, compress: .success, output: .success),
            FileRow(fileName: "ng.png", upscale: .success, compress: .failure, output: .waiting)
        ]
        #expect(store.canRetryFailed, "失敗行があれば再実行可能であること")

        store.rows = [FileRow(fileName: "ok.png", upscale: .success, compress: .success, output: .success)]
        #expect(!store.canRetryFailed, "失敗行が無ければ再実行不可であること")
    }

    @Test("直近の実行設定が無ければ再実行は何もしない")
    func retryFailedRequiresLastRun() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let store = ConvertJobStore(paths: AppPaths(baseURL: base))
        store.rows = [
            FileRow(fileName: "ng.png", upscale: .failure, compress: .waiting, output: .waiting)
        ]
        store.retryFailed()
        #expect(!store.isRunning, "設定が無いため実行を開始しないこと")
    }
}
