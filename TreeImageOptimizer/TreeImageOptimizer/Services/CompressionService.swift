import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 1ファイル分のエンコーダ設定。
/// 固定モードは最適化種別から、自動モードはコンテンツ種別と画質プリセットから組み立てる。
struct CompressionProfile: Sendable, Equatable {
    /// JPEG XL の距離、AV1 / WebP の `-q` に使う品質。
    var quality: Int
    /// jpegoptim / pngoptim に渡す品質。
    var jpegQuality: Int
    var pngQuality: Int
    var jxlEffort: Int
    var jxlExtra: [String]
    var webpPreset: String
    var webpMethod: Int
    /// `init` は `AvifParameters` をまとめて受け取り、codec と advanced の組み合わせが
    /// 崩れないようにする。各値は既存の呼び出し・テストのため計算プロパティからも読める。
    private var avif: AvifParameters

    init(
        quality: Int,
        jpegQuality: Int,
        pngQuality: Int,
        jxlEffort: Int,
        jxlExtra: [String],
        avif: AvifParameters,
        webpPreset: String,
        webpMethod: Int
    ) {
        self.quality = quality
        self.jpegQuality = jpegQuality
        self.pngQuality = pngQuality
        self.jxlEffort = jxlEffort
        self.jxlExtra = jxlExtra
        self.avif = avif
        self.webpPreset = webpPreset
        self.webpMethod = webpMethod
    }

    var avifCodec: String { avif.codec.rawValue }
    var avifSpeed: Int { avif.speed }
    var avifYuv: Int { avif.yuv }
    var avifAdvanced: [String] { avif.advanced }
}

extension OptimizeTypeParameters {
    /// 1ファイル分のエンコーダ設定に落とし込む。
    /// JPEG / PNG の品質は最適化種別ごとの固定値だが、自動モードでは画質プリセットの
    /// 品質を使うため、両方を外から差し替えられるようにしている。
    func profile(quality: Int, lossyQuality: Int? = nil) -> CompressionProfile {
        let lossy = lossyQuality ?? jpegQuality
        return CompressionProfile(
            quality: quality,
            jpegQuality: lossy,
            pngQuality: lossyQuality ?? pngQuality,
            jxlEffort: jxlEffort,
            jxlExtra: jxlExtra,
            avif: avif,
            webpPreset: webpPreset,
            webpMethod: webpMethod
        )
    }
}

/// 画像圧縮実行。Flutter版 `CompressionService` に対応する。
/// 最適化種別ごとのパラメータは `docs/design/feature/convert-flow/compression.md` 通り。
struct CompressionService: Sendable {
    let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: - Tables

    /// 最適化種別ごとのパラメータ。値は実測で決めたもので、`OptimizeType` の追加は
    /// この1か所だけで済む（ADR 0061）。
    /// AVIF の値の根拠は ADR 0037（エンコーダ振り分け）と ADR 0040（速度とクオリティ）。
    static let parameters: [OptimizeType: OptimizeTypeParameters] = [
        .anime: OptimizeTypeParameters(
            jpegQuality: 75,
            pngQuality: 75,
            jxlEffort: 7,
            jxlExtra: ["--lossless_jpeg=0"],
            // 4:4:4 を指定するため libaom を使う。`cq-level` はサイズ増を抑えるため
            // 20→22 に上げた（VMAF は実測で不変。ADR 0040）。
            avif: AvifParameters(
                codec: .aom, speed: 3, yuv: 444,
                advanced: ["-a", "end-usage=q", "-a", "cq-level=22"]),
            webpPreset: "drawing",
            webpMethod: 4
        ),
        .photo: OptimizeTypeParameters(
            jpegQuality: 80,
            pngQuality: 80,
            jxlEffort: 7,
            jxlExtra: ["--lossless_jpeg=0"],
            // SVT-AV1 は 4:2:0 のみ。`--speed` は 4→6 に上げて2.9倍速くし、
            // 増えたサイズを `crf` 11→12 で抑えた（ADR 0040）。
            avif: AvifParameters(
                codec: .svt, speed: 6, yuv: 420,
                advanced: ["-a", "crf=12"]),
            webpPreset: "photo",
            webpMethod: 4
        ),
        .speed: OptimizeTypeParameters(
            jpegQuality: 60,
            pngQuality: 60,
            jxlEffort: 7,
            jxlExtra: ["--lossless_jpeg=0"],
            // 品質は advanced option を渡さず `-q` に従わせるため、advanced は空。
            avif: AvifParameters(codec: .svt, speed: 8, yuv: 420, advanced: []),
            webpPreset: "default",
            webpMethod: 0
        ),
        .quality: OptimizeTypeParameters(
            jpegQuality: 95,
            pngQuality: 95,
            jxlEffort: 9,
            jxlExtra: ["--lossless_jpeg=0"],
            // 4:4:4 のため libaom。`--speed` は画質優先で据え置き（ADR 0040）。
            avif: AvifParameters(
                codec: .aom, speed: 4, yuv: 444,
                advanced: ["-a", "end-usage=q", "-a", "cq-level=18"]),
            webpPreset: "photo",
            webpMethod: 6
        )
    ]

