import AVFoundation
import Foundation

/// かんたん変換の実行状態を保持する共有ジョブ層。
/// 画面（`EasyConvertView` / `EasyConvertViewModel`）ではなくアプリ層で所有し、
/// サイドナビ切替でViewが再生成されても進捗・結果を維持するために使う。
/// 実処理は `ConvertOrchestrator`（Service）に委譲する。
@Observable
@MainActor
final class EasyConvertJobStore {
    var isRunning: Bool = false
    var progressPercent: Double = 0
    var successCount: Int = 0
    var failureCount: Int = 0
    var resultMessage: String = ""
    /// 直近の変換結果。nil=未実行、true=全件成功、false=1件でも失敗。ドロップエリアの枠色に使う。
    var lastRunSucceeded: Bool?

    private var completedCount: Int = 0
    private var totalCount: Int = 0
    private var runTask: Task<Void, Never>?

    private let paths: AppPaths
    private let store: SettingsStore
    private let orchestrator: ConvertOrchestrator
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
        resultMessage = ""
        lastRunSucceeded = nil
        completedCount = 0
        totalCount = files.count
        easyLogger.info("run start: files=\(files.count, privacy: .public)")
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
        (try? store.load(maxParallel: maxParallel).settings.language) ?? ""
    }

    private func playCompletionSound(allSuccess: Bool) async {
        let settings: ScreenSettings
        do {
            settings = try store.load(maxParallel: maxParallel).settings
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
