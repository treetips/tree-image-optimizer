import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("L10n")
struct L10nTests {
    @Test("日本語解決")
    func japanese() {
        #expect(L10n.string("nav.convert", language: "ja") == "一括画像変換")
        #expect(L10n.string("menu.checkForUpdates", language: "ja-JP") == "更新を確認")
        #expect(L10n.string("nav.updateAvailable", language: "ja") == "アップデートがあります")
        #expect(L10n.string("nav.download", language: "ja") == "ダウンロード")
        #expect(L10n.string("nav.downloading", language: "ja") == "ダウンロード中...")
        #expect(L10n.string("nav.updateReady", language: "ja") == "アップデート完了")
        #expect(L10n.string("nav.restart", language: "ja") == "アプリ再起動する")
        #expect(L10n.string("a.restartFailed", language: "ja") == "アプリの再起動に失敗しました")
        #expect(L10n.string("a.restarting", language: "ja") == "再起動中...")
        #expect(L10n.string("a.restartReadyMsg", language: "ja") == "再起動するとアップデートが反映されます。")
        #expect(L10n.string("nav.updateNone", language: "ja") == "アップデートは有りません")
        #expect(L10n.string("nav.installing", language: "ja") == "インストール中")
        #expect(L10n.string("nav.preparingUpdate", language: "ja") == "アップデートを準備中")
        #expect(L10n.string("nav.installFailed", language: "ja") == "インストールに失敗")
        #expect(L10n.string("nav.retry", language: "ja") == "再実行")
    }

    @Test("英語解決")
    func english() {
        #expect(L10n.string("nav.convert", language: "en") == "Convert")
        #expect(L10n.string("menu.checkForUpdates", language: "en-US") == "Check for Update")
        #expect(L10n.string("nav.download", language: "en") == "Download")
        #expect(L10n.string("nav.downloading", language: "en") == "Downloading...")
        #expect(L10n.string("nav.updateReady", language: "en") == "Update ready")
        #expect(L10n.string("nav.restart", language: "en") == "Restart app")
        #expect(L10n.string("a.restartFailed", language: "en") == "Failed to restart the app")
        #expect(L10n.string("a.restarting", language: "en") == "Restarting...")
        #expect(
            L10n.string("a.restartReadyMsg", language: "en")
                == "The update will be applied when you restart the app.")
        #expect(L10n.string("nav.updateNone", language: "en") == "No update available")
        #expect(L10n.string("nav.installing", language: "en") == "Installing")
        #expect(L10n.string("nav.preparingUpdate", language: "en") == "Preparing update")
        #expect(L10n.string("nav.installFailed", language: "en") == "Installation failed")
        #expect(L10n.string("nav.retry", language: "en") == "Retry")
    }

    @Test("自動最適化のラベル")
    func autoOptimizationLabels() {
        #expect(L10n.string("c.mode.fixed", language: "ja") == "固定最適化")
        #expect(L10n.string("c.mode.auto", language: "ja") == "自動最適化")
        #expect(L10n.string("c.preset.best", language: "ja") == "画質最優先")
        #expect(L10n.string("c.label.targetSize", language: "en") == "Target size")
    }

    @Test("書式付き文字列")
    func formatted() {
        let japanese = String(format: L10n.string("c.done.mixed", language: "ja"), 3, 1)
        #expect(japanese == "変換完了：成功3件・失敗1件")
        let english = String(format: L10n.string("c.done.mixed", language: "en"), 3, 1)
        #expect(english == "Conversion complete: 3 succeeded, 1 failed")
    }

    @Test("ダウンロード進捗の書式")
    func downloadProgressFormatted() {
        let japanese = String(format: L10n.string("nav.downloadingPercent", language: "ja"), 42)
        #expect(japanese == "ダウンロード中... 42%")
        let english = String(format: L10n.string("nav.downloadingPercent", language: "en"), 42)
        #expect(english == "Downloading... 42%")
    }
}