    /// 自動モードでコンテンツ種別から選ぶ AVIF のエンコーダ本体。
    /// 実写は SVT-AV1（4:2:0）、それ以外は libaom（4:4:4）で、固定モードと同じ対応。
    /// `--speed` は画質プリセットごとに変わるため、コンテンツ種別が決めるのは
    /// エンコーダとクロマサブサンプリングと advanced option だけ。
    static let autoAvif: [ContentType: AvifParameters] = [
        .anime: AvifParameters(codec: .aom, speed: 0, yuv: 444, advanced: ["-a", "end-usage=q"]),
        .photo: AvifParameters(codec: .svt, speed: 0, yuv: 420, advanced: [])
    ]

    /// 自動モードでコンテンツ種別から選ぶ WebP のプリセット。
    static let autoWebpPreset: [ContentType: String] = [
        .anime: "drawing",
        .photo: "photo"
    ]

    // MARK: - Profiles

    /// 最適化種別のパラメータ。`OptimizeType` は `CaseIterable` なので網羅されており、
    /// Why not `default:` でフォールバックするか: 表の漏れを既定値で隠さず、
    /// 新 case の追加時にここで気づけるようにするため。
    static func params(_ optimizeType: OptimizeType) -> OptimizeTypeParameters {
        guard let parameters = parameters[optimizeType] else {
            AppLogger.shared.error("missing optimize type parameters: \(optimizeType.rawValue)")
            return Self.parameters[.anime]!
        }
        return parameters
    }

    /// 固定モードのプロファイル。従来の最適化種別の表をそのまま使う。
    static func profile(optimizeType: OptimizeType, quality: Int) -> CompressionProfile {
        params(optimizeType).profile(quality: quality)
    }

    /// 自動モードのプロファイル。品質値はプリセットを起点にBPPで補正したもの。
    /// Why not: 従来の `cq-level` / `crf` を併用すると、`-q` より優先されて
    /// 画質プリセットの変更が効かなくなるため、自動モードでは渡さない。
    static func profile(contentType: ContentType, preset: QualityPreset, quality: Int) -> CompressionProfile {
        let presetParameters = preset.parameters
        var avif = autoAvif[contentType] ?? autoAvif[.anime]!
        // 固定モードは種別ごとの実測値を使うが、自動モードは画質プリセットで速度を決める。
        avif.speed = presetParameters.avifSpeed
        return CompressionProfile(
            quality: quality,
            jpegQuality: quality,
            pngQuality: quality,
            jxlEffort: presetParameters.jxlEffort,
            jxlExtra: params(.anime).jxlExtra,
            avif: avif,
            webpPreset: autoWebpPreset[contentType] ?? "drawing",
            webpMethod: presetParameters.webpMethod
        )
    }

