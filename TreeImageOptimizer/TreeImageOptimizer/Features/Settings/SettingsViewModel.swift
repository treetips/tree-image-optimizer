import AppKit
import AVFoundation
import Foundation

/// 設定画面の状態と保存。`settings.json` への永続化・一覧取得を配線する。
@Observable
@MainActor
final class SettingsViewModel {
    var showOsNotification: Bool = false {
        didSet { save() }
    }
    var playSound: Bool = false {
        didSet { save() }
    }
    var successSound: String = "decision49.mp3" {
        didSet { save() }
    }
    var errorSound: String = "beep1.mp3" {
        didSet { save() }
    }
    var successSounds: [SoundOption] = []
    var errorSounds: [SoundOption] = []
    var language: String = "" {
        didSet { save() }
    }
    var appearance: String = AppearanceMode.auto.rawValue {
        didSet { save() }
    }
    var fontSize: String = FontSizeOption.standard.rawValue {
        didSet { save() }
    }
    var wallpaper: String = WallpaperSelection.noneName {
        didSet { save() }
    }
    var wallpapers: [WallpaperOption] = []
    var wallpaperOpacity: Double = 1.0 {
        didSet { save() }
    }
    var wallpaperBackgroundColorHex: String = "#1E1E1E" {
        didSet { save() }
    }

    /// 外観モード別の背景色初期値。macOS標準のウインドウ背景色とする。
    /// ライト=#FFFFFF、ダーク=#1E1E1E、自動=システムに従う。
    nonisolated static func defaultWallpaperBackgroundColorHex(for appearance: String) -> String {
        switch appearance {
        case AppearanceMode.light.rawValue:
            return "#FFFFFF"
        case AppearanceMode.dark.rawValue:
            return "#1E1E1E"
        default:
            return systemWallpaperBackgroundColorHex()
        }
    }

    /// 自動用の初期値。システム設定に従う。
    /// `NSApp.effectiveAppearance` はアプリ側の上書きを反映してしまうため、
    /// システム設定そのもの（`AppleInterfaceStyle`）で判定する。
    nonisolated static func systemWallpaperBackgroundColorHex() -> String {
        systemIsDark() ? "#1E1E1E" : "#FFFFFF"
    }

    /// システム設定の外観名。View側の配色解決・診断ログ用。
    nonisolated static func systemAppearanceName() -> String? {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
    }

    /// システム設定がダークモードかどうか。
    nonisolated static func systemIsDark() -> Bool {
        (systemAppearanceName() ?? "").lowercased() == "dark"
    }

    /// 外観モードが自動の場合、システム設定に合わせて背景色を更新する。
    /// macOSの設定変更に追従するために呼ぶ。
    func refreshAutoBackgroundColor() {
        guard appearance == AppearanceMode.auto.rawValue else { return }
        wallpaperBackgroundColorHex = Self.systemWallpaperBackgroundColorHex()
    }

    /// 外観モードを変更する。ユーザー設定の背景色をリセットし、
    /// モード別の背景色初期値を設定する。
    func setAppearance(_ value: String) {
        appearance = value
        wallpaperBackgroundColorHex = Self.defaultWallpaperBackgroundColorHex(for: value)
    }

    /// 実表示に使う背景色。自動モードでは保存値ではなく常にシステム値を使う。
    /// 保存値が古いダーク値のままライト環境で表示される不整合を防ぐ。
    var effectiveWallpaperBackgroundColorHex: String {
        if appearance == AppearanceMode.auto.rawValue {
            return Self.systemWallpaperBackgroundColorHex()
        }
        return wallpaperBackgroundColorHex
    }

    /// 背景色を初期値に戻す。
    func resetWallpaperBackgroundColor() {
        wallpaperBackgroundColorHex = Self.defaultWallpaperBackgroundColorHex(for: appearance)
    }

    /// 表示言語から適用するロケール。空文字は環境に従う。
    var effectiveLocale: Locale {
        switch language {
        case "ja-JP": return Locale(identifier: "ja_JP")
        case "en-US": return Locale(identifier: "en_US")
        default: return Locale.autoupdatingCurrent
        }
    }

