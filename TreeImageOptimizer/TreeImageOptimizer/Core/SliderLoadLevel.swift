import SwiftUI

/// スライダーの負荷レベル。負荷が高い操作を色で知らせる。
/// 通常はシステムのアクセントカラー、警告は黄、危険は赤を使う。
enum SliderLoadLevel: Equatable {
    case normal
    case warning
    case danger

    /// 拡大率の負荷。1〜2は通常、3は警告、4は危険。
    static func scaleLevel(for value: Double) -> Self {
        if value >= 4 { return .danger }
        if value >= 3 { return .warning }
        return .normal
    }

    /// 品質の負荷。79以下は通常、80〜89は警告、90以上は危険。
    static func qualityLevel(for value: Double) -> Self {
        if value >= 90 { return .danger }
        if value >= 80 { return .warning }
        return .normal
    }

    /// 並列数の負荷。最大並列数に対する割合で判定する。
    /// 6割以下は通常、7〜8割は警告、9割以上は危険。
    static func parallelLevel(parallel: Double, maxParallel: Double) -> Self {
        guard maxParallel > 0 else { return .normal }
        let ratio = parallel / maxParallel
        if ratio >= 0.9 { return .danger }
        if ratio >= 0.7 { return .warning }
        return .normal
    }

    /// スライダーに適用する色。通常はシステムの既定色を使う。
    var tint: Color {
        switch self {
        case .normal: return .accentColor
        case .warning: return .yellow
        case .danger: return .red
        }
    }
}
