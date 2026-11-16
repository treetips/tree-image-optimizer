import SwiftUI

/// 変換実行・アップデート確認で共用するCTAボタン。
/// 横幅いっぱいにし、素通しのLiquid Glassでグラス感を出す。
/// `.borderedProminent` は不透明な背景を描くためグラスが透けないので使わない。
/// tintは半透明にしないとグラスが飽和してベタ塗りに見えるため、不透明色は指定しない。
struct GlassCTAButton: View {
    var title: String
    var disabled: Bool = false
    /// ボタンのテーマ色。既定はアクセントカラー。
    /// 停止は黄、取り消せない操作は赤を渡して、実行ボタンと見分けられるようにする。
    var tint: Color = .accentColor
    /// ラベルの左へ置くアイコン（SF Symbols名）。省略時は文字だけ。
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .appFont(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            // plainスタイルは描画部のみヒットするため、枠全体を受け付ける。
            .contentShape(Rectangle())
            .glassEffect(
                .regular.tint(tint.opacity(GlassStyle.ctaTintOpacity)).interactive(),
                in: RoundedRectangle(cornerRadius: GlassStyle.ctaCornerRadius)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}
