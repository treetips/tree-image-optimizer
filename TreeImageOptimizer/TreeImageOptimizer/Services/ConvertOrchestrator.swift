import Foundation

/// 変換設定のスナップショット。
struct ConvertConfig: Sendable {
    var scale: Int
    var model: String
    var format: OutputFormat
    var optimizeType: OptimizeType
    var quality: Int
    var parallelCount: Int
}

/// 1ファイルの処理段階。
enum ConvertStage: Sendable {
    case upscale
    case compress
    case output
}

/// 進捗コールバックに渡す1件分の結果。
/// `started` がtrueの場合はその段階の開始（実行中表示用）。
struct FileOutcome: Sendable {
    var index: Int
    var stage: ConvertStage
    var succeeded: Bool
    var fileDone: Bool
    var started: Bool = false
}

/// 1ファイル単位でアップスケール→圧縮→出力を並列実行する。
/// Flutter版 `ConvertViewModel._processParallel/_processFile` に対応する。
struct ConvertOrchestrator: Sendable {
    let upscale: UpscaleService
    let compression: CompressionService

    init(upscale: UpscaleService = UpscaleService(), compression: CompressionService = CompressionService()) {
        self.upscale = upscale
        self.compression = compression
    }

    /// 出力ファイル名を組み立てる。拡張子直前の `.` ではなく最初の `.` で切る（Flutter版踏襲）。
    static func outputFileName(for inputName: String, format: OutputFormat) -> String {
        let base = inputName.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
            ?? inputName
        return base + format.fileExtension
    }

    /// - Returns: (成功件数, 失敗件数)
    func run(
        files: [URL],
        config: ConvertConfig,
        outputDirectory: URL,
        paths: AppPaths,
        onOutcome: @Sendable @escaping (FileOutcome) async -> Void
    ) async -> (success: Int, failure: Int) {
        let workers = max(1, min(config.parallelCount, files.count))
        var success = 0
        var failure = 0
        var start = files.startIndex
        while start < files.endIndex {
            let end = files.index(start, offsetBy: workers, limitedBy: files.endIndex) ?? files.endIndex
            let batch = Array(files[start ..< end])
            let base = start
            await withTaskGroup(of: Bool.self) { group in
                for (offset, file) in batch.enumerated() {
                    let index = base + offset
                    group.addTask {
                        await self.processFile(at: index, file: file, config: config, outputDirectory: outputDirectory, paths: paths, onOutcome: onOutcome)
                    }
                }
                for await ok in group {
                    if ok { success += 1 } else { failure += 1 }
                }
            }
            start = end
        }
        return (success, failure)
    }

    private func processFile(
        at index: Int,
        file: URL,
        config: ConvertConfig,
        outputDirectory: URL,
        paths: AppPaths,
        onOutcome: @Sendable @escaping (FileOutcome) async -> Void
    ) async -> Bool {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempDir) }
            let upscaled = tempDir.appendingPathComponent("upscaled.png", isDirectory: false)
            await onOutcome(FileOutcome(index: index, stage: .upscale, succeeded: false, fileDone: false, started: true))
            do {
                try await upscale.run(input: file, output: upscaled, scale: config.scale, model: config.model, paths: paths)
            } catch {
                await onOutcome(FileOutcome(index: index, stage: .upscale, succeeded: false, fileDone: true))
                return false
            }
            await onOutcome(FileOutcome(index: index, stage: .upscale, succeeded: true, fileDone: false))
            await onOutcome(FileOutcome(index: index, stage: .compress, succeeded: false, fileDone: false, started: true))
            let outName = Self.outputFileName(for: file.lastPathComponent, format: config.format)
            let compressed = tempDir.appendingPathComponent(outName, isDirectory: false)
            do {
                try await compression.run(
                    input: upscaled, output: compressed,
                    format: config.format, optimizeType: config.optimizeType,
                    quality: config.quality, threads: config.parallelCount, paths: paths
                )
            } catch {
                await onOutcome(FileOutcome(index: index, stage: .compress, succeeded: false, fileDone: true))
                return false
            }
            await onOutcome(FileOutcome(index: index, stage: .compress, succeeded: true, fileDone: false))
            await onOutcome(FileOutcome(index: index, stage: .output, succeeded: false, fileDone: false, started: true))
            try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let destination = outputDirectory.appendingPathComponent(outName, isDirectory: false)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: compressed, to: destination)
            await onOutcome(FileOutcome(index: index, stage: .output, succeeded: true, fileDone: true))
            return true
        } catch {
            await onOutcome(FileOutcome(index: index, stage: .output, succeeded: false, fileDone: true))
            return false
        }
    }
}
