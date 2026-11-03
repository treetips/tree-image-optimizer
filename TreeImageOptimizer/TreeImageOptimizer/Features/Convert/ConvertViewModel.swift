import Foundation

/// 一括変換画面のフォーム状態と操作。設定の永続化・モデル一覧・実行指示を配線する。
/// 実行状態（進捗・結果）は共有の `ConvertJobStore` が持ち、このViewModelは持たない。
/// 画面遷移でViewModelが再生成されても、ジョブの進行は維持される。
@Observable
@MainActor
final class ConvertViewModel {
    var inputFolderPath: String = "" {
        didSet {
            validateFolders()
            saveConvert()
        }
    }
    var outputFolderPath: String = "" {
        didSet {
            validateFolders()
            saveConvert()
        }
    }
    var inputFolderHasError: Bool = false
    var outputFolderHasError: Bool = false
    var targetFilter: TargetFilter = .sevenDays {
        didSet { saveConvert() }
    }
    var scale: Double = 2 {
        didSet {
            syncRealCuganModelForScale()
            saveConvert()
        }
    }
    var selectedModel: String = "realesr-animevideov3-x4" {
        didSet { saveConvert() }
    }
    var models: [String] = ["realesr-animevideov3-x4"]
    /// アップスケーラーのエンジン。切替時に拡大率の範囲とモデル一覧を同期する。
    var engine: UpscaleEngine = .upscayl {
        didSet {
            guard engine != oldValue else { return }
            syncEngineChange()
            saveConvert()
        }
    }
    /// Real-CUGANのモデルID（`models-se/up2x-conservative` 形式）。
    var selectedRealCuganModel: String = "models-se/up2x-conservative" {
        didSet { saveConvert() }
    }
    /// Real-CUGANのカタログ。初期化時に `tools/realcugan` を走査して作る。
    private(set) var realCuganModels: [RealCUGANModel] = []
    /// Real-CUGANが実行可能か。未配置（任意ツール）の場合はfalseで実行を無効化する。
    private(set) var realCuganAvailable: Bool = false

    /// エンジンごとのスライダー範囲。Real-CUGANは2〜4（1xモデルが存在しないため）。
    var scaleRange: ClosedRange<Double> { engine.scaleRange }

    /// 選択中エンジンのモデル選択肢。現在の拡大率に合うものだけを示す。
    var modelOptions: [UpscaleModelOption] {
        if engine == .realCUGAN {
            return RealCUGANModels.models(models: realCuganModels, scale: Int(scale))
                .map { UpscaleModelOption(id: $0.id, label: $0.label) }
        }
        return models.map { UpscaleModelOption(id: $0, label: $0) }
    }

    /// 現在選択中のモデルID。エンジンごとに保存先が異なる。
    var selectedModelID: String {
        engine == .realCUGAN ? selectedRealCuganModel : selectedModel
    }

    /// モデルを選択する。エンジンごとの保存先へ書き込む。
    func selectModel(id: String) {
        if engine == .realCUGAN {
            selectedRealCuganModel = id
        } else {
            selectedModel = id
        }
    }
    var format: OutputFormat = .jpegXL {
        didSet { saveConvert() }
    }
    var optimizeType: OptimizeType = .anime {
        didSet { saveConvert() }
    }
    var quality: Double = 80 {
        didSet { saveConvert() }
    }
    var parallelCount: Double = Double(HardwareInfo.defaultParallelCount()) {
        didSet { saveConvert() }
    }
    var maxParallel: Double = Double(max(1, HardwareInfo.performanceCoreCount()))
    /// 実行結果の表の絞り込み。次回起動時に復元する（ADR 0041）。
    var showWaiting: Bool = true {
        didSet { saveConvert() }
    }
    var showRunning: Bool = true {
        didSet { saveConvert() }
    }
    var showSuccess: Bool = true {
        didSet { saveConvert() }
    }
    var showFailure: Bool = true {
        didSet { saveConvert() }
    }

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
    /// Real-CUGAN選択時はツールが揃っていることも条件にする。
    var canRun: Bool {
        !jobStore.isRunning
            && !inputFolderPath.isEmpty
            && !outputFolderPath.isEmpty
            && !inputFolderHasError
            && !outputFolderHasError
            && (engine != .realCUGAN || realCuganAvailable)
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
        maxParallel = Double(max(1, HardwareInfo.performanceCoreCount()))
        loadRealCuganCatalog()
        loadPersisted()
        reloadTools()
    }

