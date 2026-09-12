import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("L10n")
struct L10nTests {
    @Test("日本語解決")
    func japanese() {
        #expect(L10n.string("nav.convert", language: "ja") == "一括画像変換")
        #expect(L10n.string("menu.checkForUpdates", language: "ja-JP") == "更新を確認")
    }

    @Test("英語解決")
    func english() {
        #expect(L10n.string("nav.convert", language: "en") == "Convert")
        #expect(L10n.string("menu.checkForUpdates", language: "en-US") == "Check for Update")
    }

    @Test("書式付き文字列")
    func formatted() {
        let ja = String(format: L10n.string("c.done.mixed", language: "ja"), 3, 1)
        #expect(ja == "変換完了：成功3件・失敗1件")
        let en = String(format: L10n.string("c.done.mixed", language: "en"), 3, 1)
        #expect(en == "Conversion complete: 3 succeeded, 1 failed")
    }
}
