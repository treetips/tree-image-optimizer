import AVFoundation
import Foundation
import OSLog

let easyLogger = Logger(
    subsystem: "com.treeimageoptimizer.TreeImageOptimizer",
    category: "easyconvert"
)

/// かんたん画像変換画面の状態と処理。設定の永続化・ドロップ受付・変換実行を配線する。
/// アップスケール・圧縮・出力の設定は一括画面と `convert` セクションを共用する。
/// 共用セクションへの保存時は、かんたん画面が持たない項目（対象フォルダ・絞り込み等）を壊さない。
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
    var isRunning: Bool = false
    var progressPercent: Double = 0
    var successCount: Int = 0
    var failureCount: Int = 0
    var resultMessage: String = ""
    /// 直近の変換結果。nil=未実行、true=全件成功、false=1件でも失敗。ドロップエリアの枠色に使う。
    var lastRunSucceeded: Bool?
    var maxParallel: Double = Double(max(1, ProcessInfo.processInfo.processorCount))

    private var completedCount: Int = 0
    private var totalCount: Int = 0

    /// 実行条件。出力フォルダが確定済みで、実行中でないこと。
    var canRun: Bool {
        !isRunning
            && !outputFolderPath.isEmpty
            && !outputFolderHasError
    }

    private let paths: AppPaths
    private let store: SettingsStore
    private let orchestrator: ConvertOrchestrator
    private var soundService: SoundService
    private var audioPlayer: AVAudioPlayer?
    private var runTask: Task<Void, Never>?

    init(
        paths: AppPaths = AppPaths(),
        store: SettingsStore? = nil,
        orchestrator: ConvertOrchestrator = ConvertOrchestrator(),
        soundService: SoundService? = nil
    ) {
        self.paths = paths
        self.store = store ?? SettingsStore(paths: paths)
        self.orchestrator = orchestrator
        self.soundService = soundService ?? SoundService(paths: paths)
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
        guard !isRunning else { return }
        guard !urls.isEmpty else { return }
        let files = Self.filterDroppedImageFiles(urls)
        easyLogger.info(
            "accept files: urls=\(urls.count, privacy: .public) first=\(urls.first?.lastPathComponent ?? "-", privacy: .public) images=\(files.count, privacy: .public) canRun=\(self.canRun, privacy: .public)"
        )
        guard !files.isEmpty else {
            resultMessage = L10n.string("e.unsupportedDrop", language: currentLanguage())
            return
        }
        runConversion(files: files)
    }

    /// 変換を実行する。ファイル単位で並列に処理し、進捗を更新する。
    func runConversion(files: [URL]) {
        guard canRun && !files.isEmpty else { return }
        runTask?.cancel()
        runTask = Task {
            await execute(files: files)
        }
    }

    private func execute(files: [URL]) async {
        isRunning = true
        progressPercent = 0
        successCount = 0
        failureCount = 0
        resultMessage = ""
        lastRunSucceeded = nil
        completedCount = 0
        totalCount = files.count
        easyLogger.info("run start: files=\(files.count, privacy: .public) output=\(self.outputFolderPath, privacy: .public)")
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
        let (success, failure) = await orchestrator.run(
            files: files, config: config, outputDirectory: outputURL, paths: paths
        ) { [weak self] outcome in
            guard let self else { return }
            await MainActor.run {
                self.apply(outcome)
            }
        }
        successCount = success
        failureCount = failure
        progressPercent = 100
        let allSuccess = failure == 0 && success > 0
        lastRunSucceeded = allSuccess
        if success > 0 && failure == 0 {
            resultMessage = String(format: L10n.string("c.done.success", language: currentLanguage()), success)
        } else {
            resultMessage = String(format: L10n.string("c.done.mixed", language: currentLanguage()), success, failure)
        }
        easyLogger.info("run finish: success=\(success, privacy: .public) failure=\(failure, privacy: .public)")
        await playCompletionSound(allSuccess: allSuccess)
        isRunning = false
    }

    private func apply(_ outcome: FileOutcome) {
        guard totalCount > 0 else { return }
        if outcome.fileDone {
            completedCount += 1
            progressPercent = Double(completedCount) / Double(totalCount) * 100
        }
    }

    private func currentLanguage() -> String {
        (try? store.load(maxParallel: Int(maxParallel)).settings.language) ?? ""
    }

    private func playCompletionSound(allSuccess: Bool) async {
        let settings: ScreenSettings
        do {
            settings = try store.load(maxParallel: Int(maxParallel)).settings
        } catch {
            return
        }
        guard settings.playSound else { return }
        let name = allSuccess ? settings.successSound : settings.errorSound
        let options = soundService.listSounds(success: allSuccess)
        let resolved = soundService.resolveSelected(name, options: options)
        if let option = options.first(where: { $0.name == resolved }),
           let player = soundService.makePlayer(for: option) {
            audioPlayer = player
            player.play()
        }
    }
}
