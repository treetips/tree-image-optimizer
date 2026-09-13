import Foundation

/// 一括変換画面のフォーム状態と操作。設定の永続化・モデル一覧・実行指示を配線する。
/// 実行状態（進捗・結果）は共有の `ConvertJobStore` が持ち、このViewModelは持たない。
/// 画面遷移でViewModelが再生成されても、ジョブの進行は維持される。
@Observable
@MainActor
final class ConvertViewModel {
    var inputFolderPath: String = "" {
        didSet { validateFolders(); saveConvert() }
    }
    var outputFolderPath: String = "" {
        didSet { validateFolders(); saveConvert() }
    }
    var inputFolderHasError: Bool = false
    var outputFolderHasError: Bool = false
    var targetFilter: TargetFilter = .sevenDays {
        didSet { saveConvert() }
    }
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
    var parallelCount: Double = 3 {
        didSet { saveConvert() }
    }
    var maxParallel: Double = Double(max(1, ProcessInfo.processInfo.processorCount))
    var showWaiting: Bool = true
    var showRunning: Bool = true
    var showSuccess: Bool = true
    var showFailure: Bool = true

    /// 共有の実行状態。アプリ層で生成し、`ConvertView` 経由で注入する。
    let jobStore: ConvertJobStore

    /// 絞り込み後の表示行。いずれか1つでもチェックした状態を含む行を表示する。
    func filteredRows(for rows: [FileRow]) -> [FileRow] {
        rows.filter { row in
            let statuses = [row.upscale, row.compress, row.output]
            if showWaiting, statuses.contains(.waiting) { return true }
            if showRunning, statuses.contains(.running) { return true }
            if showSuccess, statuses.contains(.success) { return true }
            if showFailure, statuses.contains(.failure) { return true }
            return false
        }
    }

    /// 実行ボタンの活性条件。ジョブ実行中は非活性になる。
    var canRun: Bool {
        !jobStore.isRunning
            && !inputFolderPath.isEmpty
            && !outputFolderPath.isEmpty
            && !inputFolderHasError
            && !outputFolderHasError
    }

    private let paths: AppPaths
    private let store: SettingsStore

    init(
        paths: AppPaths = AppPaths(),
        store: SettingsStore? = nil,
        jobStore: ConvertJobStore? = nil
    ) {
        self.paths = paths
        self.store = store ?? SettingsStore(paths: paths)
        self.jobStore = jobStore ?? ConvertJobStore(paths: paths, store: self.store)
        maxParallel = Double(max(1, ProcessInfo.processInfo.processorCount))
        loadPersisted()
        models = TargetFiles.listModels(in: paths.upscalModelsURL)
        if !models.contains(selectedModel), let first = models.first {
            selectedModel = first
        }
    }

    private func loadPersisted() {
        guard let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        let c = file.batch
        if let filter = TargetFilter(rawValue: c.targetFilter) { targetFilter = filter }
        scale = Double(c.scale)
        selectedModel = c.model
        if let format = OutputFormat(rawValue: c.format) { self.format = format }
        if let type = OptimizeType(rawValue: c.optimizeType) { optimizeType = type }
        quality = Double(c.quality)
        parallelCount = Double(c.parallelCount)
        inputFolderPath = c.inputFolderPath ?? ""
        outputFolderPath = c.outputFolderPath ?? ""
        validateFolders()
    }

    private func saveConvert() {
        guard let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        var updated = file
        updated.batch.targetFilter = targetFilter.rawValue
        updated.batch.scale = Int(scale)
        updated.batch.model = selectedModel
        updated.batch.format = format.rawValue
        updated.batch.optimizeType = optimizeType.rawValue
        updated.batch.quality = Int(quality)
        updated.batch.parallelCount = Int(parallelCount)
        updated.batch.inputFolderPath = inputFolderPath.isEmpty ? nil : inputFolderPath
        updated.batch.outputFolderPath = outputFolderPath.isEmpty ? nil : outputFolderPath
        try? store.save(updated)
    }

    private func validateFolders() {
        inputFolderHasError = !inputFolderPath.isEmpty && !isExistingDirectory(inputFolderPath)
        outputFolderHasError = !outputFolderPath.isEmpty && !isExistingDirectory(outputFolderPath)
    }

    private func isExistingDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// 変換を実行する。対象列挙と設定スナップショット作成までを行い、
    /// 実処理と進捗管理は共有の `jobStore` に委譲する。
    func runConversion() {
        guard canRun else { return }
        let inputURL = URL(fileURLWithPath: inputFolderPath, isDirectory: true)
        let outputURL = URL(fileURLWithPath: outputFolderPath, isDirectory: true)
        let files: [URL]
        do {
            files = try TargetFiles.list(in: inputURL, modifiedWithinDays: TargetFiles.days(for: targetFilter))
        } catch {
            return
        }
        let config = ConvertConfig(
            scale: Int(scale),
            model: selectedModel,
            format: format,
            optimizeType: optimizeType,
            quality: Int(quality),
            parallelCount: Int(parallelCount)
        )
        jobStore.start(files: files, config: config, outputDirectory: outputURL)
    }
}
