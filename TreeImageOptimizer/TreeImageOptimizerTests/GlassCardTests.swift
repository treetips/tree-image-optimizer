import SwiftUI
import Testing

@testable import TreeImageOptimizer

@Suite("GlassCard")
struct GlassCardTests {
    @Test("カードの初期値は透明で角丸は共通化される")
    func cardDefaultIsTransparent() {
        #expect(GlassStyle.cardTintOpacity == 0.0)
        #expect(GlassStyle.cardCornerRadius == 22)
    }

    @Test("フッターのみ青の既定値を保持する")
    func footerKeepsBlue() {
        #expect(GlassStyle.footerTintOpacity == 0.2)
        #expect(GlassStyle.footerCornerRadius == 22)
    }

    @Test("CTAの透明度と角丸は共通定義から参照できる")
    func ctaStyleIsCentralized() {
        #expect(GlassStyle.ctaTintOpacity == 0.5)
        #expect(GlassStyle.ctaCornerRadius == 14)
    }

    @Test("カードは場所ごとに背景色を上書きできる")
    func cardTintIsOverridable() {
        let defaultCard = GlassCard(tint: nil) {
            Text("content")
        } label: {
            Text("title")
        }
        #expect(defaultCard.tint == nil)
        let blueCard = GlassCard(tint: Color.accentColor.opacity(0.2)) {
            Text("content")
        } label: {
            Text("title")
        }
        #expect(blueCard.tint != nil)
    }
}
