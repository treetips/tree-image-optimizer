import AVFoundation
import Foundation

/// 一括変換の実行状態を保持する共有ジョブ層。
/// 画面（`ConvertView` / `ConvertViewModel`）ではなくアプリ層で所有し、
/// サイドナビ切替でViewが再生成されても進捗・結果を維持するために使う。
/// 実処理は `ConvertOrchestrator`（Service）に委譲する。
@Observable
@MainActor
final class ConvertJobStore {
    var isRunning: Bool = false
    var progressPercent: Double = 0
    var successCount: Int = 0
    var failureCount: Int = 0
    var elapsedMinutes: Double = 0
    var rows: [FileRow] = []
    var resultMessage: String = ""

    private var completedCount: Int = 0
    private var runTask: Task<Void, Never>?

    private let paths: AppPaths
    private let store: SettingsStore
    private let orchestrator: ConvertOrchestrator
    private let notificationService = NotificationService()
    private var soundService: SoundService
    private var audioPlayer: AVAudioPlayer?
    private let maxParallel: Int

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
        self.maxParallel = max(1, ProcessInfo.processInfo.processorCount)
    }

    /// 変換を開始する。実行中は受け付けない。
    func start(files: [URL], config: ConvertConfig, outputDirectory: URL) {
        guard !isRunning else { return }
        guard !files.isEmpty else { return }
        runTask?.cancel()
        runTask = Task {
            await execute(files: files, config: config, outputDirectory: outputDirectory)
        }
    }

    private func execute(files: [URL], config: ConvertConfig, outputDirectory: URL) async {
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
        rows = files.map {
            FileRow(
                fileName: $0.lastPathComponent, upscale: .waiting, compress: .waiting,
                output: .waiting)
        }
        let (success, failure) = await orchestrator.run(
            files: files, config: config, outputDirectory: outputDirectory, paths: paths
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
        let language = (try? store.load(maxParallel: maxParallel).settings.language) ?? ""
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
            settings = try store.load(maxParallel: maxParallel).settings
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
