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
    /// 固定最適化 / 自動最適化（ADR 0049）。
    var mode: String = ConvertMode.fixed.rawValue
    /// 自動モードのコンテンツ種別。
    var contentType: String = ContentType.anime.rawValue
    /// 自動モードの目標解像度。
    var targetSize: String = TargetSize.fiveK.rawValue
    /// 自動モードの画質プリセット。
    var qualityPreset: String = QualityPreset.high.rawValue
    /// アップスケーラーのエンジン。`upscayl` / `realCUGAN`。
    var engine: String = UpscaleEngine.upscayl.rawValue
    /// Real-CUGANのモデルID。`models-se/up2x-conservative` 形式。
    var realCuganModel: String = "models-se/up2x-conservative"
    /// 実行結果の表の絞り込み（待機中）。次回起動時に選択状態を復元する。
    var showWaiting: Bool = true
    /// 実行結果の表の絞り込み（実行中）。
    var showRunning: Bool = true
    /// 実行結果の表の絞り込み（成功）。
    var showSuccess: Bool = true
    /// 実行結果の表の絞り込み（失敗）。
    var showFailure: Bool = true
    /// 実行結果の表の絞り込み（キャンセル）。ADR 0054 で追加。
    var showCancelled: Bool = true
    /// モードの特徴コールアウトの展開状態。固定・自動で共用する。
    var modeNoteExpanded: Bool = true
    /// 対応フォーマットコールアウトの展開状態。次回起動時に復元する。
    var formatsExpanded: Bool = true

    static func defaults(maxParallel: Int) -> BatchSettings {
        BatchSettings(
            targetFilter: TargetFilter.sevenDays.rawValue,
            scale: 2,
            model: "realesr-animevideov3-x4",
            format: OutputFormat.jpegXL.rawValue,
            optimizeType: OptimizeType.anime.rawValue,
            quality: 80,
            parallelCount: HardwareInfo.defaultParallelCount(maxParallel: maxParallel),
            inputFolderPath: nil,
            outputFolderPath: nil,
            mode: ConvertMode.fixed.rawValue,
            contentType: ContentType.anime.rawValue,
            targetSize: TargetSize.fiveK.rawValue,
            qualityPreset: QualityPreset.high.rawValue,
            engine: UpscaleEngine.upscayl.rawValue,
            realCuganModel: "models-se/up2x-conservative",
            showWaiting: true,
            showRunning: true,
            showSuccess: true,
            showFailure: true,
            showCancelled: true,
            modeNoteExpanded: true,
            formatsExpanded: true
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
    /// アップスケーラーのエンジン。`upscayl` / `realCUGAN`。
    var engine: String = UpscaleEngine.upscayl.rawValue
    /// Real-CUGANのモデルID。`models-se/up2x-conservative` 形式。
    var realCuganModel: String = "models-se/up2x-conservative"

    static func defaults(maxParallel: Int) -> EasyConvertSettings {
        EasyConvertSettings(
            scale: 2,
            model: "realesr-animevideov3-x4",
            format: OutputFormat.jpegXL.rawValue,
            optimizeType: OptimizeType.anime.rawValue,
            quality: 80,
            parallelCount: HardwareInfo.defaultParallelCount(maxParallel: maxParallel),
            outputFolderPath: nil,
            engine: UpscaleEngine.upscayl.rawValue,
            realCuganModel: "models-se/up2x-conservative"
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
    /// 直近に読んだ（または書いた）内容と、その引数。
    /// Why not 保存のたびに `load()` し直すか: `load()` はファイル全体の読み込みと
    /// 値の補正を行い、補正があれば書き戻しもする。入力欄やスライダーの操作ごとに
    /// 呼ぶと1文字・1ステップごとにディスクI/Oが発生するため、同じ条件の結果を
    /// 使い回す（差分保存の基点にもなる）。
    private struct Cached {
        var maxParallel: Int
        var file: AppSettingsFile
        /// 読み込み・書き込み時点のファイル更新日時。
        /// Why not 時刻ではなく内容のハッシュで比較するか: 毎回の `load()` で
        /// ファイルを読む必要が生まれ、キャッシュの意味がなくなるため。
        var modifiedAt: Date?
    }
    /// 読み書きは `lock` で直列化するため、検査器にはunsafeと宣言して
    /// `Sendable` を保つ。Why not `@unchecked` を外すか: 呼び出し側はactor境界を
    /// またいでこのstoreを渡しており、不適合にすると多数の呼び出し箇所が壊れる。
    /// Why not actor化するか: `load` / `save` は同期的に使われており、
    /// 全面な非同期化はViewModel全体へ波及するため別の変更として扱う。
    private nonisolated(unsafe) var cached: Cached?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    convenience init(paths: AppPaths) {
        self.init(fileURL: paths.settingsFileURL)
    }

    /// 前回と同じ条件で、かつファイルが外部から書き換えられていなければ、
    /// キャッシュした内容をそのまま返す。ディスクI/Oと値の補正を省く。
    /// Why not 無条件でキャッシュを返すか: 設定画面など別の画面（別インスタンス）や
    /// 外部の書き換えを取りこぼすと、古い値へ上書きして変更を消してしまうため。
    private func currentCached(maxParallel: Int) -> AppSettingsFile? {
        guard let cached, cached.maxParallel == maxParallel else { return nil }
        let modifiedAt = Self.modificationDate(atPath: fileURL.path)
        // 更新日時が取れない環境（ファイルが無い等）では安全側に倒して読み直す。
        guard let modifiedAt, let recorded = cached.modifiedAt else { return nil }
        // 更新日時が記録より後なら、他画面・他プロセスが書き換えたと判断して読み直す。
        // Why not 内容のハッシュで比較するか: 毎回ファイルを読む必要が生まれ、
        // キャッシュの意味がなくなるため。更新日時はディスクI/Oなしに取れる。
        guard modifiedAt <= recorded else { return nil }
        return cached.file
    }

    private static func modificationDate(atPath path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    /// 読み込む。無い・壊れている場合は初期値を保存して返す。
    /// 不正値は補正し、補正時はファイルを書き換える。
    /// 旧形式の `convert` / `batch` キーは `batchConvert` へ、
    /// `easy` キーは `easyConvert` へ移行し、新形式で書き換える。
    func load(maxParallel: Int) throws -> AppSettingsFile {
        lock.lock()
        defer { lock.unlock() }
        if let cached = currentCached(maxParallel: maxParallel) {
            return cached
        }
        let resolved = try loadUncached(maxParallel: maxParallel)
        rememberLocked(resolved, maxParallel: maxParallel)
        return resolved
    }

    /// キャッシュを使わずに読み込む。呼び出し側でロックを保持していること。
    private func loadUncached(maxParallel: Int) throws -> AppSettingsFile {
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
        rememberLocked(file, maxParallel: cached?.maxParallel ?? 0)
    }

    /// `settings.json` の一部だけを書き換える。現在の内容は `load()` と同じ条件で
    /// 取得するため、呼び出し側が `load()` を先に呼ぶ必要がない。
    /// Why not `load()` と `save()` を呼び出し側で組み合わせるか: 2回の間に別の画面が
    /// 書き換えると古い内容で全体を上書きしてしまう。更新はこの中で直列化する。
    /// - Parameter maxParallel: `load()` と同じ補正条件。値の範囲補正に使う。
    /// - Returns: 書き込んだ内容。失敗した場合はnil。
    @discardableResult
    func update(
        maxParallel: Int,
        mutate: (inout AppSettingsFile) -> Void
    ) -> AppSettingsFile? {
        lock.lock()
        defer { lock.unlock() }
        guard var file = try? loadUncached(maxParallel: maxParallel) else { return nil }
        mutate(&file)
        guard (try? writeLocked(file)) != nil else { return nil }
        rememberLocked(file, maxParallel: maxParallel)
        return file
    }

    /// セクション単位の差分更新。`update` へ渡すクロージャを組み立てるだけの糖衣。
    /// Why not セクションごとに専用メソッドを増やすか: 設定型が増えるたびに
    /// ほぼ同じ並びのメソッドが増え、変更点が散らばるため。
    @discardableResult
    func updateBatch(
        maxParallel: Int, mutate: (inout BatchSettings) -> Void
    ) -> BatchSettings? {
        update(maxParallel: maxParallel) { file in
            mutate(&file.batch)
        }.map(\.batch)
    }

    /// `easyConvert` セクションの差分更新。`updateBatch` と対になる。
    @discardableResult
    func updateEasy(
        maxParallel: Int, mutate: (inout EasyConvertSettings) -> Void
    ) -> EasyConvertSettings? {
        update(maxParallel: maxParallel) { file in
            mutate(&file.easy)
        }.map(\.easy)
    }

    private func rememberLocked(_ file: AppSettingsFile, maxParallel: Int) {
        cached = Cached(
            maxParallel: maxParallel, file: file, modifiedAt: Self.modificationDate(atPath: fileURL.path))
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
}
