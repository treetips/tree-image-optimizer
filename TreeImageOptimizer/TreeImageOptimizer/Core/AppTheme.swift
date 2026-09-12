import SwiftUI

/// アプリ全体の見た目を一括管理するテーマ。
/// 文字の大きさはここでのマッピングが唯一の正本であり、
/// `RootView` の1か所から適用することで画面全体に連動させる。
enum AppTheme {
    /// 文字の大きさ設定に対する全体倍率。
    /// 固定サイズフォントが必要になった場合の基準値。
    static func fontScale(for fontSize: String) -> CGFloat {
        switch fontSize {
        case FontSizeOption.small.rawValue: return 0.88
        case FontSizeOption.large.rawValue: return 1.35
        default: return 1.0
        }
    }

    /// 文字の大きさ設定に対するDynamic Type指定。
    /// 標準はシステム既定（`.large`）と同じにする。
    /// テキストスタイル（`.headline`等）のフォントはこれに連動する。
    static func dynamicTypeSize(for fontSize: String) -> DynamicTypeSize {
        switch fontSize {
        case FontSizeOption.small.rawValue: return .small
        case FontSizeOption.large.rawValue: return .xxLarge
        default: return .large
        }
    }

    /// 文字の大きさ設定に対するサイズカテゴリ。
    /// 小→標準→大で明確に差が出る幅にする。
    static func sizeCategory(for fontSize: String) -> ContentSizeCategory {
        switch fontSize {
        case FontSizeOption.small.rawValue: return .small
        case FontSizeOption.large.rawValue: return .extraExtraLarge
        default: return .large
        }
    }

    /// テキストスタイルの基準サイズ（macOS既定値）。
    static func baseSize(for style: Font.TextStyle) -> CGFloat {
        if style == .largeTitle { return 26 }
        if style == .title { return 28 }
        if style == .title2 { return 22 }
        if style == .title3 { return 20 }
        if style == .headline { return 13 }
        if style == .subheadline { return 11 }
        if style == .callout { return 12 }
        if style == .footnote { return 11 }
        if style == .caption { return 12 }
        if style == .caption2 { return 11 }
        return 13
    }

    /// テキストスタイルの太さ。`.headline` の強調を維持する。
    static func weight(for style: Font.TextStyle) -> Font.Weight {
        if style == .headline { return .semibold }
        return .regular
    }

    /// 倍率を適用した明示フォント。環境値に依存せず確実に拡大する。
    static func font(_ style: Font.TextStyle, scale: CGFloat) -> Font {
        .system(size: baseSize(for: style) * scale, weight: weight(for: style))
    }
}

/// アプリ全体のフォント倍率。`RootView` の1か所で設定する。
struct AppFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var appFontScale: CGFloat {
        get { self[AppFontScaleKey.self] }
        set { self[AppFontScaleKey.self] = newValue }
    }
}

/// テーマ倍率を適用するフォントモディファイア。
/// `.font(.headline)` の代わりに `.appFont(.headline)` と書く。
struct AppFontModifier: ViewModifier {
    @Environment(\.appFontScale) private var scale
    var style: Font.TextStyle

    func body(content: Content) -> some View {
        content.font(AppTheme.font(style, scale: scale))
    }
}

extension View {
    func appFont(_ style: Font.TextStyle) -> some View {
        modifier(AppFontModifier(style: style))
    }
}
