import Foundation

/// 一括変換とかんたん変換で共有する変換設定。
/// エンジン・拡大率・Real-CUGANモデル・圧縮・自動最適化をここに集約し、
/// `settings.json` の `batchConvert` / `easyConvert` へ保存する。
/// 画面固有の項目（フォルダ・絞り込み・出力先）は各ViewModelが持つ。
@Observable
@MainActor
final class ConversionSettings {
    /// 保存先のセクション。一括画面と、かんたん画面で独立に保存する。
    enum Scope: Sendable {
        case batch
        case easy
    }

    var scale: Double = 2 {
        didSet {
            syncRealCuganModelForScale()
            persist()
        }
    }
    var selectedModel: String = "realesr-animevideov3-x4" {
        didSet { persist() }
    }
    /// アップスケーラーのエンジン。切替時に拡大率の範囲とモデル一覧を同期する。
    var engine: UpscaleEngine = .upscayl {
        didSet {
            guard engine != oldValue else { return }
            syncEngineChange()
            persist()
        }
    }
    /// Real-CUGANのモデルID（`models-se/up2x-conservative` 形式）。
    var selectedRealCuganModel: String = "models-se/up2x-conservative" {
        didSet { persist() }
    }
    var format: OutputFormat = .jpegXL {
        didSet { persist() }
    }
    var optimizeType: OptimizeType = .anime {
        didSet { persist() }
    }
    var quality: Double = 80 {
        didSet { persist() }
    }
    /// 固定最適化 / 自動最適化（ADR 0049）。かんたん画面は固定のみ。
    var mode: ConvertMode = .fixed {
        didSet { persist() }
    }
    /// 自動最適化のコンテンツ種別。
    var contentType: ContentType = .anime {
        didSet { persist() }
    }
    /// 自動最適化の目標解像度。
    var targetSize: TargetSize = .fiveK {
        didSet { persist() }
    }
    /// 自動最適化の画質プリセット。
    var qualityPreset: QualityPreset = .high {
        didSet { persist() }
    }
    var parallelCount: Double = Double(HardwareInfo.defaultParallelCount()) {
        didSet { persist() }
    }

    /// 配置済みのupscaylモデル一覧。
    private(set) var models: [String] = ["realesr-animevideov3-x4"]
    /// Real-CUGANのカタログ。初期化時に `tools/realcugan` を走査して作る。
    private(set) var realCuganModels: [RealCUGANModel] = []
    /// Real-CUGANが実行可能か。未配置（任意ツール）の場合はfalseで実行を無効化する。
    private(set) var realCuganAvailable: Bool = false

    var maxParallel: Double = Double(max(1, HardwareInfo.performanceCoreCount()))

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

    private let scope: Scope
    private let paths: AppPaths
    private let store: SettingsStore
    /// 読み込み中の代入では保存しない（起動直後に保存し直さないため）。
    private var isLoading = false

    init(scope: Scope, paths: AppPaths = AppPaths(), store: SettingsStore? = nil) {
        self.scope = scope
        self.paths = paths
        self.store = store ?? SettingsStore(paths: paths)
        maxParallel = Double(max(1, HardwareInfo.performanceCoreCount()))
        loadRealCuganCatalog()
        loadPersisted()
        reloadTools()
    }

    /// モデルを選択する。エンジンごとの保存先へ書き込む。
    func selectModel(id: String) {
        if engine == .realCUGAN {
            selectedRealCuganModel = id
        } else {
            selectedModel = id
        }
    }

    /// 実行用のスナップショットを作る。かんたん画面は常に固定最適化にする。
    func makeConfig() -> ConvertConfig {
        ConvertConfig(
            scale: Int(scale),
            model: selectedModel,
            format: format,
            optimizeType: optimizeType,
            quality: Int(quality),
            parallelCount: Int(parallelCount),
            engine: engine,
            realCuganModel: engine == .realCUGAN
                ? RealCUGANModel.parse(selectedRealCuganModel) : nil,
            mode: scope == .easy ? .fixed : mode,
            contentType: contentType,
            targetSize: targetSize,
            qualityPreset: qualityPreset
        )
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
        isLoading = true
        defer { isLoading = false }
        guard let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        switch scope {
        case .batch:
            let batch = file.batch
            scale = Double(batch.scale)
            selectedModel = batch.model
            if let value = UpscaleEngine(rawValue: batch.engine) { engine = value }
            selectedRealCuganModel = batch.realCuganModel
            if let value = OutputFormat(rawValue: batch.format) { format = value }
            if let value = OptimizeType(rawValue: batch.optimizeType) { optimizeType = value }
            quality = Double(batch.quality)
            if let value = ConvertMode(rawValue: batch.mode) { mode = value }
            if let value = ContentType(rawValue: batch.contentType) { contentType = value }
            if let value = TargetSize(rawValue: batch.targetSize) { targetSize = value }
            if let value = QualityPreset(rawValue: batch.qualityPreset) { qualityPreset = value }
            parallelCount = Double(batch.parallelCount)
        case .easy:
            let easy = file.easy
            scale = Double(easy.scale)
            selectedModel = easy.model
            if let value = UpscaleEngine(rawValue: easy.engine) { engine = value }
            selectedRealCuganModel = easy.realCuganModel
            if let value = OutputFormat(rawValue: easy.format) { format = value }
            if let value = OptimizeType(rawValue: easy.optimizeType) { optimizeType = value }
            quality = Double(easy.quality)
            parallelCount = Double(easy.parallelCount)
        }
    }

    private func persist() {
        guard !isLoading, let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        var updated = file
        switch scope {
        case .batch:
            updated.batch.scale = Int(scale)
            updated.batch.model = selectedModel
            updated.batch.format = format.rawValue
            updated.batch.optimizeType = optimizeType.rawValue
            updated.batch.quality = Int(quality)
            updated.batch.mode = mode.rawValue
            updated.batch.contentType = contentType.rawValue
            updated.batch.targetSize = targetSize.rawValue
            updated.batch.qualityPreset = qualityPreset.rawValue
            updated.batch.parallelCount = Int(parallelCount)
            updated.batch.engine = engine.rawValue
            updated.batch.realCuganModel = selectedRealCuganModel
        case .easy:
            updated.easy.scale = Int(scale)
            updated.easy.model = selectedModel
            updated.easy.format = format.rawValue
            updated.easy.optimizeType = optimizeType.rawValue
            updated.easy.quality = Int(quality)
            updated.easy.parallelCount = Int(parallelCount)
            updated.easy.engine = engine.rawValue
            updated.easy.realCuganModel = selectedRealCuganModel
        }
        try? store.save(updated)
    }
}
