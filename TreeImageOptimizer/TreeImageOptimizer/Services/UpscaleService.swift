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
    func postVerify(output: URL, input: URL, scale: Int) throws {
        let fm = FileManager.default
        guard let inputDims = Self.imageDimensions(of: input) else {
            throw AppError.verificationFailed("input is not readable image: \(input.path)")
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
    static func imageDimensions(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
