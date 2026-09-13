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
