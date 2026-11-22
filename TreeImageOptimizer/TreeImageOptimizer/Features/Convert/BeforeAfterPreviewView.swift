import AppKit
import SwiftUI

/// 変換前後の画像をスライダーで比較するビュー（ADR 0071）。
/// 前後の画像はアスペクト比を保ったまま同じ表示サイズに揃え、区切り線で「前 → 後」を切り替える。
struct BeforeAfterPreviewView: View {
    let beforePath: String
    let afterPath: String
    /// 画像を読み込めないときに表示する文言（L10n 経由）。
    let missingMessage: String

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
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(missingMessage)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 比較ウインドウを開くための入力一式。引数を増やさずに済むよう1つの型にまとめる。
struct ComparisonRequest: Sendable {
    var beforePath: String
    var afterPath: String
    var title: String
    var beforeLabel: String
    var afterLabel: String
    var missingMessage: String
}

/// 結果表のプレビューセル。クリックで比較ウインドウを別に開く（ADR 0071）。
/// 出力が完了していない間は「後」が無いため無効化する。
/// Why not 絵文字（🔍）を使うか: 絵文字は色を変えられず、クリック可能になったことが
/// 視認しづらいため、SF Symbol にして有効時にテーマ色で強調する。
///
/// Why not ホバーで拡大するアニメーションや Button を使うか: `Table` の行はセルの中身の
/// 理想サイズから行高を決める。アニメーション・押下状態・フォーカス・ツールチップは
/// 行高の再計算を誘発し、ウィンドウの制約更新が「Update Constraints in Window」の
/// 上限を超えてクラッシュするため、固定サイズの画像とタップジェスチャに絞っている
/// （ADR 0075）。
struct ConvertPreviewCell: View {
    let beforePath: String
    let afterPath: String
    let title: String
    let beforeLabel: String
    let afterLabel: String
    let missingMessage: String
    let isEnabled: Bool

    var body: some View {
        Image(systemName: "rectangle.split.2x1")
            .appFont(.body)
            .foregroundStyle(iconColor)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .onTapGesture {
                openPreview()
            }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(isEnabled ? .isButton : [])
            .accessibilityRespondsToUserInteraction(isEnabled)
            .accessibilityAction {
                openPreview()
            }
    }

    /// 比較ウインドウを次のメインアクタージョブで開く。
    private func openPreview() {
        guard isEnabled else { return }
        // Why not その場で開くか: Table の行更新中に新しい NSWindow を生成すると、
        // AppKit の制約更新が再入して同じループを誘発するため、次のメインアクター
        // ジョブで開く（ADR 0075）。
        let request = ComparisonRequest(
            beforePath: beforePath, afterPath: afterPath, title: title,
            beforeLabel: beforeLabel, afterLabel: afterLabel,
            missingMessage: missingMessage)
        Task { @MainActor in
            ComparisonWindowController.shared.open(request)
        }
    }

    /// 有効時はテーマ色、無効時は控えめなグレー。
    private var iconColor: Color {
        guard isEnabled else { return Color.secondary.opacity(0.35) }
        return Color.accentColor
    }
}

/// 比較ウインドウの中身。比較ビューを全面に広げ、下部に前後ラベルを添える。
struct BeforeAfterPreviewWindowContent: View {
    let beforePath: String
    let afterPath: String
    let beforeLabel: String
    let afterLabel: String
    let missingMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BeforeAfterPreviewView(
                beforePath: beforePath, afterPath: afterPath, missingMessage: missingMessage
            )
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

/// 比較を表示するウインドウ。Escキーで閉じられるようにする。
/// Why not 標準の NSWindow をそのまま使うか: 通常のウインドウは Esc でのクローズを
/// 標準では行わないため、`cancelOperation(_:)`（Esc で応答チェーンへ送られる）を上書きする。
final class PreviewWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}

/// 比較ウインドウの生成と保持。閉じたら参照を外して破棄できるようにする（ADR 0071）。
/// Why not シートを使うか: 壁紙サイズ（5K等）の画像はシート内の小さい領域へ縮小され、
/// アップスケール済みの「後」がジャギーに見える。別ウインドウで大きく表示するため。
/// Why not メインアクター隔離を外すか: 生成・破棄・辞書更新はすべてメインスレッドで行うため、
/// `@MainActor` で隔離してコンパイラに保証させる。
@MainActor
final class ComparisonWindowController: NSObject, NSWindowDelegate {
    static let shared = ComparisonWindowController()
    /// 変換元パスをキーに、開いている比較ウインドウを保持する。同じ行を複数開かせないため。
    private var windows: [String: NSWindow] = [:]

    func open(_ request: ComparisonRequest) {
        // 同じ比較（同じ変換元）が既に開いていれば前面へ出すだけで、重複させない。
        if let existing = windows[request.beforePath] {
            // 最小化中は makeKeyAndOrderFront だけでは復元されないため、先に戻す。
            existing.deminiaturize(nil)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let content = BeforeAfterPreviewWindowContent(
            beforePath: request.beforePath, afterPath: request.afterPath,
            beforeLabel: request.beforeLabel, afterLabel: request.afterLabel,
            missingMessage: request.missingMessage)
        let hosting = NSHostingController(rootView: content)
        // 画面の8割を上限に、壁紙サイズでも縮小のジャギーを抑えられる大きさで開く。
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let contentSize = NSSize(
            width: min(screen.width * 0.8, 1600),
            height: min(screen.height * 0.8, 1000))
        // Why not 生成後に styleMask を変えるか: コンテンツ設定後の styleMask 変更は
        // 制約の再評価を招き、表示直後のレイアウトを不安定にするため、生成時に指定する。
        let window = PreviewWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.contentViewController = hosting
        window.title = request.title
        window.setContentSize(contentSize)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier(request.beforePath)
        // Why not 表示してから保持するか: 表示直後のレイアウト中にウィンドウが
        // 解放されないよう、先に保持してから前面へ出す。
        windows[request.beforePath] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let key = window.identifier?.rawValue
        else { return }
        windows.removeValue(forKey: key)
    }
}
