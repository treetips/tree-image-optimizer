import AppKit
import Testing

@testable import TreeImageOptimizer

/// 比較ウインドウの生成・再利用・破棄を確認する。
/// 同じ変換元で複数のウインドウを開かず、閉じたら保持を外すことが目的。
@Suite("ComparisonWindowController")
@MainActor
struct ComparisonWindowControllerTests {
    @Test("同じ変換元の比較ウインドウは再利用し、閉じると保持を外す")
    func reusesAndReleasesWindow() {
        let beforePath = "/tmp/\(UUID().uuidString).png"
        let identifier = NSUserInterfaceItemIdentifier(beforePath)
        let request = ComparisonRequest(
            beforePath: beforePath, afterPath: beforePath + ".jxl",
            title: "preview-\(UUID().uuidString)", beforeLabel: "before", afterLabel: "after",
            missingMessage: "missing")

        ComparisonWindowController.shared.open(request)

        let opened = NSApp.windows.first { $0.identifier == identifier && $0.isVisible }
        #expect(opened != nil, "比較ウインドウが開くこと")
        #expect(opened?.styleMask.contains(.resizable) == true, "比較ウインドウはリサイズできること")

        // 同じ変換元をもう一度開いても、既存のウインドウを前面に出すだけにする。
        var secondRequest = request
        secondRequest.title = "preview-second-\(UUID().uuidString)"
        ComparisonWindowController.shared.open(secondRequest)

        let matches = NSApp.windows.filter { $0.identifier == identifier && $0.isVisible }
        #expect(matches.count == 1, "同じ変換元のウインドウを重複して開かないこと")
        #expect(matches.first?.title == request.title, "既存のウインドウのタイトルを変えないこと")

        // 閉じる通知で保持を外すことを確認する。AppKit の close は表示サイクルに
        // 依存するため、デリゲートの処理を直接呼んで判定する。
        ComparisonWindowController.shared.windowWillClose(
            Notification(name: NSWindow.willCloseNotification, object: opened))
        opened?.orderOut(nil)

        var reopenedRequest = request
        reopenedRequest.title = "preview-reopened-\(UUID().uuidString)"
        ComparisonWindowController.shared.open(reopenedRequest)

        let reopened = NSApp.windows.first {
            $0.identifier == identifier && $0.title == reopenedRequest.title && $0.isVisible
        }
        #expect(reopened != nil, "閉じたウインドウを再利用しないこと")
        reopened?.orderOut(nil)
        reopened?.close()
        opened?.close()
    }
}
