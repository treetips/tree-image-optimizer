import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("ConvertPipeline")
struct ConvertPipelineTests {
    @Test("品質→distance変換")
    func qualityToDistance() {
        #expect(CompressionService.qualityToDistance(100) == 0)
        #expect(CompressionService.qualityToDistance(80) == 2.0)
        #expect(CompressionService.qualityToDistance(1) == 9.9)
        #expect(CompressionService.qualityToDistance(0) == 9.9)
        #expect(CompressionService.qualityToDistance(101) == 0)
    }

    @Test("jpegoptim引数")
    func jpegoptimArgs() {
        #expect(CompressionService.jpegoptimArguments(output: "/tmp/o/a.jpg", quality: 75)
            == ["-m75", "-o", "-d", "/tmp/o", "/tmp/o/a.jpg"])
    }

    @Test("pngoptim引数")
    func pngoptimArgs() {
        #expect(CompressionService.pngoptimArguments(output: "/tmp/o/a.png", quality: 80)
            == ["/tmp/o/a.png", "-o", "/tmp/o/a.png", "--quality", "80"])
    }

    @Test("cjxl引数（アニメ・実写・速度・画質）")
    func cjxlArgs() {
        #expect(CompressionService.cjxlArguments(input: "i.png", output: "o.jxl", optimizeType: .anime, quality: 80, threads: 4)
            == ["i.png", "o.jxl", "--distance=2.0", "-e", "7", "--num_threads=4", "--lossless_jpeg=0"])
        #expect(CompressionService.cjxlArguments(input: "i.png", output: "o.jxl", optimizeType: .quality, quality: 80, threads: 2)
            == ["i.png", "o.jxl", "--distance=2.0", "-e", "9", "--num_threads=2", "--lossless_jpeg=0"])
        #expect(CompressionService.cjxlArguments(input: "i.png", output: "o.jxl", optimizeType: .speed, quality: 100, threads: 1)
            == ["i.png", "o.jxl", "--distance=0.0", "-e", "7", "--num_threads=1", "--lossless_jpeg=0"])
    }

    @Test("avifenc引数")
    func avifencArgs() {
        #expect(CompressionService.avifencArguments(input: "i.png", output: "o.avif", optimizeType: .anime, quality: 90)
            == ["--speed", "3", "-q", "90", "-y", "444", "-a", "end-usage=q", "-a", "cq-level=20", "i.png", "o.avif"])
        #expect(CompressionService.avifencArguments(input: "i.png", output: "o.avif", optimizeType: .speed, quality: 70)
            == ["--speed", "8", "-q", "70", "-y", "420", "i.png", "o.avif"])
        #expect(CompressionService.avifencArguments(input: "i.png", output: "o.avif", optimizeType: .quality, quality: 90)
            == ["--speed", "4", "-q", "90", "-y", "444", "-a", "end-usage=q", "-a", "cq-level=16", "i.png", "o.avif"])
    }

    @Test("cwebp引数")
    func cwebpArgs() {
        #expect(CompressionService.cwebpArguments(input: "i.png", output: "o.webp", optimizeType: .anime, quality: 80)
            == ["-preset", "drawing", "-q", "80", "-m", "4", "-mt", "i.png", "-o", "o.webp"])
        #expect(CompressionService.cwebpArguments(input: "i.png", output: "o.webp", optimizeType: .speed, quality: 80)
            == ["-preset", "default", "-q", "80", "-m", "0", "-mt", "i.png", "-o", "o.webp"])
        #expect(CompressionService.cwebpArguments(input: "i.png", output: "o.webp", optimizeType: .quality, quality: 80)
            == ["-preset", "photo", "-q", "80", "-m", "6", "-mt", "i.png", "-o", "o.webp"])
    }

    @Test("upscayl-bin引数")
    func upscaleArgs() {
        #expect(UpscaleService.arguments(input: "i.png", output: "o.png", scale: 2, model: "m", modelsDir: "/models")
            == ["-i", "i.png", "-o", "o.png", "-s", "2", "-m", "/models", "-n", "m"])
    }

    @Test("出力ファイル名（最初のドットで切る）")
    func outputFileName() {
        #expect(ConvertOrchestrator.outputFileName(for: "aaa.jpg", format: .jpegXL) == "aaa.jxl")
        #expect(ConvertOrchestrator.outputFileName(for: "a.b.png", format: .webp) == "a.webp")
    }

    @Test("対象ファイル選定（拡張子・日数・ソート）")
    func targetFiles() throws {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["b.png", "a.jpg", "c.webp", "skip.txt", "sub"] {
            let url = dir.appendingPathComponent(name, isDirectory: false)
            if name == "sub" {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                fm.createFile(atPath: url.path, contents: Data("x".utf8))
            }
        }
        // 古いファイルを用意
        let old = dir.appendingPathComponent("old.jpg", isDirectory: false)
        fm.createFile(atPath: old.path, contents: Data("x".utf8))
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -10 * 24 * 3600)], ofItemAtPath: old.path)

        let all = try TargetFiles.list(in: dir, modifiedWithinDays: nil)
        #expect(all.map { $0.lastPathComponent } == ["a.jpg", "b.png", "c.webp", "old.jpg"])
        let recent = try TargetFiles.list(in: dir, modifiedWithinDays: 7)
        #expect(!recent.map { $0.lastPathComponent }.contains("old.jpg"))
        #expect(recent.map { $0.lastPathComponent } == ["a.jpg", "b.png", "c.webp"])
    }

    @Test("存在しないフォルダはエラー")
    func missingFolder() {
        #expect(throws: AppError.self) {
            try TargetFiles.list(in: URL(fileURLWithPath: "/nonexistent-xyz"), modifiedWithinDays: nil)
        }
    }

    @Test("モデル一覧（.bin走査・フォールバック）")
    func models() throws {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(TargetFiles.listModels(in: dir) == ["realesr-animevideov3-x4"])
        for name in ["b.bin", "a.bin", "a.param"] {
            fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data("x".utf8))
        }
        #expect(TargetFiles.listModels(in: dir) == ["a", "b"])
    }
}
