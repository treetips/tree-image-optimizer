import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 画像圧縮実行。Flutter版 `CompressionService` に対応する。
/// 最適化種別ごとのパラメータは `docs/design/feature/convert-flow/compression.md` 通り。
struct CompressionService: Sendable {
    let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: - Tables

    static let jpegQuality: [OptimizeType: Int] = [
        .anime: 75, .photo: 80, .speed: 60, .quality: 95
    ]

    static let pngQuality: [OptimizeType: Int] = [
        .anime: 75, .photo: 80, .speed: 60, .quality: 95
    ]

    static let jxlEffort: [OptimizeType: Int] = [
        .anime: 7, .photo: 7, .speed: 7, .quality: 9
    ]

    static let jxlExtraOpts: [OptimizeType: [String]] = [
        .anime: ["--lossless_jpeg=0"],
        .photo: ["--lossless_jpeg=0"],
        .speed: ["--lossless_jpeg=0"],
        .quality: ["--lossless_jpeg=0"]
    ]

    /// 速度プリセット。アニメ・画質最優先はlibaom、実写・速度優先はSVT-AV1を使う。
    /// 実写を4→6に上げ、AVIFとJPEG XLの速度差を広げた（ADR 0040）。
    /// libaom側は画質優先のため据え置く。
    static let avifSpeed: [OptimizeType: Int] = [
        .anime: 3, .photo: 6, .speed: 8, .quality: 4
    ]

    /// 出力のクロマサブサンプリング。SVT-AV1が4:2:0のみ対応のため、
    /// SVTを使う種別は必ず420にする（ADR 0037）。
    static let avifYuv: [OptimizeType: Int] = [
        .anime: 444, .photo: 420, .speed: 420, .quality: 444
    ]

    /// AVIFのエンコーダ選択。SVT-AV1は4:2:0しか受け付けないため、
    /// 4:4:4を指定する種別はlibaomのままにする（ADR 0037）。
    static let avifCodec: [OptimizeType: String] = [
        .anime: "aom", .photo: "svt", .speed: "svt", .quality: "aom"
    ]

    /// libaomのadvanced option。速度を上げた分のサイズ増を抑えるため、
    /// クオリティ指定を一段下げた（アニメ20→22、画質16→18）。VMAFは実測で不変（ADR 0040）。
    static let avifAomOpts: [OptimizeType: [String]] = [
        .anime: ["-a", "end-usage=q", "-a", "cq-level=22"],
        .photo: ["-a", "end-usage=q", "-a", "cq-level=22"],
        .speed: [],
        .quality: ["-a", "end-usage=q", "-a", "cq-level=18"]
    ]

    /// SVT-AV1のadvanced option。品質はCRFで決めるため、libaomの `cq-level` とは
    /// 値の意味が違う。photoは `--speed` を6に上げたため、サイズ増を抑える目的で
    /// `crf` を12にした（1536x2752で 113KB→116KB、VMAF 95.41→95.38、速度2.9倍。ADR 0040）。
    /// 速度優先はlibaomと同じくadvanced optionを渡さず `-q` に従わせる。
    static let avifSvtOpts: [OptimizeType: [String]] = [
        .photo: ["-a", "crf=12"],
        .speed: []
    ]

    static let webpPreset: [OptimizeType: String] = [
        .anime: "drawing", .photo: "photo", .speed: "default", .quality: "photo"
    ]

    static let webpMethod: [OptimizeType: Int] = [
        .anime: 4, .photo: 4, .speed: 0, .quality: 6
    ]

    /// 品質 (1-100) を JPEG XL の距離に変換する。100はロスレス相当 (0)。
    static func qualityToDistance(_ quality: Int) -> Double {
        let q = min(max(quality, 1), 100)
        if q >= 100 { return 0 }
        return Double(100 - q) * 0.1
    }

    /// エンコーダ1プロセスに割り当てるスレッド数。
    /// 予算は並列数そのもの（Pコア数で頭打ち）にし、ワーカー数で割って切り捨てる。
    /// 合計が予算を超えないため、スライダーの位置がそのまま負荷の目安になる（ADR 0039）。
    /// Why not: コア数をワーカー数で割ると、ワーカー数×スレッド数の積が常にコア数になり、
    /// 並列数を下げてもCPU負荷が下がらない（並列1〜9がいずれもコア数ぶん）うえ、
    /// 除算の端数で負荷が並列数に対して単調にならなかった。
    static func encoderThreads(
        parallelCount: Int,
        workers: Int,
        processorCount: Int = HardwareInfo.performanceCoreCount()
    ) -> Int {
        let budget = max(1, min(max(1, parallelCount), max(1, processorCount)))
        return max(1, budget / max(1, workers))
    }

    // MARK: - Argument builders (pure, testable)

    static func jpegoptimArguments(output: String, quality: Int) -> [String] {
        let dir = URL(fileURLWithPath: output, isDirectory: false).deletingLastPathComponent().path
        return ["-m\(quality)", "-o", "-d", dir, output]
    }

    static func pngoptimArguments(output: String, quality: Int) -> [String] {
        [output, "-o", output, "--quality", "\(quality)"]
    }

