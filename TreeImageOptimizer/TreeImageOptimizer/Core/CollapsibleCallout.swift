import SwiftUI

/// GitHub Alerts 風のコールアウトを、見出しクリックで開閉できるパネルにする。
/// 見出しの右に開閉状態を示すシェブロンを置き、縮小中は本文だけを隠す。
/// 「対応フォーマット」とモードの説明で同じ開閉操作を複製しないよう共通化する。
/// Why not SwiftUI の `DisclosureGroup` を使うか: ガラスカードの上でコールアウトの
/// 装飾を保ったまま、見出しのシェブロンだけを差し替えたいため。
struct CollapsibleCallout<Content: View>: View {
    let tint: Color
    let icon: String
    let title: String
    @Binding var isExpanded: Bool
    /// VoiceOver が開閉状態を読み上げるための文言。
    let expandedStateLabel: String
    let collapsedStateLabel: String
    @ViewBuilder var content: () -> Content

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            CalloutContainer(tint: tint) {
                CalloutLayout(icon: icon, tint: tint) {
                    header
                } content: {
                    if isExpanded {
                        content()
                            .transition(.opacity)
                    }
                }
            }
            // 余白を含むパネル全面をクリック領域にする。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .overlay {
            // ガラスの上でもクリックできると分かるよう、ホバー中だけ枠を強める。
            // Why not ヒットテストを有効にするか: 枠がパネル端のクリックを奪うため。
            RoundedRectangle(cornerRadius: CalloutStyle.cornerRadius, style: .continuous)
                .stroke(tint.opacity(isHovering ? 0.55 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .accessibilityValue(Text(isExpanded ? expandedStateLabel : collapsedStateLabel))
    }

    /// モード名やタイトルの右に、開閉状態を示すシェブロンを並べる。
    private var header: some View {
        HStack(spacing: 6) {
            Text(title)
                .appFont(.headline)
                .foregroundStyle(tint)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Spacer(minLength: 0)
        }
    }
}