    /// 品質 (1-100) を JPEG XL の距離に変換する。100はロスレス相当 (0)。
    static func qualityToDistance(_ quality: Int) -> Double {
        let clamped = min(max(quality, 1), 100)
        if clamped >= 100 { return 0 }
        return Double(100 - clamped) * 0.1
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

    static func cjxlArguments(
        input: String, output: String, profile: CompressionProfile, threads: Int
    ) -> [String] {
        [
            input,
            output,
            "--distance=\(qualityToDistance(profile.quality))",
            "-e", "\(profile.jxlEffort)",
            "--num_threads=\(threads)"
        ] + profile.jxlExtra
    }

    static func cjxlArguments(
        input: String, output: String, optimizeType: OptimizeType, quality: Int, threads: Int
    ) -> [String] {
        cjxlArguments(
            input: input, output: output,
            profile: profile(optimizeType: optimizeType, quality: quality), threads: threads)
    }

    static func avifencArguments(
        input: String, output: String, profile: CompressionProfile, threads: Int
    ) -> [String] {
        [
            "-c", profile.avifCodec,
            "--speed", "\(profile.avifSpeed)",
            "-q", "\(profile.quality)",
            "-y", "\(profile.avifYuv)",
            "-j", "\(threads)"
        ] + profile.avifAdvanced + [input, output]
    }

    static func avifencArguments(
        input: String, output: String, optimizeType: OptimizeType, quality: Int, threads: Int
    ) -> [String] {
        avifencArguments(
            input: input, output: output,
            profile: profile(optimizeType: optimizeType, quality: quality), threads: threads)
    }

    static func cwebpArguments(input: String, output: String, profile: CompressionProfile) -> [String] {
        [
            "-preset", profile.webpPreset,
            "-q", "\(profile.quality)",
            "-m", "\(profile.webpMethod)",
            "-mt",
            input,
            "-o",
            output
        ]
    }

    static func cwebpArguments(input: String, output: String, optimizeType: OptimizeType, quality: Int) -> [String] {
        cwebpArguments(
            input: input, output: output,
            profile: profile(optimizeType: optimizeType, quality: quality))
    }

    // MARK: - Run

    func run(
        input: URL,
        output: URL,
        format: OutputFormat,
        profile: CompressionProfile,
        threads: Int,
        paths: AppPaths,
        source: URL? = nil
    ) async throws {
        switch format {
        case .jpeg:
            try await compressJpeg(
                input: input, output: output, profile: profile, paths: paths, source: source)
        case .png:
            try await compressPng(
                input: input, output: output, profile: profile, paths: paths, source: source)
        case .jpegXL:
            let bin = paths.cjxlBinURL
            try await runBinary(
                bin,
                args: Self.cjxlArguments(
                    input: input.path, output: output.path, profile: profile, threads: threads
                ), workingDirectory: bin.deletingLastPathComponent().path)
        case .av1:
            let bin = paths.avifencBinURL
            try await runBinary(
                bin,
                args: Self.avifencArguments(
                    input: input.path, output: output.path, profile: profile, threads: threads
                ), workingDirectory: bin.deletingLastPathComponent().path)
        case .webp:
            let bin = paths.cwebpBinURL
            try await runBinary(
                bin,
                args: Self.cwebpArguments(
                    input: input.path, output: output.path, profile: profile
                ), workingDirectory: bin.deletingLastPathComponent().path)
        }
    }

    func runBinary(_ bin: URL, args: [String], workingDirectory: String) async throws {
        guard FileManager.default.fileExists(atPath: bin.path) else {
            AppLogger.shared.error("encoder binary missing: \(bin.path)")
            throw AppError.toolMissing(bin.path)
        }
        _ = try await runner.run(bin.path, args: args, workingDirectory: workingDirectory)
    }
}
