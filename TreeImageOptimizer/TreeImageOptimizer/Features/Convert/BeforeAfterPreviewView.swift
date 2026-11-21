import AppKit
import SwiftUI

/// 変換前後の画像をスライダーで比較するビュー（ADR 0071）。
/// 前後の画像はアスペクト比を保ったまま同じ表示サイズに揃え、区切り線で「前 → 後」を切り替える。
struct BeforeAfterPreviewView: View {
    let beforePath: String
    let afterPath: String

    @State private var split: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .leading) {
                // 後（変換後）を全面に表示する。
                previewImage(afterPath)
                    .frame(width: width, height: height)
                // 前（変換前）を左側の区切りまで表示する。
                previewImage(beforePath)
                    .frame(width: width, height: height)
                    .frame(width: width * split, alignment: .leading)
                    .clipped()
                // 区切り線とハンドル。
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: height)
                    .offset(x: width * split - 1)
                Image(systemName: "arrow.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .padding(6)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                    .offset(x: width * split - 14)
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        split = min(max(value.location.x / width, 0), 1)
                    }
            )
        }
    }

    /// 画像を読み、無ければプレースホルダーを返す。
    @ViewBuilder
    private func previewImage(_ path: String) -> some View {
        if let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 結果表のプレビューセル。クリックで比較ウインドウを別に開く（ADR 0071）。
struct ConvertPreviewCell: View {
    let beforePath: String
    let afterPath: String
    let title: String
    let beforeLabel: String
    let afterLabel: String

    var body: some View {
        Button {
            ComparisonWindowController.shared.open(
                beforePath: beforePath, afterPath: afterPath,
                title: title, beforeLabel: beforeLabel, afterLabel: afterLabel)
        } label: {
            Text("🔍").appFont(.body)
        }
        .buttonStyle(.plain)
    }
}

/// 比較ウインドウの中身。比較ビューを全面に広げ、下部に前後ラベルを添える。
struct BeforeAfterPreviewWindowContent: View {
    let beforePath: String
    let afterPath: String
    let beforeLabel: String
    let afterLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BeforeAfterPreviewView(beforePath: beforePath, afterPath: afterPath)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(beforeLabel).appFont(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(afterLabel).appFont(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 900, minHeight: 600)
    }
}

/// 比較ウインドウの生成と保持。閉じたら参照を外して破棄できるようにする（ADR 0071）。
/// Why not シートを使うか: 壁紙サイズ（5K等）の画像はシート内の小さい領域へ縮小され、
/// アップスケール済みの「後」がジャギーに見える。別ウインドウで大きく表示するため。
/// Why not @unchecked を外すか: 生成・破棄はすべてメインスレッド（SwiftUIのボタンアクションと
/// NSWindowデリゲート）で行うため、`@MainActor` 相当の実態を保ちつつ Sendable を宣言する。
final class ComparisonWindowController: NSObject, NSWindowDelegate, @unchecked Sendable {
    static let shared = ComparisonWindowController()
    private var windows: [NSWindow] = []

    func open(
        beforePath: String, afterPath: String, title: String, beforeLabel: String, afterLabel: String
    ) {
        let content = BeforeAfterPreviewWindowContent(
            beforePath: beforePath, afterPath: afterPath,
            beforeLabel: beforeLabel, afterLabel: afterLabel)
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        // 画面の8割を上限に、壁紙サイズでも縮小のジャギーを抑えられる大きさで開く。
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.setContentSize(
            NSSize(
                width: min(screen.width * 0.8, 1600),
                height: min(screen.height * 0.8, 1000)))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
    }
}
