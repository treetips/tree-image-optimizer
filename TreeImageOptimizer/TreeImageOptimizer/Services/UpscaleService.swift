import Foundation

/// アップスケール実行。Flutter版 `UpscaleService` に対応する。
struct UpscaleService: Sendable {
    let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    static func arguments(input: String, output: String, scale: Int, model: String, modelsDir: String) -> [String] {
        ["-i", input, "-o", output, "-s", "\(scale)", "-m", modelsDir, "-n", model]
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
}
