import Foundation

// MARK: - Sidebar

/// 左サイドナビの選択肢。Finder風UIのセクションに対応する。
enum SidebarSelection: String, Hashable, Identifiable, CaseIterable {
    case convert
    case easyConvert
    case settings
    case about

    var id: String { rawValue }
}

// MARK: - Convert (UISpec mirrors docs/design/feature/convert.md)

/// 対象ファイルの絞り込み条件。
enum TargetFilter: String, Hashable, Identifiable, CaseIterable {
    case oneDay
    case threeDays
    case sevenDays
    case thirtyDays
    case all

    var id: String { rawValue }
}

/// 出力フォーマット。
enum OutputFormat: String, Hashable, Identifiable, CaseIterable {
    case jpeg
    case png
    case jpegXL
    case av1
    case webp

    var id: String { rawValue }

    /// 出力ファイルの拡張子。Flutter版 `OutputFormat.extension` に対応する。
    var fileExtension: String {
        switch self {
        case .jpeg: return ".jpg"
        case .png: return ".png"
        case .jpegXL: return ".jxl"
        case .av1: return ".avif"
        case .webp: return ".webp"
        }
    }
}

/// 最適化種別。
enum OptimizeType: String, Hashable, Identifiable, CaseIterable {
    case anime
    case photo
    case speed
    case quality

    var id: String { rawValue }
}

/// 変換モード。`fixed` は従来どおり全ファイル共通の設定で変換し、
/// `auto` は画像ごとに目標解像度と圧縮品質を決める（ADR 0049）。
enum ConvertMode: String, Hashable, Identifiable, CaseIterable, Sendable {
    case fixed
    case auto

    var id: String { rawValue }

    var l10nKey: String {
        switch self {
        case .fixed: return "c.mode.fixed"
        case .auto: return "c.mode.auto"
        }
    }

    var symbolName: String {
        switch self {
        case .fixed: return "slider.horizontal.3"
        case .auto: return "wand.and.stars"
        }
    }

    /// モードの概要・得意・不得意の文言キー。
    var summaryL10nKey: String { "c.mode.\(rawValue).summary" }
    var strengthL10nKey: String { "c.mode.\(rawValue).strength" }
    var weaknessL10nKey: String { "c.mode.\(rawValue).weakness" }
}

/// 自動最適化のコンテンツ種別。色差サブサンプリングと
/// エンコーダのプリセットを選ぶ。
enum ContentType: String, Hashable, Identifiable, CaseIterable, Sendable {
    case anime
    case photo

    var id: String { rawValue }

    /// 既存の最適化種別のラベルを流用する。
    var l10nKey: String {
        switch self {
        case .anime: return "c.optimize.anime"
        case .photo: return "c.optimize.photo"
        }
    }
}

/// 自動最適化の目標解像度。長辺のpxで比較する。
/// 一覧の解像度表記は16:9の参考値で、実際の出力は元画像のアスペクト比を保つ。
enum TargetSize: String, Hashable, Identifiable, CaseIterable, Sendable {
    case twoK = "k2"
    case fourK = "k4"
    case fiveK = "k5"
    case eightK = "k8"

    var id: String { rawValue }

    var longEdge: Int {
        switch self {
        case .twoK: return 1920
        case .fourK: return 3840
        case .fiveK: return 5120
        case .eightK: return 7680
        }
    }

    var label: String {
        switch self {
        case .twoK: return "2K (1920×1080)"
        case .fourK: return "4K (3840×2160)"
        case .fiveK: return "5K (5120×2880)"
        case .eightK: return "8K (7680×4320)"
        }
    }
}

/// 画質と処理速度のプリセット。品質値はBPPに応じて補正する。
enum QualityPreset: String, Hashable, Identifiable, CaseIterable, Sendable {
    case best
    case high
    case medium
    case low

    var id: String { rawValue }

