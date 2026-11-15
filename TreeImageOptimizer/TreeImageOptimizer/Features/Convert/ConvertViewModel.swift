import Foundation

/// 一括変換画面のフォーム状態と操作。
/// 変換設定（エンジン・拡大率・圧縮・自動最適化）は `ConversionSettings` に集約し、
/// このViewModelは画面固有の項目（フォルダ・絞り込み・実行指示）だけを持つ。
/// 実行状態（進捗・結果）は共有の `ConvertJobStore` が持つ。
@Observable
@MainActor
final class ConvertViewModel {
    var inputFolderPath: String = "" {
        didSet {
            validateFolders()
            saveBatchFields()
        }
    }
    var outputFolderPath: String = "" {
        didSet {
            validateFolders()
            saveBatchFields()
        }
    }
    var inputFolderHasError: Bool = false
    var outputFolderHasError: Bool = false
    var targetFilter: TargetFilter = .sevenDays {
        didSet { saveBatchFields() }
    }
    /// 実行結果の表の絞り込み。次回起動時に復元する（ADR 0041）。
    var showWaiting: Bool = true {
        didSet { saveBatchFields() }
    }
    var showRunning: Bool = true {
        didSet { saveBatchFields() }
    }
    var showSuccess: Bool = true {
        didSet { saveBatchFields() }
    }
    var showFailure: Bool = true {
        didSet { saveBatchFields() }
    }
    /// モードの特徴コールアウトの展開状態。固定・自動で共用する。
    var modeNoteExpanded: Bool = true {
        didSet { saveBatchFields() }
    }

    /// 変換設定。かんたん変換画面と共通の型を使う。
    let settings: ConversionSettings
    /// 共有の実行状態。アプリ層で生成し、`ConvertView` 経由で注入する。
    let jobStore: ConvertJobStore

    // MARK: - ConversionSettings へのプロキシ
    // Why not: 画面とテストのバインディングを変えずに、設定の実体を1か所へ寄せるため。

    var scale: Double {
        get { settings.scale }
        set { settings.scale = newValue }
    }
    var selectedModel: String {
        get { settings.selectedModel }
        set { settings.selectedModel = newValue }
    }
    var models: [String] { settings.models }
    var engine: UpscaleEngine {
        get { settings.engine }
        set { settings.engine = newValue }
    }
    var selectedRealCuganModel: String {
        get { settings.selectedRealCuganModel }
        set { settings.selectedRealCuganModel = newValue }
    }
    var realCuganModels: [RealCUGANModel] { settings.realCuganModels }
    var realCuganAvailable: Bool { settings.realCuganAvailable }
    var scaleRange: ClosedRange<Double> { settings.scaleRange }
    var modelOptions: [UpscaleModelOption] { settings.modelOptions }
    var selectedModelID: String { settings.selectedModelID }
    var format: OutputFormat {
        get { settings.format }
        set { settings.format = newValue }
    }
    var optimizeType: OptimizeType {
        get { settings.optimizeType }
        set { settings.optimizeType = newValue }
    }
    var quality: Double {
        get { settings.quality }
        set { settings.quality = newValue }
    }
    var mode: ConvertMode {
        get { settings.mode }
        set { settings.mode = newValue }
    }
    var contentType: ContentType {
        get { settings.contentType }
        set { settings.contentType = newValue }
    }
    var targetSize: TargetSize {
        get { settings.targetSize }
        set { settings.targetSize = newValue }
    }
    var qualityPreset: QualityPreset {
        get { settings.qualityPreset }
        set { settings.qualityPreset = newValue }
    }
    var parallelCount: Double {
        get { settings.parallelCount }
        set { settings.parallelCount = newValue }
    }
    var maxParallel: Double { settings.maxParallel }

    func selectModel(id: String) {
        settings.selectModel(id: id)
    }

    func reloadTools() {
        settings.reloadTools()
    }

    // MARK: - Screen specific

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
    /// Real-CUGAN選択時はツールが揃っていることも条件にする。
    var canRun: Bool {
        !jobStore.isRunning
            && !inputFolderPath.isEmpty
            && !outputFolderPath.isEmpty
            && !inputFolderHasError
            && !outputFolderHasError
            && (settings.engine != .realCUGAN || settings.realCuganAvailable)
    }

    private let store: SettingsStore
    private var isLoading = false

    init(
        paths: AppPaths = AppPaths(),
        store: SettingsStore? = nil,
        jobStore: ConvertJobStore? = nil
    ) {
        let resolvedStore = store ?? SettingsStore(paths: paths)
        self.store = resolvedStore
        self.settings = ConversionSettings(scope: .batch, paths: paths, store: resolvedStore)
        self.jobStore = jobStore ?? ConvertJobStore(paths: paths, store: resolvedStore)
        loadBatchFields()
    }

    /// 画面固有の保存項目を読み込む。変換設定は `ConversionSettings` が読み込み済み。
    private func loadBatchFields() {
        isLoading = true
        defer { isLoading = false }
        guard let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        let batch = file.batch
        if let filter = TargetFilter(rawValue: batch.targetFilter) { targetFilter = filter }
        inputFolderPath = batch.inputFolderPath ?? ""
        outputFolderPath = batch.outputFolderPath ?? ""
        showWaiting = batch.showWaiting
        showRunning = batch.showRunning
        showSuccess = batch.showSuccess
        showFailure = batch.showFailure
        modeNoteExpanded = batch.modeNoteExpanded
        validateFolders()
    }

    /// 画面固有の項目だけを保存する。変換設定は `ConversionSettings` が保存する。
    private func saveBatchFields() {
        guard !isLoading, let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        var updated = file
        updated.batch.targetFilter = targetFilter.rawValue
        updated.batch.inputFolderPath = inputFolderPath.isEmpty ? nil : inputFolderPath
        updated.batch.outputFolderPath = outputFolderPath.isEmpty ? nil : outputFolderPath
        updated.batch.showWaiting = showWaiting
        updated.batch.showRunning = showRunning
        updated.batch.showSuccess = showSuccess
        updated.batch.showFailure = showFailure
        updated.batch.modeNoteExpanded = modeNoteExpanded
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
            files = try TargetFiles.list(
                in: inputURL, modifiedWithinDays: TargetFiles.days(for: targetFilter))
        } catch {
            return
        }
        jobStore.start(
            files: files, config: settings.makeConfig(), outputDirectory: outputURL)
    }
}
