import SwiftUI

/// コールアウト共通の角丸。ホバー枠を重ねる `CollapsibleCallout` と共有する。
/// Why not 各Viewに12を直書きするか: 片方だけ変えると枠が背景からずれるため。
enum CalloutStyle {
    static let cornerRadius: CGFloat = 12
}

/// GitHub Alerts 風コールアウトの共通外観（背景・枠線・左のアクセントバー・余白）。
/// 「モードの説明」と「対応フォーマット」で同じ装飾を複製しないよう、見た目をここに集約する。
struct CalloutContainer<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                tint.opacity(0.08),
                in: RoundedRectangle(cornerRadius: CalloutStyle.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CalloutStyle.cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.leading, 3)
            }
    }
}

/// コールアウトのアイコン・見出し・本文を並べる共通レイアウト。
/// 見出しだけを差し替えられるようにし、アイコンの幅と本文の余白を共通化する。
struct CalloutLayout<Header: View, Content: View>: View {
    let icon: String
    let tint: Color
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 8) {
                header()
                content()
            }
        }
    }
}