    var l10nKey: String {
        switch self {
        case .best: return "c.preset.best"
        case .high: return "c.preset.high"
        case .medium: return "c.preset.medium"
        case .low: return "c.preset.low"
        }
    }

    /// 品質の基準値。ファイルサイズに応じた補正の起点になる。
    var quality: Int {
        switch self {
        case .best: return 90
        case .high: return 80
        case .medium: return 60
        case .low: return 40
        }
    }
}

/// アップスケーラーのエンジン。`upscayl-bin` と `realcugan-ncnn-vulkan` の二択。
enum UpscaleEngine: String, Hashable, Identifiable, CaseIterable, Sendable {
    case upscayl
    case realCUGAN

    var id: String { rawValue }

    /// UIプルダウンに表示する名前。
    var displayName: String {
        switch self {
        case .upscayl: return "upscayl-bin"
        case .realCUGAN: return "Real-CUGAN"
        }
    }

    /// Real-CUGANは1xモデルが存在しないため拡大率2〜4に制限する。
    var scaleRange: ClosedRange<Double> {
        switch self {
        case .upscayl: return 1...4
        case .realCUGAN: return 2...4
        }
    }
}

/// アップスケールモデル選択肢。プルダウン表示用のタプル。
/// Real-CUGANではフォルダ名+ファイル名のID（`models-se/up2x-conservative`）を持つ。
struct UpscaleModelOption: Hashable, Identifiable {
    /// 設定JSONへ保存するID。upscaylはモデル名そのまま、Real-CUGANは `フォルダ/ファイル名`。
    let id: String
    var label: String
}

/// 外観モード。macOSの外観モードと同じくライト／ダーク／自動（システムに従う）。
enum AppearanceMode: String, Hashable, Identifiable, CaseIterable {
    case auto
    case light
    case dark

    var id: String { rawValue }
}

/// 文字の大きさ。小さい／標準／大きい。
enum FontSizeOption: String, Hashable, Identifiable, CaseIterable {
    case small
    case standard
    case large

    var id: String { rawValue }
}

/// 処理状態。表示文言はFlutter版と同一にする。
enum ProcessStatus: String, Hashable, CaseIterable {
    case waiting
    case running
    case success
    case failure

    func label(language: String) -> String {
        switch self {
        case .waiting: return L10n.string("status.waitingIcon", language: language)
        case .running: return L10n.string("status.runningIcon", language: language)
        case .success: return L10n.string("status.successIcon", language: language)
        case .failure: return L10n.string("status.failureIcon", language: language)
        }
    }
}

/// 進捗表の1行分（フェーズ2ではダミーデータのみ）。
struct FileRow: Identifiable {
    let id = UUID()
    var fileName: String
    /// 変換対象ファイルのフルパス。Finder表示に使う。
    var sourcePath: String = ""
    /// 変換後ファイルのフルパス。Finder表示に使う。
    var outputPath: String = ""
    var upscale: ProcessStatus
    var compress: ProcessStatus
    var output: ProcessStatus
}

// MARK: - Settings (UISpec mirrors docs/design/feature/settings.md)

/// サウンド選択肢。
struct SoundOption: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var isBundled: Bool

    /// 同梱のみサンプルprefixを付ける。Flutter版と同一仕様。
    func label(language: String) -> String {
        if name == WallpaperSelection.noneName {
            return L10n.string("s.none", language: language)
        }
        if isBundled {
            return String(format: L10n.string("sample.prefix", language: language), name)
        }
        return name
    }
}

/// 壁紙選択肢。
struct WallpaperOption: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var isBundled: Bool

    /// 同梱のみサンプルprefixを付ける。Flutter版と同一仕様。
    func label(language: String) -> String {
        if name == WallpaperSelection.noneName {
            return L10n.string("s.none", language: language)
        }
        if isBundled {
            return String(format: L10n.string("sample.prefix", language: language), name)
        }
        return name
    }
}