    /// ツール配置の変化にカタログ・利用可否・モデル一覧を追従させる。
    /// Why not: 初期化時のみの読込では、ブートストラップのダウンロード完了前に
    /// 作られた「未配置」の状態が残り、配置済みでも未配置表示が消えないため。
    func reloadTools() {
        loadRealCuganCatalog()
        models = TargetFiles.listModels(in: paths.upscalModelsURL)
        if !models.contains(selectedModel), let first = models.first {
            selectedModel = first
        }
        applyRealCuganResolution()
    }

    /// Real-CUGANのカタログと利用可否を読む。設定より先に行い、後続の解決に使う。
    private func loadRealCuganCatalog() {
        realCuganModels = RealCUGANModels.catalog(in: paths.realCuganRootURL)
        realCuganAvailable =
            !realCuganModels.isEmpty
            && FileManager.default.fileExists(atPath: paths.realCuganBinURL.path)
    }

    /// 保存済みReal-CUGANモデルIDをカタログに解決し、見つからなければ補正する。
    private func applyRealCuganResolution() {
        let resolved = RealCUGANModels.resolve(
            id: selectedRealCuganModel, catalog: realCuganModels, scale: Int(scale))
        selectedRealCuganModel = resolved.id
    }

    /// エンジン切替時の同期。拡大率を範囲へクランプし、モデル選択を復元する。
    private func syncEngineChange() {
        scale = min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
        applyRealCuganResolution()
    }

    /// Real-CUGAN選択中に拡大率が変わったとき、対応する拡大率のモデルへ切替える。
    private func syncRealCuganModelForScale() {
        guard engine == .realCUGAN else { return }
        let current = RealCUGANModel.parse(selectedRealCuganModel)
        if current?.scale == Int(scale) { return }
        applyRealCuganResolution()
    }

    private func loadPersisted() {
        guard let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        let c = file.batch
        if let filter = TargetFilter(rawValue: c.targetFilter) { targetFilter = filter }
        scale = Double(c.scale)
        selectedModel = c.model
        if let engineValue = UpscaleEngine(rawValue: c.engine) { engine = engineValue }
        selectedRealCuganModel = c.realCuganModel
        if let format = OutputFormat(rawValue: c.format) { self.format = format }
        if let type = OptimizeType(rawValue: c.optimizeType) { optimizeType = type }
        quality = Double(c.quality)
        parallelCount = Double(c.parallelCount)
        inputFolderPath = c.inputFolderPath ?? ""
        outputFolderPath = c.outputFolderPath ?? ""
        showWaiting = c.showWaiting
        showRunning = c.showRunning
        showSuccess = c.showSuccess
        showFailure = c.showFailure
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
        // Real-CUGANは拡大率2〜4のため、モデルの拡大率と揃える。
        if engine == .realCUGAN { updated.batch.scale = Int(scale) }
        updated.batch.engine = engine.rawValue
        updated.batch.realCuganModel = selectedRealCuganModel
        updated.batch.showWaiting = showWaiting
        updated.batch.showRunning = showRunning
        updated.batch.showSuccess = showSuccess
        updated.batch.showFailure = showFailure
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
        let realCuganModel = RealCUGANModel.parse(selectedRealCuganModel)
        let config = ConvertConfig(
            scale: Int(scale),
            model: selectedModel,
            format: format,
            optimizeType: optimizeType,
            quality: Int(quality),
            parallelCount: Int(parallelCount),
            engine: engine,
            realCuganModel: engine == .realCUGAN ? realCuganModel : nil
        )
        jobStore.start(files: files, config: config, outputDirectory: outputURL)
    }
}
