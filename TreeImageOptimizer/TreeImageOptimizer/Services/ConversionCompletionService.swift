import AVFoundation
import Foundation

/// 変換完了時のOS通知とサウンド再生。
/// 一括変換とかんたん変換で同じ設定・同じ再生経路を使う。
@MainActor
final class ConversionCompletionService {
    private let store: SettingsStore
    private let notificationService: NotificationService
    private let soundService: SoundService
    private let maxParallel: Int
    /// 再生中にプレイヤーが破棄されないよう保持する。
    private var audioPlayer: AVAudioPlayer?

    init(
        paths: AppPaths,
        store: SettingsStore,
        soundService: SoundService? = nil,
        maxParallel: Int
    ) {
        self.store = store
        self.notificationService = NotificationService()
        self.soundService = soundService ?? SoundService(paths: paths)
        self.maxParallel = max(1, maxParallel)
    }

    /// 完了時の通知とサウンド。`notify` がfalseの画面（かんたん変換）はサウンドだけ再生する。
    func complete(allSuccess: Bool, language: String, notify: Bool) async {
        let settings: ScreenSettings
        do {
            settings = try store.load(maxParallel: maxParallel).settings
        } catch {
            return
        }
        if notify, settings.showOsNotification {
            let body = L10n.string(
                allSuccess ? "notify.success" : "notify.failure", language: language)
            await notificationService.notify(body: body)
        }
        guard settings.playSound,
            let option = soundService.resolvePlaybackOption(
                success: allSuccess,
                name: allSuccess ? settings.successSound : settings.errorSound,
                random: allSuccess ? settings.successSoundRandom : settings.errorSoundRandom
            ),
            let player = soundService.makePlayer(for: option)
        else { return }
        audioPlayer = player
        player.play()
    }
}
