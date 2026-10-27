import Foundation

/// 一括変換画面の設定。`settings.json` の `batchConvert` セクションに対応する。
struct BatchSettings: Codable, Equatable {
    var targetFilter: String
    var scale: Int
    var model: String
    var format: String
    var optimizeType: String
    var quality: Int
    var parallelCount: Int
    var inputFolderPath: String?
    var outputFolderPath: String?

    static func defaults(maxParallel: Int) -> BatchSettings {
        BatchSettings(
            targetFilter: TargetFilter.sevenDays.rawValue,
            scale: 2,
            model: "realesr-animevideov3-x4",
            format: OutputFormat.jpegXL.rawValue,
            optimizeType: OptimizeType.anime.rawValue,
            quality: 80,
            parallelCount: max(1, maxParallel / 2 - 1),
            inputFolderPath: nil,
            outputFolderPath: nil
        )
    }
}

/// かんたん変換画面の設定。`settings.json` の `easyConvert` セクションに対応する。
/// 一括画面とは独立に保存する。並列数は画面に出さず保存値を使う。
struct EasyConvertSettings: Codable, Equatable {
    var scale: Int
    var model: String
    var format: String
    var optimizeType: String
    var quality: Int
    var parallelCount: Int
    var outputFolderPath: String?

    static func defaults(maxParallel: Int) -> EasyConvertSettings {
        EasyConvertSettings(
            scale: 2,
            model: "realesr-animevideov3-x4",
            format: OutputFormat.jpegXL.rawValue,
            optimizeType: OptimizeType.anime.rawValue,
            quality: 80,
            parallelCount: max(1, maxParallel / 2 - 1),
            outputFolderPath: nil
        )
    }
}

/// 設定画面の設定。`settings.json` の `settings` セクションに対応する。
struct ScreenSettings: Codable, Equatable {
    var showOsNotification: Bool
    var playSound: Bool
    var successSound: String
    var errorSound: String
    /// 成功時サウンドをランダム再生するか (checkbox label: ランダム).
    var successSoundRandom: Bool = false
    /// 失敗時サウンドをランダム再生するか (checkbox label: ランダム).
    var errorSoundRandom: Bool = false
    var language: String
    var appearance: String
    var fontSize: String
    var wallpaper: String
    var wallpaperOpacity: Double
    var wallpaperBackgroundColor: String
    /// 壁紙をランダムにシャッフルするかどうか (checkbox label: ランダム).
    var wallpaperRandom: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var wallpaperShuffle: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var wallpaperShuffleEnabled: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var randomWallpaper: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var shuffleWallpaper: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var shuffleEnabled: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var isRandom: Bool = false
    /// `wallpaperRandom` の別名 (互換用).
    var isShuffle: Bool = false

    /// シャッフル間隔 (分). 1/5/15/30/60/240/720/1440 のいずれか.
    var wallpaperShuffleInterval: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var wallpaperShuffleMinutes: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var wallpaperRandomInterval: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var shuffleInterval: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var shuffleMinutes: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var wallpaperShuffleTime: Int = 1
    /// `wallpaperShuffleInterval` の別名 (互換用).
    var wallpaperShuffleIntervalMinutes: Int = 1

    static func defaults() -> ScreenSettings {
        ScreenSettings(
            showOsNotification: false,
            playSound: false,
            successSound: "assets/sounds/success/decision49.mp3",
            errorSound: "assets/sounds/error/beep1.mp3",
            successSoundRandom: false,
            errorSoundRandom: false,
            language: "",
            appearance: AppearanceMode.auto.rawValue,
            fontSize: FontSizeOption.standard.rawValue,
            wallpaper: WallpaperSelection.noneName,
            wallpaperOpacity: 1.0,
            wallpaperBackgroundColor: "#1E1E1E",
            wallpaperRandom: false,
            wallpaperShuffle: false,
            wallpaperShuffleEnabled: false,
            randomWallpaper: false,
            shuffleWallpaper: false,
            shuffleEnabled: false,
            isRandom: false,
            isShuffle: false,
            wallpaperShuffleInterval: 1,
            wallpaperShuffleMinutes: 1,
            wallpaperRandomInterval: 1,
            shuffleInterval: 1,
            shuffleMinutes: 1,
            wallpaperShuffleTime: 1,
            wallpaperShuffleIntervalMinutes: 1
        )
    }
}

struct AppSettingsFile: Codable, Equatable {
    var settings: ScreenSettings
    var batch: BatchSettings
    var easy: EasyConvertSettings

