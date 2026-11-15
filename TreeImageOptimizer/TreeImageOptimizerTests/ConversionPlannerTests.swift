import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import TreeImageOptimizer

@Suite("ConversionPlanner")
struct ConversionPlannerTests {
    private func autoConfig(
        target: TargetSize = .fiveK,
        preset: QualityPreset = .high,
        contentType: ContentType = .anime
    ) -> ConvertConfig {
        ConvertConfig(
            scale: 2,
            model: "realesr-animevideov3-x4",
            format: .jpegXL,
            optimizeType: .anime,
            quality: 80,
            parallelCount: 4,
            mode: .auto,
            contentType: contentType,
            targetSize: target,
            qualityPreset: preset
        )
    }

    /// BPPが補正なしの範囲（0.12〜0.25）になるファイルサイズ。
    private func neutralBytes(width: Int, height: Int) -> Int {
        Int(Double(width * height) * 0.2)
    }

    @Test("固定モードは全ファイルに同じ倍率と品質を返す")
    func fixedPlan() {
        let config = ConvertConfig(
            scale: 3, model: "m", format: .jpegXL, optimizeType: .anime, quality: 77,
            parallelCount: 4)
        let files = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]
        let plans = ConversionPlanner.plans(for: files, config: config)
        #expect(plans.count == 2)
        for plan in plans {
            #expect(plan.scale == 3)
            #expect(plan.resizeLongEdge == nil)
            #expect(plan.quality == 77)
        }
    }

    @Test("既に目標以上の画像は拡大も縮小もしない")
    func skipsImagesAtOrAboveTarget() {
        let metadata = ImageMetadata(
            width: 6000, height: 4000, bytes: neutralBytes(width: 6000, height: 4000))
        let plan = ConversionPlanner.plan(metadata: metadata, config: autoConfig())
        #expect(plan.scale == nil)
        #expect(plan.resizeLongEdge == nil)
        #expect(plan.quality == 80)
    }

    @Test("目標との差が僅かな画像は超解像を使わずリサイズで合わせる")
    func resizesNearTargetWithoutModel() {
        let metadata = ImageMetadata(
            width: 5000, height: 3333, bytes: neutralBytes(width: 5000, height: 3333))
        let plan = ConversionPlanner.plan(metadata: metadata, config: autoConfig())
        #expect(plan.scale == nil)
        #expect(plan.resizeLongEdge == 5120)
    }

    @Test("不足分は整数倍に切り上げ、超えた分は目標へ縮小する")
    func upscalesAndDownscalesToTarget() {
        let metadata = ImageMetadata(
            width: 3000, height: 2000, bytes: neutralBytes(width: 3000, height: 2000))
        let plan = ConversionPlanner.plan(metadata: metadata, config: autoConfig())
        // 5120 / 3000 = 1.71 → 2倍（6000）で目標を超えるため5120へ縮小する。
        #expect(plan.scale == 2)
        #expect(plan.resizeLongEdge == 5120)
    }

    @Test("4倍でも届かない画像は4倍で止める")
    func capsAtFourTimes() {
        let metadata = ImageMetadata(
            width: 1000, height: 800, bytes: neutralBytes(width: 1000, height: 800))
        let plan = ConversionPlanner.plan(metadata: metadata, config: autoConfig(target: .eightK))
        #expect(plan.scale == 4)
        #expect(plan.resizeLongEdge == nil)
    }

    @Test("目標ちょうどの画像は拡大しない")
    func exactTargetIsSkipped() {
        let metadata = ImageMetadata(
            width: 1920, height: 1080, bytes: neutralBytes(width: 1920, height: 1080))
        let plan = ConversionPlanner.plan(metadata: metadata, config: autoConfig(target: .twoK))
        #expect(plan.scale == nil)
        #expect(plan.resizeLongEdge == nil)
    }

    @Test("BPPが高いほど品質を下げ、低いほど上げる")
    func adjustsQualityByBytesPerPixel() {
        #expect(ConversionPlanner.adjustedQuality(base: 80, bytesPerPixel: 0.60) == 65)
        #expect(ConversionPlanner.adjustedQuality(base: 80, bytesPerPixel: 0.30) == 70)
        #expect(ConversionPlanner.adjustedQuality(base: 80, bytesPerPixel: 0.20) == 80)
        #expect(ConversionPlanner.adjustedQuality(base: 80, bytesPerPixel: 0.08) == 85)
        #expect(ConversionPlanner.adjustedQuality(base: 40, bytesPerPixel: 0.01) == 45)
    }

    @Test("長辺を合わせてもアスペクト比を維持する")
    func resizedDimensions() {
        let dimensions = ConversionPlanner.resizedDimensions(width: 3000, height: 2000, longEdge: 5120)
        #expect(dimensions.width == 5120)
        #expect(dimensions.height == 3413)
        let same = ConversionPlanner.resizedDimensions(width: 5120, height: 2880, longEdge: 5120)
        #expect(same.width == 5120)
        #expect(same.height == 2880)
    }

    @Test("自動モードのアニメは4:4:4のlibaom、実写は4:2:0のSVT-AV1")
    func autoProfiles() {
        let anime = CompressionService.profile(
            contentType: .anime, preset: .best, quality: 88)
        #expect(anime.avifCodec == "aom")
        #expect(anime.avifYuv == 444)
        #expect(anime.avifSpeed == 2)
        #expect(anime.jxlEffort == 9)
        #expect(anime.webpPreset == "drawing")
        #expect(anime.webpMethod == 6)
        #expect(anime.avifAdvanced == ["-a", "end-usage=q"])

        let photo = CompressionService.profile(
            contentType: .photo, preset: .low, quality: 40)
        #expect(photo.avifCodec == "svt")
        #expect(photo.avifYuv == 420)
        #expect(photo.avifSpeed == 8)
        #expect(photo.jxlEffort == 3)
        #expect(photo.webpPreset == "photo")
        #expect(photo.webpMethod == 0)
        #expect(photo.avifAdvanced.isEmpty)
    }

    @Test("固定モードのプロファイルは従来の表を維持する")
    func fixedProfileKeepsLegacyTables() {
        let profile = CompressionService.profile(optimizeType: .anime, quality: 80)
        #expect(profile.jpegQuality == 75)
        #expect(profile.pngQuality == 75)
        #expect(profile.jxlEffort == 7)
        #expect(profile.avifCodec == "aom")
        #expect(profile.avifAdvanced == ["-a", "end-usage=q", "-a", "cq-level=22"])
    }

    @Test("自動モードの設定は保存して復元できる")
    func persistsAutoSettings() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        var file = try store.load(maxParallel: 8)
        #expect(file.batch.mode == ConvertMode.fixed.rawValue)
        #expect(file.batch.targetSize == TargetSize.fiveK.rawValue)

        file.batch.mode = ConvertMode.auto.rawValue
        file.batch.contentType = ContentType.photo.rawValue
        file.batch.targetSize = TargetSize.eightK.rawValue
        file.batch.qualityPreset = QualityPreset.best.rawValue
        try store.save(file)

        let reloaded = try store.load(maxParallel: 8)
        #expect(reloaded.batch.mode == ConvertMode.auto.rawValue)
        #expect(reloaded.batch.contentType == ContentType.photo.rawValue)
        #expect(reloaded.batch.targetSize == TargetSize.eightK.rawValue)
        #expect(reloaded.batch.qualityPreset == QualityPreset.best.rawValue)
    }

    @Test("不正な自動モード設定は既定値へ補正される")
    func correctsInvalidAutoSettings() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("settings.json")
        try """
        {"batchConvert":{"mode":"nope","contentType":"x","targetSize":"k9","qualityPreset":"ultra"}}
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try SettingsStore(fileURL: fileURL).load(maxParallel: 8)
        #expect(loaded.batch.mode == ConvertMode.fixed.rawValue)
        #expect(loaded.batch.contentType == ContentType.anime.rawValue)
        #expect(loaded.batch.targetSize == TargetSize.fiveK.rawValue)
        #expect(loaded.batch.qualityPreset == QualityPreset.high.rawValue)
    }

    @Test("自動モードは大きい画像を拡大せず、小さい画像だけ超解像する")
    func autoModeSkipsLargeImages() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: base) }
        let paths = AppPaths(baseURL: base)
        let log = base.appendingPathComponent("upscale.log", isDirectory: false)

        // -s を受け取り、入力を拡大して出力する。呼ばれた入力量をログに残す。
        let upscaleScript = """
            #!/bin/sh
            in=""
            out=""
            scale=1
            while [ $# -gt 0 ]; do
              case "$1" in
                -i) in="$2"; shift 2 ;;
                -o) out="$2"; shift 2 ;;
                -s) scale="$2"; shift 2 ;;
                *) shift ;;
              esac
            done
            mkdir -p "$out" || exit 1
            for f in "$in"/*; do
              [ -f "$f" ] || continue
              w=$(/usr/bin/sips -g pixelWidth "$f" | /usr/bin/awk '/pixelWidth/{print $2}')
              h=$(/usr/bin/sips -g pixelHeight "$f" | /usr/bin/awk '/pixelHeight/{print $2}')
              echo "${w}x${h}" >> "REPLACE_LOG"
              base=${f##*/}
              /usr/bin/sips -z $((h * scale)) $((w * scale)) "$f" --out "$out/$base" >/dev/null || exit 1
            done
            exit 0
            """
        try writeExecutable(
            paths.upscalBinURL, contents: upscaleScript.replacingOccurrences(of: "REPLACE_LOG", with: log.path))
        try writeExecutable(paths.cjxlBinURL, contents: "#!/bin/sh\ncp \"$1\" \"$2\"\n")

        let inputDirectory = base.appendingPathComponent("input", isDirectory: true)
        let outputDirectory = base.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        let large = inputDirectory.appendingPathComponent("large.png", isDirectory: false)
        let small = inputDirectory.appendingPathComponent("small.png", isDirectory: false)
        try makePNG(at: large, width: 1920, height: 1080)
        try makePNG(at: small, width: 512, height: 512)

        let config = ConvertConfig(
            scale: 2, model: "m", format: .jpegXL, optimizeType: .anime, quality: 80,
            parallelCount: 2, mode: .auto, contentType: .anime, targetSize: .twoK,
            qualityPreset: .high)
        let result = await ConvertOrchestrator().run(
            files: [large, small], config: config, outputDirectory: outputDirectory, paths: paths
        ) { _ in }
        #expect(result == (success: 2, failure: 0), "全件成功すること: \(result)")

        let logText = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(logText.contains("512x512"), "小さい画像は超解像されること: \(logText)")
        #expect(!logText.contains("1920x1080"), "目標以上の画像は超解像されないこと: \(logText)")

        let largeOutput = outputDirectory.appendingPathComponent("large.jxl", isDirectory: false)
        let smallOutput = outputDirectory.appendingPathComponent("small.jxl", isDirectory: false)
        #expect(UpscaleService.imageDimensions(of: largeOutput)?.width == 1920)
        #expect(UpscaleService.imageDimensions(of: largeOutput)?.height == 1080)
        #expect(UpscaleService.imageDimensions(of: smallOutput)?.width == 1920)
        #expect(UpscaleService.imageDimensions(of: smallOutput)?.height == 1920)
    }

    private func writeExecutable(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makePNG(at url: URL, width: Int, height: Int) throws {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let image = makeImage(context: context, width: width, height: height),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw NSError(domain: "ConversionPlannerTests", code: 1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ConversionPlannerTests", code: 2)
        }
    }

    private func makeImage(context: CGContext, width: Int, height: Int) -> CGImage? {
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
