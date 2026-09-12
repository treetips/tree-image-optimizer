import SwiftUI

/// ⓘアイコン。ホバー／フォーカスで説明ポップオーバーを表示する。
/// システムのツールチップより即時に表示され、複数行も読みやすい。
/// macOS標準のポップオーバーを使う。
struct HelpPopover: View {
    var text: String

    @State private var isPresented = false
    @State private var isHovering = false
    @State private var isPinned = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            isPinned.toggle()
            updatePresented()
        } label: {
            Image(systemName: "info.circle")
                .appFont(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { hovering in
            isHovering = hovering
            updatePresented()
        }
        .onChange(of: isFocused) {
            updatePresented()
        }
        .popover(isPresented: $isPresented) {
            Text(text)
                .appFont(.body)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(maxWidth: 280)
        }
    }

    private func updatePresented() {
        isPresented = isHovering || isFocused || isPinned
    }
}
