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

    /// 常に `workers` 件が実行中であることを維持する実行方式。
    /// バッチ方式（前バッチの全完了を待つ）ではなく、1件完了のたびに次の未処理ファイルを
    /// 直ちに投入するスライディングウィンドウ方式（convert-flow.md の並列処理の単位）。
    /// - Returns: (成功件数, 失敗件数)
    static func runParallel(
        count: Int,
        workers: Int,
        operation: @Sendable @escaping (Int) async -> Bool
    ) async -> (success: Int, failure: Int) {
        let workers = max(1, workers)
        var success = 0
        var failure = 0
        var nextIndex = 0
        await withTaskGroup(of: Bool.self) { group in
            // 最初に並列数ぶん投入する。
            for _ in 0..<workers where nextIndex < count {
                let index = nextIndex
                nextIndex += 1
                group.addTask { await operation(index) }
            }
            // 結果を1件受けるたびに次の未処理を投入する。未処理が尽きたら残りを排水して終了。
            while let succeeded = await group.next() {
                if succeeded { success += 1 } else { failure += 1 }
                if nextIndex < count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask { await operation(index) }
                }
            }
        }
        return (success, failure)
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
        return await Self.runParallel(count: files.count, workers: workers) { index in
            await self.processFile(
                at: index, file: files[index], config: config,
                outputDirectory: outputDirectory, paths: paths, onOutcome: onOutcome
            )
        }
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
