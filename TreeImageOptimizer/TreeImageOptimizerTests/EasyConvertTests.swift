import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("EasyConvert")
struct EasyConvertTests {
    func makeStore() throws -> SettingsStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SettingsStore(fileURL: dir.appendingPathComponent("settings.json", isDirectory: false))
    }

    @Test("初期値は一括画面と同一")
    @MainActor
    func defaults() throws {
        let viewModel = EasyConvertViewModel(store: try makeStore())
        #expect(viewModel.scale == 2)
        #expect(viewModel.selectedModel == "realesr-animevideov3-x4")
        #expect(viewModel.format == .jpegXL)
        #expect(viewModel.optimizeType == .anime)
        #expect(viewModel.quality == 80)
        #expect(viewModel.isRunning == false)
        #expect(viewModel.progressPercent == 0)
        #expect(viewModel.canRun == false)
    }

    @Test("ドロップ画像の選別は拡張子で行う")
    func filterDroppedImageFiles() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.jpg"),
            URL(fileURLWithPath: "/tmp/b.JPG"),
            URL(fileURLWithPath: "/tmp/c.jpeg"),
            URL(fileURLWithPath: "/tmp/d.png"),
            URL(fileURLWithPath: "/tmp/e.webp"),
            URL(fileURLWithPath: "/tmp/f.txt"),
            URL(fileURLWithPath: "/tmp/g.pdf"),
            URL(fileURLWithPath: "/tmp/noext"),
        ]
        let filtered = EasyConvertViewModel.filterDroppedImageFiles(urls)
        #expect(filtered.map { $0.lastPathComponent } == ["a.jpg", "b.JPG", "c.jpeg", "d.png", "e.webp"])
        #expect(EasyConvertViewModel.filterDroppedImageFiles([]).isEmpty)
    }

    @Test("空のURLには反応しない")
    @MainActor
    func emptyURLsAreIgnored() throws {
        let viewModel = EasyConvertViewModel(store: try makeStore())
        viewModel.outputFolderPath = NSTemporaryDirectory()
        viewModel.acceptFileURLs([])
        #expect(viewModel.isRunning == false)
        #expect(viewModel.resultMessage.isEmpty)
    }

    @Test("ファイル選択で画像以外はメッセージを表示して実行しない")
    @MainActor
    func pickedUnsupportedShowsMessage() throws {
        let viewModel = EasyConvertViewModel(store: try makeStore())
        viewModel.outputFolderPath = NSTemporaryDirectory()
        #expect(viewModel.lastRunSucceeded == nil)
        viewModel.acceptFileURLs([URL(fileURLWithPath: "/tmp/note.txt")])
        #expect(viewModel.isRunning == false)
        #expect(!viewModel.resultMessage.isEmpty)
    }

    @Test("出力フォルダが有効なら実行可能")
    @MainActor
    func canRunWithValidOutputFolder() throws {
        let viewModel = EasyConvertViewModel(store: try makeStore())
        viewModel.outputFolderPath = NSTemporaryDirectory()
        #expect(viewModel.outputFolderHasError == false)
        #expect(viewModel.canRun == true)
    }

    @Test("一括画面と設定が独立している")
    @MainActor
    func independentFromBatchSettings() throws {
        let store = try makeStore()
        var file = try store.load(maxParallel: 8)
        file.batch.inputFolderPath = "/tmp/batch-input"
        file.batch.outputFolderPath = "/tmp/batch-output"
        file.batch.scale = 4
        try store.save(file)

        let viewModel = EasyConvertViewModel(store: store)
        viewModel.scale = 3
        viewModel.outputFolderPath = "/tmp/easy-output"

        let reloaded = try store.load(maxParallel: 8)
        // かんたん側の変更が保存されている
        #expect(reloaded.easy.scale == 3)
        #expect(reloaded.easy.outputFolderPath == "/tmp/easy-output")
        // 一括側は壊れていない
        #expect(reloaded.batch.scale == 4)
        #expect(reloaded.batch.inputFolderPath == "/tmp/batch-input")
        #expect(reloaded.batch.outputFolderPath == "/tmp/batch-output")
    }
}