    private let store: SettingsStore
    private let soundService: SoundService
    private let wallpaperService: WallpaperService
    private let notificationService: NotificationService
    private var audioPlayer: AVAudioPlayer?

    init(store: SettingsStore? = nil, soundService: SoundService? = nil, wallpaperService: WallpaperService? = nil, notificationService: NotificationService? = nil) {
        let paths = AppPaths()
        self.store = store ?? SettingsStore(paths: paths)
        self.soundService = soundService ?? SoundService(paths: paths)
        self.wallpaperService = wallpaperService ?? WallpaperService(paths: paths)
        self.notificationService = notificationService ?? NotificationService()
        load()
    }

    /// 起動時に完了通知の許可を求める。拒否時は通知なしになる。
    nonisolated func requestNotificationAuthorization() {
        let service = notificationService
        Task {
            _ = await service.requestAuthorization()
        }
    }

    private func load() {
        guard let file = try? store.load(maxParallel: ProcessInfo.processInfo.processorCount) else { return }
        let s = file.settings
        showOsNotification = s.showOsNotification
        playSound = s.playSound
        language = s.language
        appearance = s.appearance
        fontSize = s.fontSize
        wallpaperOpacity = s.wallpaperOpacity
        wallpaperBackgroundColorHex = s.wallpaperBackgroundColor
        successSounds = soundService.listSounds(success: true).map {
            SoundOption(name: $0.name, isBundled: $0.isBundled)
        }
        errorSounds = soundService.listSounds(success: false).map {
            SoundOption(name: $0.name, isBundled: $0.isBundled)
        }
        successSound = soundService.resolveSelected(
            s.successSound, options: soundService.listSounds(success: true)
        )
        errorSound = soundService.resolveSelected(
            s.errorSound, options: soundService.listSounds(success: false)
        )
        // プルダウン先頭に「背景無し」を追加する。
        wallpapers = [WallpaperOption(name: WallpaperSelection.noneName, isBundled: false)]
            + wallpaperService.listWallpapers()
        wallpaper = wallpaperService.resolveSelected(s.wallpaper, options: wallpapers)
        // 保存値が一覧に無い場合の解決で「背景無し」が選ばれることはないため、
        // 不正値はサービス側フォールバックに任せる。
    }

    private func save() {
        guard let file = try? store.load(maxParallel: ProcessInfo.processInfo.processorCount) else { return }
        var updated = file
        updated.settings.showOsNotification = showOsNotification
        updated.settings.playSound = playSound
        updated.settings.successSound = successSound
        updated.settings.errorSound = errorSound
        updated.settings.language = language
        updated.settings.appearance = appearance
        updated.settings.fontSize = fontSize
        updated.settings.wallpaper = wallpaper
        updated.settings.wallpaperOpacity = wallpaperOpacity
        updated.settings.wallpaperBackgroundColor = wallpaperBackgroundColorHex
        try? store.save(updated)
    }

    /// 表示用の壁紙URLを解決する。「背景無し」選択時はnilを返す。
    func wallpaperFileURL() -> URL? {
        if wallpaper == WallpaperSelection.noneName { return nil }
        return wallpaperService.fileURL(for: wallpaper)
    }

    /// Hex入力を検証し、正常値なら反映してtrueを返す。不正値なら保存せずfalseを返す。
    func commitBackgroundHex(_ draft: String) -> Bool {
        guard SettingsStore.isValidColor(draft) else { return false }
        wallpaperBackgroundColorHex = draft
        return true
    }

    func playSuccessSound() {
        play(name: successSound, success: true)
    }

    func playErrorSound() {
        play(name: errorSound, success: false)
    }

    private func play(name: String, success: Bool) {
        let options = soundService.listSounds(success: success)
        guard let option = options.first(where: { $0.name == name }),
              let player = soundService.makePlayer(for: option)
        else { return }
        audioPlayer = player
        player.play()
    }
}