    enum CodingKeys: String, CodingKey {
        case settings
        case batch = "batchConvert"
        case easy = "easyConvert"
    }
}

/// `settings.json` の読み書き。書き込みはロックで直列化する。
final class SettingsStore: Sendable {
    let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    convenience init(paths: AppPaths) {
        self.init(fileURL: paths.settingsFileURL)
    }

    /// 読み込む。無い・壊れている場合は初期値を保存して返す。
    /// 不正値は補正し、補正時はファイルを書き換える。
    /// 旧形式の `convert` / `batch` キーは `batchConvert` へ、
    /// `easy` キーは `easyConvert` へ移行し、新形式で書き換える。
    func load(maxParallel: Int) throws -> AppSettingsFile {
        lock.lock()
        defer { lock.unlock() }
        let defaults = AppSettingsFile(
            settings: .defaults(),
            batch: .defaults(maxParallel: maxParallel),
            easy: .defaults(maxParallel: maxParallel)
        )
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try writeLocked(defaults)
            return defaults
        }
        guard
            let data = try? Data(contentsOf: fileURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            try writeLocked(defaults)
            return defaults
        }
        var needsRewrite = false
        let settings = resolveScreen(json["settings"], defaults: defaults.settings, mark: { needsRewrite = true })
        if json["batchConvert"] == nil { needsRewrite = true }
        let batch = resolveBatch(
            json["batchConvert"] ?? json["batch"] ?? json["convert"],
            defaults: defaults.batch,
            maxParallel: maxParallel,
            mark: { needsRewrite = true }
        )
        if json["easyConvert"] == nil { needsRewrite = true }
        let easy = resolveEasy(
            json["easyConvert"] ?? json["easy"],
            defaults: defaults.easy,
            maxParallel: maxParallel,
            mark: { needsRewrite = true }
        )
        let resolved = AppSettingsFile(settings: settings, batch: batch, easy: easy)
        if needsRewrite {
            try writeLocked(resolved)
        }
        return resolved
    }

    func save(_ file: AppSettingsFile) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeLocked(file)
    }

    private func writeLocked(_ file: AppSettingsFile) throws {
        let encoder = JSONEncoder()
        // キー順を固定し、人間が読める形式で保存する。同じ内容は常に同一バイト列になる。
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Resolve

    func resolveScreen(
        _ value: Any?,
        defaults: ScreenSettings,
        mark: () -> Void
    ) -> ScreenSettings {
        guard let json = value as? [String: Any] else {
            mark()
            return defaults
        }
        // シャッフル関連の間隔は複数のキー名を許容し、最初に見つかった値を採用する。
        let shuffleBool = wallpaperShuffleBoolValue(json, defaults: defaults, mark: mark)
        let shuffleIntervalRaw =
            json["wallpaperShuffleInterval"] ?? json["wallpaperShuffleMinutes"]
            ?? json["wallpaperRandomInterval"] ?? json["shuffleInterval"]
            ?? json["shuffleMinutes"] ?? json["wallpaperShuffleTime"]
            ?? json["wallpaperShuffleIntervalMinutes"]
        let shuffleInterval = intValue(
            shuffleIntervalRaw, min: 1, max: 1440, fallback: defaults.wallpaperShuffleInterval,
            mark: mark)
        return ScreenSettings(
            showOsNotification: boolValue(
                json["showOsNotification"], fallback: defaults.showOsNotification, mark: mark),
            playSound: boolValue(json["playSound"], fallback: defaults.playSound, mark: mark),
            successSound: stringValue(json["successSound"], fallback: defaults.successSound, mark: mark),
            errorSound: stringValue(json["errorSound"], fallback: defaults.errorSound, mark: mark),
            successSoundRandom: boolValue(
                json["successSoundRandom"], fallback: defaults.successSoundRandom, mark: mark),
            errorSoundRandom: boolValue(
                json["errorSoundRandom"], fallback: defaults.errorSoundRandom, mark: mark),
            language: languageValue(json["language"], fallback: defaults.language, mark: mark),
            appearance: appearanceValue(json["appearance"], fallback: defaults.appearance, mark: mark),
            fontSize: fontSizeValue(json["fontSize"], fallback: defaults.fontSize, mark: mark),
            wallpaper: stringValue(json["wallpaper"], fallback: defaults.wallpaper, mark: mark),
            wallpaperOpacity: doubleValue(
                json["wallpaperOpacity"], min: 0, max: 1, fallback: defaults.wallpaperOpacity, mark: mark),
            wallpaperBackgroundColor: colorValue(
                json["wallpaperBackgroundColor"], fallback: defaults.wallpaperBackgroundColor, mark: mark),
            wallpaperRandom: shuffleBool,
            wallpaperShuffle: shuffleBool,
            wallpaperShuffleEnabled: shuffleBool,
            randomWallpaper: shuffleBool,
            shuffleWallpaper: shuffleBool,
            shuffleEnabled: shuffleBool,
            isRandom: shuffleBool,
            isShuffle: shuffleBool,
            wallpaperShuffleInterval: shuffleInterval,
            wallpaperShuffleMinutes: shuffleInterval,
            wallpaperRandomInterval: shuffleInterval,
            shuffleInterval: shuffleInterval,
            shuffleMinutes: shuffleInterval,
            wallpaperShuffleTime: shuffleInterval,
            wallpaperShuffleIntervalMinutes: shuffleInterval
        )
    }

    /// 壁紙シャッフルの真偽値。複数のキー名を許容し、最初に見つかった値を採用する。
    /// デフォルト名だけでなく旧/別名からの値も統合するため、すべて同じ値に揃える。
    private func wallpaperShuffleBoolValue(
        _ json: [String: Any], defaults: ScreenSettings, mark: () -> Void
    ) -> Bool {
        boolValue(
            json["wallpaperRandom"] ?? json["wallpaperShuffle"] ?? json["randomWallpaper"]
                ?? json["shuffleWallpaper"] ?? json["shuffleEnabled"] ?? json["wallpaperShuffleEnabled"]
                ?? json["isRandom"] ?? json["isShuffle"],
            fallback: defaults.wallpaperRandom, mark: mark)
    }

    func resolveBatch(
        _ value: Any?,
        defaults: BatchSettings,
        maxParallel: Int,
        mark: () -> Void
    ) -> BatchSettings {
        guard let json = value as? [String: Any] else {
            mark()
            return defaults
        }
        let targetFilter: String
        if let raw = json["targetFilter"] as? String, TargetFilter(rawValue: raw) != nil {
            targetFilter = raw
        } else {
            mark()
            targetFilter = defaults.targetFilter
        }
        return BatchSettings(
            targetFilter: targetFilter,
            scale: intValue(json["scale"], min: 1, max: 4, fallback: defaults.scale, mark: mark),
            model: stringValue(json["model"], fallback: defaults.model, mark: mark),
            format: validatedFormat(json["format"], fallback: defaults.format, mark: mark),
            optimizeType: validatedOptimizeType(json["optimizeType"], fallback: defaults.optimizeType, mark: mark),
            quality: intValue(json["quality"], min: 1, max: 100, fallback: defaults.quality, mark: mark),
            parallelCount: intValue(
                json["parallelCount"], min: 1, max: maxParallel, fallback: defaults.parallelCount, mark: mark),
            inputFolderPath: optionalPath(json["inputFolderPath"]),
            outputFolderPath: optionalPath(json["outputFolderPath"])
        )
    }

    func resolveEasy(
        _ value: Any?,
        defaults: EasyConvertSettings,
        maxParallel: Int,
        mark: () -> Void
    ) -> EasyConvertSettings {
        guard let json = value as? [String: Any] else {
            mark()
            return defaults
        }
        return EasyConvertSettings(
            scale: intValue(json["scale"], min: 1, max: 4, fallback: defaults.scale, mark: mark),
            model: stringValue(json["model"], fallback: defaults.model, mark: mark),
            format: validatedFormat(json["format"], fallback: defaults.format, mark: mark),
            optimizeType: validatedOptimizeType(json["optimizeType"], fallback: defaults.optimizeType, mark: mark),
            quality: intValue(json["quality"], min: 1, max: 100, fallback: defaults.quality, mark: mark),
            parallelCount: intValue(
                json["parallelCount"], min: 1, max: maxParallel, fallback: defaults.parallelCount, mark: mark),
            outputFolderPath: optionalPath(json["outputFolderPath"])
        )
    }

    private func validatedFormat(_ value: Any?, fallback: String, mark: () -> Void) -> String {
        if let raw = value as? String, OutputFormat(rawValue: raw) != nil { return raw }
        mark()
        return fallback
    }

    private func validatedOptimizeType(_ value: Any?, fallback: String, mark: () -> Void) -> String {
        if let raw = value as? String, OptimizeType(rawValue: raw) != nil { return raw }
        mark()
        return fallback
    }
}
