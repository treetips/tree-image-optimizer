import SwiftUI

/// Liquid Glassの濃さ・形状を一元管理する定義。
/// 透明度や屈折率を変えたい場合はここだけを変更すれば全画面に反映される。
/// カードの初期値は透明。青が必要な場所（フッター等）は呼び出し側でtintを上書きする。
enum GlassStyle {
    static let cardTintOpacity: Double = 0.0
    static let cardCornerRadius: CGFloat = 22
    static let footerTintOpacity: Double = 0.2
    static let footerCornerRadius: CGFloat = 22
    static let ctaTintOpacity: Double = 0.5
    static let ctaCornerRadius: CGFloat = 14
}

/// 全画面共通のLiquid Glassカード。`GroupBox` の置き換え用。
/// 初期値は透明。場所ごとに `tint` で背景色を上書きできる。
struct GlassCard<Content: View, Label: View>: View {
    var tint: Color?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label

    init(tint: Color? = nil, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.tint = tint
        self.content = content
        self.label = label
    }

    var body: some View {
        // Apple HIGのBoxesに合わせ、タイトルはガラス枠の外・上に置く。
        VStack(alignment: .leading, spacing: 6) {
            label()
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass(), in: RoundedRectangle(cornerRadius: GlassStyle.cardCornerRadius))
        }
    }

    private func glass() -> Glass {
        if let tint {
            .regular.tint(tint).interactive()
        } else {
            .regular.interactive()
        }
    }
}
