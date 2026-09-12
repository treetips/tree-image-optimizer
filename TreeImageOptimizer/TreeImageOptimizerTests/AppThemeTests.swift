import SwiftUI
import Testing

@testable import TreeImageOptimizer

@Suite("AppTheme")
struct AppThemeTests {
    @Test("文字の大きさマッピング")
    func mapping() {
        #expect(AppTheme.dynamicTypeSize(for: "small") == .small)
        #expect(AppTheme.dynamicTypeSize(for: "standard") == .large)
        #expect(AppTheme.dynamicTypeSize(for: "large") == .xxLarge)
        #expect(AppTheme.dynamicTypeSize(for: "unknown") == .large)
        #expect(AppTheme.fontScale(for: "small") == 0.88)
        #expect(AppTheme.fontScale(for: "standard") == 1.0)
        #expect(AppTheme.fontScale(for: "large") == 1.35)
        #expect(AppTheme.sizeCategory(for: "small") == .small)
        #expect(AppTheme.sizeCategory(for: "standard") == .large)
        #expect(AppTheme.sizeCategory(for: "large") == .extraExtraLarge)
        #expect(AppTheme.sizeCategory(for: "unknown") == .large)
    }

    @Test("明示フォントは倍率で変わる")
    func explicitFontScales() {
        #expect(AppTheme.baseSize(for: .headline) == 13)
        #expect(AppTheme.font(.headline, scale: 1.0) == .system(size: 13, weight: .semibold))
        #expect(AppTheme.font(.headline, scale: 1.35) == .system(size: 13 * 1.35, weight: .semibold))
        #expect(AppTheme.font(.body, scale: 1.0) == .system(size: 13, weight: .regular))
    }

    @Test("明示フォントは描画サイズが変わる")
    @MainActor
    func rendersScaledFonts() {
        func height(scale: CGFloat) -> Int? {
            struct Probe: View {
                var scale: CGFloat
                var body: some View {
                    Text("テスト")
                        .font(AppTheme.font(.body, scale: scale))
                }
            }
            let renderer = ImageRenderer(content: Probe(scale: scale))
            renderer.scale = 1
            return renderer.cgImage.map { $0.height }
        }
        let small = height(scale: AppTheme.fontScale(for: "small"))
        let standard = height(scale: AppTheme.fontScale(for: "standard"))
        let large = height(scale: AppTheme.fontScale(for: "large"))
        #expect(small != nil && standard != nil && large != nil)
        #expect(small! < standard!)
        #expect(standard! < large!)
    }

    // 注意：ImageRendererによる描画サイズ比較はヘッドレス環境では
    // Dynamic Typeが無視される（常に同一サイズで描画される）ため検証に使えない。
    // 実機・実画面での目視確認が必要。
}
