import Foundation
import OSLog

let easyLogger = Logger(
    subsystem: "com.treeimageoptimizer.TreeImageOptimizer",
    category: "easyconvert"
)

/// かんたん変換画面のフォーム状態と操作。設定の永続化・ドロップ受付・実行指示を配線する。
/// アップスケール・圧縮・出力の設定は一括画面と `convert` セクションを共用する。
/// 共用セクションへの保存時は、かんたん画面が持たない項目（対象フォルダ・絞り込み等）を壊さない。
/// 実行状態（進捗・結果）は共有の `EasyConvertJobStore` が持ち、このViewModelは持たない。
/// 画面遷移でViewModelが再生成されても、ジョブの進行は維持される。
@Observable
@MainActor
final class EasyConvertViewModel {
    var scale: Double = 2 {
        didSet { saveConvert() }
    }
    var selectedModel: String = "realesr-animevideov3-x4" {
        didSet { saveConvert() }
    }
    var models: [String] = ["realesr-animevideov3-x4"]
    var format: OutputFormat = .jpegXL {
        didSet { saveConvert() }
    }
    var optimizeType: OptimizeType = .anime {
        didSet { saveConvert() }
    }
    var quality: Double = 80 {
        didSet { saveConvert() }
    }
    var outputFolderPath: String = "" {
        didSet { validateOutputFolder(); saveConvert() }
    }
    var outputFolderHasError: Bool = false
    var maxParallel: Double = Double(max(1, ProcessInfo.processInfo.processorCount))

    /// 共有の実行状態。アプリ層で生成し、`EasyConvertView` 経由で注入する。
    let jobStore: EasyConvertJobStore

    /// 実行状態の読み取り専用プロキシ。共有ジョブに転送する。
    var isRunning: Bool { jobStore.isRunning }
    var progressPercent: Double { jobStore.progressPercent }
    var successCount: Int { jobStore.successCount }
    var failureCount: Int { jobStore.failureCount }
    var resultMessage: String { jobStore.resultMessage }
    /// 直近の変換結果。nil=未実行、true=全件成功、false=1件でも失敗。ドロップエリアの枠色に使う。
    var lastRunSucceeded: Bool? { jobStore.lastRunSucceeded }

    /// 実行条件。出力フォルダが確定済みで、実行中でないこと。
    var canRun: Bool {
        !jobStore.isRunning
            && !outputFolderPath.isEmpty
            && !outputFolderHasError
    }

    private let paths: AppPaths
    private let store: SettingsStore

    init(
        paths: AppPaths = AppPaths(),
        store: SettingsStore? = nil,
        jobStore: EasyConvertJobStore? = nil
    ) {
        self.paths = paths
        self.store = store ?? SettingsStore(paths: paths)
        self.jobStore = jobStore ?? EasyConvertJobStore(paths: paths, store: self.store)
        maxParallel = Double(max(1, ProcessInfo.processInfo.processorCount))
        loadPersisted()
        models = TargetFiles.listModels(in: paths.upscalModelsURL)
        if !models.contains(selectedModel), let first = models.first {
            selectedModel = first
        }
    }

    private func loadPersisted() {
        guard let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        let c = file.easy
        scale = Double(c.scale)
        selectedModel = c.model
        if let format = OutputFormat(rawValue: c.format) { self.format = format }
        if let type = OptimizeType(rawValue: c.optimizeType) { optimizeType = type }
        quality = Double(c.quality)
        outputFolderPath = c.outputFolderPath ?? ""
        validateOutputFolder()
    }

    private func saveConvert() {
        guard let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        var updated = file
        updated.easy.scale = Int(scale)
        updated.easy.model = selectedModel
        updated.easy.format = format.rawValue
        updated.easy.optimizeType = optimizeType.rawValue
        updated.easy.quality = Int(quality)
        updated.easy.outputFolderPath = outputFolderPath.isEmpty ? nil : outputFolderPath
        try? store.save(updated)
    }

    private func validateOutputFolder() {
        outputFolderHasError = !outputFolderPath.isEmpty && !isExistingDirectory(outputFolderPath)
    }

    private func isExistingDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// ドロップされたURLから画像ファイルのみを抽出する（拡張子判定・純粋関数）。
    /// 画像以外は除外し、呼び出し側は空配列の場合に何も反応しない。
    nonisolated static func filterDroppedImageFiles(_ urls: [URL]) -> [URL] {
        urls.filter { TargetFiles.supportedExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// ドロップまたはファイル選択ダイアログで得たURLを受け付ける。画像ファイルを即座に変換する。
    /// URLが空の場合は反応せず、画像が1件もない場合はその旨を表示する。
    func acceptFileURLs(_ urls: [URL]) {
        guard !jobStore.isRunning else { return }
        guard !urls.isEmpty else { return }
        let files = Self.filterDroppedImageFiles(urls)
        easyLogger.info(
            "accept files: urls=\(urls.count, privacy: .public) first=\(urls.first?.lastPathComponent ?? "-", privacy: .public) images=\(files.count, privacy: .public) canRun=\(self.canRun, privacy: .public)"
        )
        guard !files.isEmpty else {
            jobStore.resultMessage = L10n.string("e.unsupportedDrop", language: currentLanguage())
            return
        }
        runConversion(files: files)
    }

    /// 変換を実行する。設定スナップショット作成までを行い、
    /// 実処理と進捗管理は共有の `jobStore` に委譲する。
    func runConversion(files: [URL]) {
        guard canRun && !files.isEmpty else { return }
        let outputURL = URL(fileURLWithPath: outputFolderPath, isDirectory: true)
        let storedParallel = (try? store.load(maxParallel: Int(maxParallel)).easy.parallelCount)
        let config = ConvertConfig(
            scale: Int(scale),
            model: selectedModel,
            format: format,
            optimizeType: optimizeType,
            quality: Int(quality),
            parallelCount: storedParallel ?? max(1, Int(maxParallel) / 2 - 1)
        )
        jobStore.start(files: files, config: config, outputDirectory: outputURL)
    }

    private func currentLanguage() -> String {
        (try? store.load(maxParallel: Int(maxParallel)).settings.language) ?? ""
    }
}
