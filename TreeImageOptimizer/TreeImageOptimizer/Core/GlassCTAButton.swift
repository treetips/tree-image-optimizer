import SwiftUI

/// 変換実行・アップデート確認で共用するCTAボタン。
/// Liquid Glassでグラス感を出す。
struct GlassCTAButton: View {
    var title: String
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.body)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity)
    }
}
