import Testing

@testable import TreeImageOptimizer

@Suite("SliderLoadLevel")
struct SliderLoadLevelTests {
    @Test("拡大率は1〜2が通常・3が警告・4が危険")
    func scaleLevel() {
        #expect(SliderLoadLevel.scaleLevel(for: 1) == .normal)
        #expect(SliderLoadLevel.scaleLevel(for: 2) == .normal)
        #expect(SliderLoadLevel.scaleLevel(for: 3) == .warning)
        #expect(SliderLoadLevel.scaleLevel(for: 4) == .danger)
    }

    @Test("品質は79以下が通常・80〜89が警告・90以上が危険")
    func qualityLevel() {
        #expect(SliderLoadLevel.qualityLevel(for: 1) == .normal)
        #expect(SliderLoadLevel.qualityLevel(for: 79) == .normal)
        #expect(SliderLoadLevel.qualityLevel(for: 80) == .warning)
        #expect(SliderLoadLevel.qualityLevel(for: 89) == .warning)
        #expect(SliderLoadLevel.qualityLevel(for: 90) == .danger)
        #expect(SliderLoadLevel.qualityLevel(for: 100) == .danger)
    }

    @Test("並列数は6割以下が通常・7〜8割が警告・9割以上が危険")
    func parallelLevel() {
        #expect(SliderLoadLevel.parallelLevel(parallel: 6, maxParallel: 10) == .normal)
        #expect(SliderLoadLevel.parallelLevel(parallel: 7, maxParallel: 10) == .warning)
        #expect(SliderLoadLevel.parallelLevel(parallel: 8, maxParallel: 10) == .warning)
        #expect(SliderLoadLevel.parallelLevel(parallel: 9, maxParallel: 10) == .danger)
        #expect(SliderLoadLevel.parallelLevel(parallel: 10, maxParallel: 10) == .danger)
        #expect(SliderLoadLevel.parallelLevel(parallel: 1, maxParallel: 10) == .normal)
    }
}
