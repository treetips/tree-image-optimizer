import CoreGraphics
import Foundation
import ImageIO

/// アップスケール実行。Flutter版 `UpscaleService` に対応する。
/// エンジンごとに `upscayl-bin` / `realcugan-ncnn-vulkan` へ処理を振り分ける。
/// Real-CUGANは実行前後の検証を行う。モデル不在時に終了コード0で黒画像を
/// 出力するバイナリ挙動を成功扱いにしないためである。
struct UpscaleService: Sendable {
    let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    static func arguments(input: String, output: String, scale: Int, model: String, modelsDir: String) -> [String] {
        ["-i", input, "-o", output, "-s", "\(scale)", "-m", modelsDir, "-n", model]
    }

    /// `realcugan-ncnn-vulkan` の引数。`-n` はモデルから導出したノイズレベル。
    static func realCuganArguments(
        input: String, output: String, scale: Int, noise: Int, modelsDir: String
    ) -> [String] {
        ["-i", input, "-o", output, "-s", "\(scale)", "-n", "\(noise)", "-m", modelsDir]
    }

    func run(input: URL, output: URL, scale: Int, model: String, paths: AppPaths) async throws {
        let bin = paths.upscalBinURL.path
        guard FileManager.default.fileExists(atPath: bin) else {
            throw AppError.toolMissing(bin)
        }
        _ = try await runner.run(
            bin,
            args: Self.arguments(
                input: input.path,
                output: output.path,
                scale: scale,
                model: model,
                modelsDir: paths.upscalModelsURL.path
            ),
            workingDirectory: paths.upscalBinURL.deletingLastPathComponent().path
        )
    }

    /// ディレクトリ内の画像を1プロセスでまとめてアップスケールする。
    /// モデル読み込みとMoltenVK初期化をファイルごとに繰り返さないため、
    /// 小さな画像が連続するときに固定費を削れる（ADR 0035）。
    func runDirectory(
        inputDirectory: URL, outputDirectory: URL, scale: Int, model: String, paths: AppPaths
    ) async throws {
        let bin = paths.upscalBinURL.path
        guard FileManager.default.fileExists(atPath: bin) else {
            throw AppError.toolMissing(bin)
        }
        _ = try await runner.run(
            bin,
            args: Self.arguments(
                input: inputDirectory.path,
                output: outputDirectory.path,
                scale: scale,
                model: model,
                modelsDir: paths.upscalModelsURL.path
            ),
            workingDirectory: paths.upscalBinURL.deletingLastPathComponent().path
        )
    }

    /// Real-CUGANでアップスケールする。実行前に `.param`/`.bin` の存在を確認し、
    /// 実行後に出力の存在・寸法を検証する。
    func runRealCUGAN(input: URL, output: URL, model: RealCUGANModel, paths: AppPaths) async throws {
        let bin = paths.realCuganBinURL.path
        guard FileManager.default.fileExists(atPath: bin) else {
            throw AppError.toolMissing(bin)
        }
        let modelsDir = paths.realCuganRootURL.appendingPathComponent(
            model.folder, isDirectory: true)
        try preflight(model: model, modelsDir: modelsDir)
        _ = try await runner.run(
            bin,
            args: Self.realCuganArguments(
                input: input.path,
                output: output.path,
                scale: model.scale,
                noise: model.noise,
                modelsDir: modelsDir.path
            ),
            workingDirectory: paths.realCuganBinURL.deletingLastPathComponent().path
        )
        try postVerify(output: output, input: input, scale: model.scale)
    }

    /// ディレクトリ内の画像を1プロセスでまとめてアップスケールする。
    /// モデルの事前検証は1回で済む。出力の検証は呼び出し側がファイル単位で行う。
    func runRealCUGANDirectory(
        inputDirectory: URL, outputDirectory: URL, model: RealCUGANModel, paths: AppPaths
    ) async throws {
        let bin = paths.realCuganBinURL.path
        guard FileManager.default.fileExists(atPath: bin) else {
            throw AppError.toolMissing(bin)
        }
        let modelsDir = paths.realCuganRootURL.appendingPathComponent(
            model.folder, isDirectory: true)
        try preflight(model: model, modelsDir: modelsDir)
        _ = try await runner.run(
            bin,
            args: Self.realCuganArguments(
                input: inputDirectory.path,
                output: outputDirectory.path,
                scale: model.scale,
                noise: model.noise,
                modelsDir: modelsDir.path
            ),
            workingDirectory: paths.realCuganBinURL.deletingLastPathComponent().path
        )
    }

