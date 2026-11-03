import Foundation

/// `SettingsStore` が読んだJSONを各設定型へ解決する。
/// クラス本体の行数制限（file_length）を守るためextensionに分離する。
/// `SettingsStoreValues.swift` の値検証ヘルパーを使う。
extension SettingsStore {
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
            outputFolderPath: optionalPath(json["outputFolderPath"]),
            engine: validatedEngine(json["engine"], fallback: defaults.engine, mark: mark),
            realCuganModel: realCuganModelValue(
                json["realCuganModel"], fallback: defaults.realCuganModel, mark: mark),
            showWaiting: boolValue(json["showWaiting"], fallback: defaults.showWaiting, mark: mark),
            showRunning: boolValue(json["showRunning"], fallback: defaults.showRunning, mark: mark),
            showSuccess: boolValue(json["showSuccess"], fallback: defaults.showSuccess, mark: mark),
            showFailure: boolValue(json["showFailure"], fallback: defaults.showFailure, mark: mark)
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
            outputFolderPath: optionalPath(json["outputFolderPath"]),
            engine: validatedEngine(json["engine"], fallback: defaults.engine, mark: mark),
            realCuganModel: realCuganModelValue(
                json["realCuganModel"], fallback: defaults.realCuganModel, mark: mark)
        )
    }

    /// エンジン名の検証。既知の `UpscaleEngine` のみ許容し、それ以外は既定へ戻す。
    private func validatedEngine(_ value: Any?, fallback: String, mark: () -> Void) -> String {
        if let raw = value as? String, UpscaleEngine(rawValue: raw) != nil { return raw }
        mark()
        return fallback
    }

    /// Real-CUGANモデルIDの検証。`models-{se,pro,nose}/up{2..4}x-...` 形式のみ許容する。
    private func realCuganModelValue(_ value: Any?, fallback: String, mark: () -> Void) -> String {
        if let raw = value as? String, RealCUGANModel.parse(raw) != nil { return raw }
        mark()
        return fallback
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