    static func cjxlArguments(input: String, output: String, optimizeType: OptimizeType, quality: Int, threads: Int)
        -> [String]
    {
        [
            input,
            output,
            "--distance=\(qualityToDistance(quality))",
            "-e", "\(jxlEffort[optimizeType, default: 7])",
            "--num_threads=\(threads)"
        ] + (jxlExtraOpts[optimizeType] ?? [])
    }

    static func avifencArguments(
        input: String, output: String, optimizeType: OptimizeType, quality: Int, threads: Int
    ) -> [String] {
        let codec = avifCodec[optimizeType, default: "aom"]
        let advanced =
            codec == "svt" ? (avifSvtOpts[optimizeType] ?? []) : (avifAomOpts[optimizeType] ?? [])
        return [
            "-c", codec,
            "--speed", "\(avifSpeed[optimizeType, default: 6])",
            "-q", "\(quality)",
            "-y", "\(avifYuv[optimizeType, default: 420])",
            "-j", "\(threads)"
        ] + advanced + [input, output]
    }

    static func cwebpArguments(input: String, output: String, optimizeType: OptimizeType, quality: Int) -> [String] {
        [
            "-preset", webpPreset[optimizeType, default: "default"],
            "-q", "\(quality)",
            "-m", "\(webpMethod[optimizeType, default: 4])",
            "-mt",
            input,
            "-o",
            output
        ]
    }

    // MARK: - Run

    func run(
        input: URL,
        output: URL,
        format: OutputFormat,
        optimizeType: OptimizeType,
        quality: Int,
        threads: Int,
        paths: AppPaths
    ) async throws {
        switch format {
        case .jpeg:
            try await compressJpeg(input: input, output: output, optimizeType: optimizeType, paths: paths)
        case .png:
            try await compressPng(input: input, output: output, optimizeType: optimizeType, paths: paths)
        case .jpegXL:
            let bin = paths.cjxlBinURL
            try await runBinary(
                bin,
                args: Self.cjxlArguments(
                    input: input.path, output: output.path,
                    optimizeType: optimizeType, quality: quality, threads: threads
                ), workingDirectory: bin.deletingLastPathComponent().path)
        case .av1:
            let bin = paths.avifencBinURL
            try await runBinary(
                bin,
                args: Self.avifencArguments(
                    input: input.path, output: output.path,
                    optimizeType: optimizeType, quality: quality, threads: threads
                ), workingDirectory: bin.deletingLastPathComponent().path)
        case .webp:
            let bin = paths.cwebpBinURL
            try await runBinary(
                bin,
                args: Self.cwebpArguments(
                    input: input.path, output: output.path,
                    optimizeType: optimizeType, quality: quality
                ), workingDirectory: bin.deletingLastPathComponent().path)
        }
    }

    private func runBinary(_ bin: URL, args: [String], workingDirectory: String) async throws {
        guard FileManager.default.fileExists(atPath: bin.path) else {
            AppLogger.shared.error("encoder binary missing: \(bin.path)")
            throw AppError.toolMissing(bin.path)
        }
        _ = try await runner.run(bin.path, args: args, workingDirectory: workingDirectory)
    }

    private func compressJpeg(input: URL, output: URL, optimizeType: OptimizeType, paths: AppPaths) async throws {
        let quality = Self.jpegQuality[optimizeType, default: 80]
        // jpegoptim はJPEG入力のみ対応のため、一旦JPEGを生成する。
        try Self.convertToJPEG(input: input, output: output, quality: 1.0)
        do {
            let bin = paths.jpegoptimBinURL
            try await runBinary(
                bin, args: Self.jpegoptimArguments(output: output.path, quality: quality),
                workingDirectory: bin.deletingLastPathComponent().path)
        } catch {
            AppLogger.shared.warning(
                "jpegoptim failed, falling back to re-encode: \(error.localizedDescription)")
            // フォールバック：指定品質で再エンコードする。
            try Self.convertToJPEG(input: output, output: output, quality: Double(quality) / 100.0)
        }
    }

    private func compressPng(input: URL, output: URL, optimizeType: OptimizeType, paths: AppPaths) async throws {
        let quality = Self.pngQuality[optimizeType, default: 80]
        try Self.convertToPNG(input: input, output: output)
        do {
            let bin = paths.pngoptimBinURL
            try await runBinary(
                bin, args: Self.pngoptimArguments(output: output.path, quality: quality),
                workingDirectory: bin.deletingLastPathComponent().path)
        } catch {
            AppLogger.shared.warning(
                "pngoptim failed, falling back to re-encode: \(error.localizedDescription)")
            try Self.convertToPNG(input: output, output: output)
        }
    }

    // MARK: - ImageIO helpers (Dart `package:image` の代替)

    static func convertToJPEG(input: URL, output: URL, quality: Double) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            throw AppError.fileNotFound("画像のデコードに失敗しました: \(input.path)")
        }
        CGImageDestinationSetProperties(dest, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw AppError.processFailed(executable: "CGImageDestination", exitCode: -1, output: output.path)
        }
    }

    static func convertToPNG(input: URL, output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw AppError.fileNotFound("画像のデコードに失敗しました: \(input.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw AppError.processFailed(executable: "CGImageDestination", exitCode: -1, output: output.path)
        }
    }
}
