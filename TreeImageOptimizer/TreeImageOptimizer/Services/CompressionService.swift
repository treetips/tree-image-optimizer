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
        .anime: 75, .photo: 80, .speed: 60, .quality: 95,
    ]

    static let pngQuality: [OptimizeType: Int] = [
        .anime: 75, .photo: 80, .speed: 60, .quality: 95,
    ]

    static let jxlEffort: [OptimizeType: Int] = [
        .anime: 7, .photo: 7, .speed: 7, .quality: 9,
    ]

    static let jxlExtraOpts: [OptimizeType: [String]] = [
        .anime: ["--lossless_jpeg=0"],
        .photo: ["--lossless_jpeg=0"],
        .speed: ["--lossless_jpeg=0"],
        .quality: ["--lossless_jpeg=0"],
    ]

    static let avifSpeed: [OptimizeType: Int] = [
        .anime: 3, .photo: 4, .speed: 8, .quality: 4,
    ]

    static let avifYuv: [OptimizeType: Int] = [
        .anime: 444, .photo: 420, .speed: 420, .quality: 444,
    ]

    static let avifAomOpts: [OptimizeType: [String]] = [
        .anime: ["-a", "end-usage=q", "-a", "cq-level=20"],
        .photo: ["-a", "end-usage=q", "-a", "cq-level=22"],
        .speed: [],
        .quality: ["-a", "end-usage=q", "-a", "cq-level=16"],
    ]

    static let webpPreset: [OptimizeType: String] = [
        .anime: "drawing", .photo: "photo", .speed: "default", .quality: "photo",
    ]

    static let webpMethod: [OptimizeType: Int] = [
        .anime: 4, .photo: 4, .speed: 0, .quality: 6,
    ]

    /// 品質 (1-100) を JPEG XL の距離に変換する。100はロスレス相当 (0)。
    static func qualityToDistance(_ quality: Int) -> Double {
        let q = min(max(quality, 1), 100)
        if q >= 100 { return 0 }
        return Double(100 - q) * 0.1
    }

    // MARK: - Argument builders (pure, testable)

    static func jpegoptimArguments(output: String, quality: Int) -> [String] {
        let dir = URL(fileURLWithPath: output, isDirectory: false).deletingLastPathComponent().path
        return ["-m\(quality)", "-o", "-d", dir, output]
    }

    static func pngoptimArguments(output: String, quality: Int) -> [String] {
        [output, "-o", output, "--quality", "\(quality)"]
    }

    static func cjxlArguments(input: String, output: String, optimizeType: OptimizeType, quality: Int, threads: Int) -> [String] {
        [
            input,
            output,
            "--distance=\(qualityToDistance(quality))",
            "-e", "\(jxlEffort[optimizeType, default: 7])",
            "--num_threads=\(threads)",
        ] + (jxlExtraOpts[optimizeType] ?? [])
    }

    static func avifencArguments(input: String, output: String, optimizeType: OptimizeType, quality: Int) -> [String] {
        [
            "--speed", "\(avifSpeed[optimizeType, default: 6])",
            "-q", "\(quality)",
            "-y", "\(avifYuv[optimizeType, default: 420])",
        ] + (avifAomOpts[optimizeType] ?? []) + [input, output]
    }

    static func cwebpArguments(input: String, output: String, optimizeType: OptimizeType, quality: Int) -> [String] {
        [
            "-preset", webpPreset[optimizeType, default: "default"],
            "-q", "\(quality)",
            "-m", "\(webpMethod[optimizeType, default: 4])",
            "-mt",
            input,
            "-o",
            output,
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
            try await runBinary(bin, args: Self.cjxlArguments(
                input: input.path, output: output.path,
                optimizeType: optimizeType, quality: quality, threads: threads
            ), workingDirectory: bin.deletingLastPathComponent().path)
        case .av1:
            let bin = paths.avifencBinURL
            try await runBinary(bin, args: Self.avifencArguments(
                input: input.path, output: output.path,
                optimizeType: optimizeType, quality: quality
            ), workingDirectory: bin.deletingLastPathComponent().path)
        case .webp:
            let bin = paths.cwebpBinURL
            try await runBinary(bin, args: Self.cwebpArguments(
                input: input.path, output: output.path,
                optimizeType: optimizeType, quality: quality
            ), workingDirectory: bin.deletingLastPathComponent().path)
        }
    }

    private func runBinary(_ bin: URL, args: [String], workingDirectory: String) async throws {
        guard FileManager.default.fileExists(atPath: bin.path) else {
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
            try await runBinary(bin, args: Self.jpegoptimArguments(output: output.path, quality: quality),
                                workingDirectory: bin.deletingLastPathComponent().path)
        } catch {
            // フォールバック：指定品質で再エンコードする。
            try Self.convertToJPEG(input: output, output: output, quality: Double(quality) / 100.0)
        }
    }

    private func compressPng(input: URL, output: URL, optimizeType: OptimizeType, paths: AppPaths) async throws {
        let quality = Self.pngQuality[optimizeType, default: 80]
        try Self.convertToPNG(input: input, output: output)
        do {
            let bin = paths.pngoptimBinURL
            try await runBinary(bin, args: Self.pngoptimArguments(output: output.path, quality: quality),
                                workingDirectory: bin.deletingLastPathComponent().path)
        } catch {
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
