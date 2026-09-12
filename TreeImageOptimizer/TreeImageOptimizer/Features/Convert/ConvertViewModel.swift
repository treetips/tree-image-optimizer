import AVFoundation
import Foundation

/// 変換画面の状態と処理。設定の永続化・モデル一覧・変換実行を配線する。
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
    var isRunning: Bool = false
    var progressPercent: Double = 0
    var successCount: Int = 0
    var failureCount: Int = 0
    var elapsedMinutes: Double = 0
    var rows: [FileRow] = []
    private var completedCount: Int = 0
    var showWaiting: Bool = true
    var showRunning: Bool = true
    var showSuccess: Bool = true
    var showFailure: Bool = true
    var resultMessage: String = ""

    /// 絞り込み後の表示行。いずれか1つでもチェックした状態を含む行を表示する。
    var filteredRows: [FileRow] {
        rows.filter { row in
            let statuses = [row.upscale, row.compress, row.output]
            if showWaiting, statuses.contains(.waiting) { return true }
            if showRunning, statuses.contains(.running) { return true }
            if showSuccess, statuses.contains(.success) { return true }
            if showFailure, statuses.contains(.failure) { return true }
            return false
        }
    }

    /// 実行ボタンの活性条件。
    var canRun: Bool {
        !isRunning
            && !inputFolderPath.isEmpty
            && !outputFolderPath.isEmpty
            && !inputFolderHasError
            && !outputFolderHasError
    }

    private let paths: AppPaths
    private let store: SettingsStore
    private let orchestrator: ConvertOrchestrator
    private let notificationService = NotificationService()
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

    /// 変換を実行する。ファイル単位で並列に処理し、進捗を更新する。
    func runConversion() {
        guard canRun else { return }
        runTask?.cancel()
        runTask = Task {
            await execute()
        }
    }

    private func execute() async {
        isRunning = true
        progressPercent = 0
        successCount = 0
        failureCount = 0
        elapsedMinutes = 0
        rows = []
        completedCount = 0
        resultMessage = ""
        let started = Date()
        // 実行時間をリアルタイム表示するための更新ループ。
        let elapsedTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                self.elapsedMinutes = Date().timeIntervalSince(started) / 60.0
            }
        }
        defer {
            elapsedTask.cancel()
            isRunning = false
            elapsedMinutes = Date().timeIntervalSince(started) / 60.0
        }
        let inputURL = URL(fileURLWithPath: inputFolderPath, isDirectory: true)
        let outputURL = URL(fileURLWithPath: outputFolderPath, isDirectory: true)
        let files: [URL]
        do {
            files = try TargetFiles.list(in: inputURL, modifiedWithinDays: TargetFiles.days(for: targetFilter))
        } catch {
            return
        }
        rows = files.map { FileRow(fileName: $0.lastPathComponent, upscale: .waiting, compress: .waiting, output: .waiting) }
        let config = ConvertConfig(
            scale: Int(scale),
            model: selectedModel,
            format: format,
            optimizeType: optimizeType,
            quality: Int(quality),
            parallelCount: Int(parallelCount)
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
        let language = (try? store.load(maxParallel: Int(maxParallel)).settings.language) ?? ""
        if allSuccess {
            resultMessage = String(format: L10n.string("c.done.success", language: language), success)
        } else {
            resultMessage = String(format: L10n.string("c.done.mixed", language: language), success, failure)
        }
        await finishNotification(allSuccess: allSuccess, language: language)
    }

    private func apply(_ outcome: FileOutcome) {
        guard rows.indices.contains(outcome.index) else { return }
        if outcome.started {
            switch outcome.stage {
            case .upscale:
                rows[outcome.index].upscale = .running
            case .compress:
                rows[outcome.index].compress = .running
            case .output:
                rows[outcome.index].output = .running
            }
            return
        }
        switch outcome.stage {
        case .upscale:
            rows[outcome.index].upscale = outcome.succeeded ? .success : .failure
        case .compress:
            rows[outcome.index].compress = outcome.succeeded ? .success : .failure
        case .output:
            rows[outcome.index].output = outcome.succeeded ? .success : .failure
        }
        // 件数は完了都度リアルタイムに集計する。
        if outcome.fileDone {
            completedCount += 1
            if outcome.succeeded {
                successCount += 1
            } else {
                failureCount += 1
            }
        }
        if !rows.isEmpty {
            progressPercent = Double(completedCount) / Double(rows.count) * 100
        }
    }

    private func finishNotification(allSuccess: Bool, language: String) async {
        let settings: ScreenSettings
        do {
            settings = try store.load(maxParallel: Int(maxParallel)).settings
        } catch {
            return
        }
        if settings.showOsNotification {
            let body = L10n.string(allSuccess ? "notify.success" : "notify.failure", language: language)
            await notificationService.notify(body: body)
        }
        if settings.playSound {
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
}