    /// 実行前検証。対象モデルの `.param` と `.bin` が揃っていること。
    /// どちらかが欠けてもバイナリは失敗せず黒画像を生成するため、事前に落とす。
    func preflight(model: RealCUGANModel, modelsDir: URL) throws {
        let fm = FileManager.default
        for suffix in ["param", "bin"] {
            let url = modelsDir.appendingPathComponent("\(model.name).\(suffix)", isDirectory: false)
            guard fm.fileExists(atPath: url.path) else {
                throw AppError.fileNotFound(url.path)
            }
        }
    }

    /// 実行後検証。出力が存在しサイズが0より大きく、寸法が入力のscale倍であること。
    ///
    /// ここでの「寸法」は**総フレーム数と先頭フレーム**を見る。
    /// 前提: 入力は静止画1枚（`TargetFiles.supportedExtensions` の jpg/jpeg/png/webp）。
    /// `realcugan-ncnn-vulkan` と `upscayl-bin` はマルチフレーム（GIF/APNG/HEIF）を
    /// アニメーションとして扱わず静止画として読み出すため、対応外としている。
    ///
    /// 静止画専用と割り切る理由（ADR 0063）:
    /// 全フレームを検証するには、各フレームを `CGImageSourceCreateImageAtIndex` で
    /// デコードして比較する必要があり、対象ファイルが数千枚になる一括変換では
    /// アップスケール本体より検証のI/OとCPUが高くつく。現状は入力フィルタで
    /// アニメーションを通さないため、先頭フレーム＋総フレーム数の検査で
    /// 「モデル不在による黒画像」という検出したい失敗は十分に捕らえられる。
    ///
    /// Why not `CGImageSourceCopyPropertiesAtIndex(source, 0, nil)` だけで済ませるか:
    /// index 0 が読めれば総フレーム数に関わらず検証が通ってしまい、
    /// マルチフレーム入力が紛れたときに黙って見逃す。総フレーム数も見て
    /// 前提が崩れたことを明示的に失敗にする。
    func postVerify(output: URL, input: URL, scale: Int) throws {
        let fm = FileManager.default
        guard let inputFrames = Self.imageFrameCount(of: input), inputFrames > 0,
            let inputDims = Self.imageDimensions(of: input)
        else {
            throw AppError.verificationFailed("input is not readable image: \(input.path)")
        }
        // マルチフレーム入力は静止画専用の前提から外れるため検証で落とす。
        // Why not そのまま通すか: 先頭フレームだけ見ると2枚目以降が正しく
        // 処理されていなくても成功扱いになり、前提が崩れていることに気づけない。
        guard inputFrames == 1 else {
            throw AppError.verificationFailed(
                "input is multi-frame (\(inputFrames) frames), still images only: \(input.path)")
        }
        let expectedWidth = inputDims.width * scale
        let expectedHeight = inputDims.height * scale
        // Why not: `attributesOfItem` は欠損時にCocoaErrorを投げるため、
        // 非throwな存在チェックでAppErrorに正規化する。
        guard
            fm.fileExists(atPath: output.path),
            fm.isReadableFile(atPath: output.path),
            let attrs = try? fm.attributesOfItem(atPath: output.path),
            let size = (attrs[.size] as? NSNumber)?.intValue,
            size > 0
        else {
            throw AppError.verificationFailed("upscaled file is missing or empty: \(output.path)")
        }
        guard let dims = Self.imageDimensions(of: output) else {
            throw AppError.verificationFailed("upscaled file is not readable image: \(output.path)")
        }
        guard dims.width == expectedWidth, dims.height == expectedHeight else {
            throw AppError.verificationFailed(
                """
                upscaled dimensions mismatch: expected \
                \(expectedWidth)x\(expectedHeight), got \(dims.width)x\(dims.height)
                """)
        }
    }

    /// PNG等の寸法を `CGImageSource` で読む。失敗時はnil。
    /// index 0（先頭フレーム）の寸法を返す。
    static func imageDimensions(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return Self.dimensions(at: 0, of: source)
    }

    /// 画像の総フレーム数。`CGImageSourceGetCount` が使えない形式はnil。
    /// 静止画は1、アニメーションGIF/APNGは2以上になる。
    static func imageFrameCount(of url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        // Why not 0をそのまま返すか: デコードできない画像を「フレーム数0の正常な
        // 画像」として扱うと、後段が0枚の画像を圧縮に回してしまう。
        return count > 0 ? count : nil
    }

    private static func dimensions(at index: Int, of source: CGImageSource) -> (width: Int, height: Int)? {
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
