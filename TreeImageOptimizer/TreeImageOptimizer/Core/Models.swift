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

// MARK: - Compression parameters

/// AVIFエンコーダの種別。
/// Why not `String` で `"aom"` / `"svt"` を持つか: タイポが実行時まで検出されず、
/// 値を見て別のパラメータ表を選ぶ分岐（`codec == "svt"`）が生まれていたため。ADR 0061。
enum AvifCodec: String, Hashable, Sendable, Equatable {
    case aom
    case svt

    /// SVT-AV1 は 4:2:0 しか受け付けないため、使えるクロマサブサンプリングが決まる（ADR 0037）。
    var supportsYuv444: Bool {
        switch self {
        case .aom: return true
        case .svt: return false
        }
    }
}

/// AVIF のエンコーダ設定。
/// codec と advanced を1つに持つことで、呼び出し側が codec の値を見て
/// 別の表を引き直す分岐を書かずに済む（ADR 0061）。
struct AvifParameters: Sendable, Equatable {
    var codec: AvifCodec
    var speed: Int
    var yuv: Int
    var advanced: [String]

    /// SVT-AV1 は 4:2:0 のみ。4:4:4 を指定するとエンコードが失敗するため生成時に担保する。
    init(codec: AvifCodec, speed: Int, yuv: Int, advanced: [String]) {
        self.codec = codec
        self.speed = speed
        self.yuv = codec.supportsYuv444 ? yuv : 420
        self.advanced = advanced
    }
}

/// 最適化種別ごとの圧縮パラメータ。
/// Why not 種別→値の辞書を項目ごとに持つか: 1種別を追加・変更するのに8〜11か所の
/// 修正が必要で、表の対応が崩れても気づけなかったため。ADR 0061 で1テーブルに集約した。
struct OptimizeTypeParameters: Sendable, Equatable {
    var jpegQuality: Int
    var pngQuality: Int
    var jxlEffort: Int
    var jxlExtra: [String]
    var avif: AvifParameters
    var webpPreset: String
    var webpMethod: Int
}

/// 画質プリセットごとのエンコーダ調整値。
/// Why not `QualityPreset` に計算プロパティを3本並べるか: プリセット間の対応
/// （JPEG XL effort / AVIF speed / WebP method）が離れた場所に散らばり、
/// 自動モードの1プリセットを調整するのに3か所を見比べる必要があったため。ADR 0061。
struct QualityPresetParameters: Sendable, Equatable {
    var jxlEffort: Int
    /// AVIF の `--speed`。数値が大きいほど高速・低画質。
    var avifSpeed: Int
    /// WebP の `-m`。数値が大きいほど高画質・低速。
    var webpMethod: Int
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

    /// プリセットごとのエンコーダ調整値。画質を優先するほど低速・高圧縮に振る。
    var parameters: QualityPresetParameters {
        switch self {
        case .best: return QualityPresetParameters(jxlEffort: 9, avifSpeed: 2, webpMethod: 6)
        case .high: return QualityPresetParameters(jxlEffort: 7, avifSpeed: 4, webpMethod: 4)
        case .medium: return QualityPresetParameters(jxlEffort: 5, avifSpeed: 6, webpMethod: 2)
        case .low: return QualityPresetParameters(jxlEffort: 3, avifSpeed: 8, webpMethod: 0)
        }
    }

    /// JPEG XL の effort。画質を優先するほど高い。
    var jxlEffort: Int { parameters.jxlEffort }

    /// AVIF の `--speed`。数値が大きいほど高速・低画質。
    var avifSpeed: Int { parameters.avifSpeed }

    /// WebP の `-m`。数値が大きいほど高画質・低速。
    var webpMethod: Int { parameters.webpMethod }
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
    /// 実行中にユーザーがキャンセルした段階（ADR 0054）。
    case cancelled

    func label(language: String) -> String {
        switch self {
        case .waiting: return L10n.string("status.waitingIcon", language: language)
        case .running: return L10n.string("status.runningIcon", language: language)
        case .success: return L10n.string("status.successIcon", language: language)
        case .failure: return L10n.string("status.failureIcon", language: language)
        case .cancelled: return L10n.string("status.cancelledIcon", language: language)
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
