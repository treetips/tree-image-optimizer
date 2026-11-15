import Foundation
import OSLog

let easyLogger = Logger(
    subsystem: "com.treeimageoptimizer.TreeImageOptimizer",
    category: "easyconvert"
)

/// かんたん変換画面のフォーム状態と操作。
/// 変換設定は `ConversionSettings`（`easyConvert` セクション）に集約し、
/// このViewModelは画面固有の項目（出力先・ドロップ受付・実行指示）だけを持つ。
@Observable
@MainActor
final class EasyConvertViewModel {
    var outputFolderPath: String = "" {
        didSet {
            validateOutputFolder()
            saveEasyFields()
        }
    }
    var outputFolderHasError: Bool = false

    /// 変換設定。一括変換画面と共通の型を使う。
    let settings: ConversionSettings
    /// 共有の実行状態。アプリ層で生成し、`EasyConvertView` 経由で注入する。
    let jobStore: EasyConvertJobStore

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
    var maxParallel: Double { settings.maxParallel }

    func selectModel(id: String) {
        settings.selectModel(id: id)
    }

    func reloadTools() {
        settings.reloadTools()
    }

    // MARK: - Job state proxies

    var isRunning: Bool { jobStore.isRunning }
    var progressPercent: Double { jobStore.progressPercent }
    var successCount: Int { jobStore.successCount }
    var failureCount: Int { jobStore.failureCount }
    var resultMessage: String { jobStore.resultMessage }
    /// 直近の変換結果。nil=未実行、true=全件成功、false=1件でも失敗。ドロップエリアの枠色に使う。
    var lastRunSucceeded: Bool? { jobStore.lastRunSucceeded }

    /// 実行条件。出力フォルダが確定済みで、実行中でないこと。
    /// Real-CUGAN選択時はツールが揃っていることも条件にする。
    var canRun: Bool {
        !jobStore.isRunning
            && !outputFolderPath.isEmpty
            && !outputFolderHasError
            && (settings.engine != .realCUGAN || settings.realCuganAvailable)
    }

    private let store: SettingsStore
    private var isLoading = false

    init(
        paths: AppPaths = AppPaths(),
        store: SettingsStore? = nil,
        jobStore: EasyConvertJobStore? = nil
    ) {
        let resolvedStore = store ?? SettingsStore(paths: paths)
        self.store = resolvedStore
        self.settings = ConversionSettings(scope: .easy, paths: paths, store: resolvedStore)
        self.jobStore = jobStore ?? EasyConvertJobStore(paths: paths, store: resolvedStore)
        loadEasyFields()
    }

    /// 画面固有の保存項目を読み込む。変換設定は `ConversionSettings` が読み込み済み。
    private func loadEasyFields() {
        isLoading = true
        defer { isLoading = false }
        guard let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        outputFolderPath = file.easy.outputFolderPath ?? ""
        validateOutputFolder()
    }

    /// 画面固有の項目だけを保存する。変換設定は `ConversionSettings` が保存する。
    private func saveEasyFields() {
        guard !isLoading, let file = try? store.load(maxParallel: Int(maxParallel)) else { return }
        var updated = file
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
        let first = urls.first?.lastPathComponent ?? "-"
        easyLogger.info(
            """
            accept files: urls=\(urls.count, privacy: .public) first=\(first, privacy: .public) \
            images=\(files.count, privacy: .public) canRun=\(self.canRun, privacy: .public)
            """)

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
        jobStore.start(
            files: files, config: settings.makeConfig(), outputDirectory: outputURL)
    }

    private func currentLanguage() -> String {
        (try? store.load(maxParallel: Int(maxParallel)).settings.language) ?? ""
    }
}
