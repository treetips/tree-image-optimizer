import Foundation

/// 同一の倍率・縮小先でまとめたファイル群。バッチはこの単位をまたがない。
struct UpscaleGroup: Sendable {
    /// 超解像の倍率。`nil` は超解像をかけない（リサイズのみ、またはそのまま）。
    var scale: Int?
    /// 出力の目標長辺。`nil` はリサイズしない。
    var resizeLongEdge: Int?
    /// Real-CUGANのモデル。倍率に合うものが選ばれている。
    var model: RealCUGANModel?
    var indices: [Int]
}

/// グループ分けのキー。倍率と縮小先が同じファイルだけを同じバッチにする。
struct UpscaleGroupKey: Hashable, Sendable {
    var scale: Int?
    var resizeLongEdge: Int?
}

/// ワーカーが受け取る1バッチ分の処理。
struct UpscaleBatch: Sendable {
    var scale: Int?
    var resizeLongEdge: Int?
    var model: RealCUGANModel?
    var indices: [Int]
}

/// アップスケールワーカーが共有する入力。
struct UpscaleBatchContext: Sendable {
    var files: [URL]
    var plans: [FilePlan]
    var config: ConvertConfig
    var paths: AppPaths
    var queue: UpscaledQueue
    var control: RunControl
    var onOutcome: @Sendable (FileOutcome) async -> Void
}

/// 圧縮ワーカーが共有する入力。
struct CompressionContext: Sendable {
    var config: ConvertConfig
    var encoderThreads: Int
    var outputDirectory: URL
    var paths: AppPaths
    var control: RunControl
    var onOutcome: @Sendable (FileOutcome) async -> Void
}

extension ConvertOrchestrator {

    /// バッチを処理するアップスケールワーカー。1プロセスで複数ファイルを処理する。
    func upscaleWorker(scheduler: BatchScheduler, context: UpscaleBatchContext) async -> RunCounts {
        var total = RunCounts()
        while let batch = await scheduler.next() {
            let counts = await processBatch(batch: batch, context: context)
            total.merge(counts)
        }
        return total
    }

    /// 1バッチ分を1プロセスでアップスケールし、成功したファイルだけキューへ流す。
    /// プロセスが失敗しても、出力が揃っているファイルは成功として扱う。
    private func processBatch(batch: UpscaleBatch, context: UpscaleBatchContext) async -> RunCounts {
        guard let scale = batch.scale else {
            return await processResizeOnlyBatch(batch: batch, context: context)
        }
        let fileManager = FileManager.default
        let batchRoot = fileManager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        let inputDirectory = batchRoot.appendingPathComponent("in", isDirectory: true)
        let outputDirectory = batchRoot.appendingPathComponent("out", isDirectory: true)

        do {
            try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.error(
                """
                upscale batch: failed to create temp directories under \(batchRoot.path): \
                \(error.localizedDescription)
                """)
            var counts = RunCounts()
            for index in batch.indices {
                await context.onOutcome(
                    FileOutcome(index: index, stage: .upscale, succeeded: false, fileDone: true))
                counts.failure += 1
            }
            return counts
        }
        defer { try? fileManager.removeItem(at: batchRoot) }

        let prepared = await prepareBatch(
            batch: batch, inputDirectory: inputDirectory, outputDirectory: outputDirectory,
            context: context)
        guard !prepared.prepared.isEmpty else { return prepared.counts }
        // キャンセル直後にバッチを受け取ったワーカーが、新しい超解像プロセスを起動しないようにする。
        // 起動してしまうとキャンセルがバッチ1回分（数分）遅れる（ADR 0054）。
        if await context.control.isCancelled { return prepared.counts }

        // 失敗しても部分的な出力が残ることがあるため、ここでは投げずに後段でファイル単位に検証する。
        do {
            try await runUpscaleBatch(
                inputDirectory: inputDirectory, outputDirectory: outputDirectory,
                batch: batch, scale: scale, config: context.config, paths: context.paths)
        } catch is CancellationError {
            // タスクキャンセルで止めたプロセスの失敗は失敗件数に数えない。
            return prepared.counts
        } catch {
            // キャンセルで止めたプロセスの失敗は失敗件数に数えない。
            // 行は呼び出し側が「キャンセル」として表示する（ADR 0054）。
            if await context.control.isCancelled {
                return prepared.counts
            }
            AppLogger.shared.error(
                "upscale batch: process failed (continuing per-file verification): \(error.localizedDescription)")
        }

        let finished = await enqueuePrepared(prepared.prepared, batch: batch, context: context)
        var result = prepared.counts
        result.merge(finished)
        return result
    }

    /// 超解像をかけないバッチを圧縮キューへ流す。目標が近い場合はここでリサイズする。
    /// Why not: 1.2倍程度の拡大に超解像モデルを使うと、中間画像だけが巨大になり
    /// 画質差も小さいため、高品質リサイズで目標ちょうどに合わせる（ADR 0049）。
    private func processResizeOnlyBatch(
        batch: UpscaleBatch,
        context: UpscaleBatchContext
    ) async -> RunCounts {
        let fileManager = FileManager.default
        var counts = RunCounts()
        for index in batch.indices {
            // バッチの途中でキャンセルされたら、残りのファイルは開始しない。
            if await context.control.isCancelled { return counts }
            let file = context.files[index]
            await context.onOutcome(
                FileOutcome(index: index, stage: .upscale, succeeded: false, fileDone: false, started: true))
            do {
                let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)
                try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
                let upscaled = tempDirectory.appendingPathComponent("upscaled.png", isDirectory: false)
                if let longEdge = batch.resizeLongEdge {
                    try ImageResizer.resize(input: file, output: upscaled, longEdge: longEdge)
                } else {
                    try Self.stageFile(file, to: upscaled)
                }
                await context.onOutcome(
                    FileOutcome(index: index, stage: .upscale, succeeded: true, fileDone: false))
                await context.queue.push(
                    UpscaledItem(
                        index: index, upscaled: upscaled, tempDirectory: tempDirectory,
                        outputName: Self.outputFileName(
                            for: file.lastPathComponent, format: context.config.format),
                        quality: context.plans[index].quality,
                        source: file))
            } catch {
                AppLogger.shared.error(
                    "upscale skip: failed for \(file.path): \(error.localizedDescription)")
                await context.onOutcome(
                    FileOutcome(index: index, stage: .upscale, succeeded: false, fileDone: true))
                counts.failure += 1
            }
        }
        return counts
    }

    /// バッチの入力ディレクトリを作り、元ファイルを連番で持ち込む。
    private func prepareBatch(
        batch: UpscaleBatch,
        inputDirectory: URL,
        outputDirectory: URL,
        context: UpscaleBatchContext
    ) async -> (prepared: [PreparedBatchItem], counts: RunCounts) {
        var prepared: [PreparedBatchItem] = []
        var counts = RunCounts()
        for index in batch.indices {
            let file = context.files[index]
            let name = String(format: "%04d.png", index)
            let input = inputDirectory.appendingPathComponent(name, isDirectory: false)
            do {
                try Self.stageFile(file, to: input)
            } catch {
                AppLogger.shared.error(
                    "upscale batch: failed to stage \(file.path) -> \(input.path): \(error.localizedDescription)")
                await context.onOutcome(
                    FileOutcome(index: index, stage: .upscale, succeeded: false, fileDone: true))
                counts.failure += 1
                continue
            }
            await context.onOutcome(
                FileOutcome(index: index, stage: .upscale, succeeded: false, fileDone: false, started: true))
            prepared.append(
                PreparedBatchItem(
                    index: index, file: file,
                    output: outputDirectory.appendingPathComponent(name, isDirectory: false)))
        }
        return (prepared, counts)
    }

    /// 出力をファイル単位で検証し、成功したものだけを圧縮キューへ流す。
    private func enqueuePrepared(
        _ prepared: [PreparedBatchItem],
        batch: UpscaleBatch,
        context: UpscaleBatchContext
    ) async -> RunCounts {
        let fileManager = FileManager.default
        // Real-CUGANはモデル側の倍率で出力するため、検証もモデルの倍率に合わせる。
        let expectedScale = batch.model?.scale ?? batch.scale ?? context.config.scale
        var counts = RunCounts()

        for item in prepared {
            // キャンセル後は後段のキューへ積まない。残りは呼び出し側が片付ける。
            if await context.control.isCancelled { return counts }
            guard
                (try? upscale.postVerify(output: item.output, input: item.file, scale: expectedScale)) != nil
            else {
                AppLogger.shared.error(
                    "upscale batch: output verification failed file=\(item.file.path) output=\(item.output.path)")
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: .upscale, succeeded: false, fileDone: true))
                counts.failure += 1
                continue
            }
            var tempDirectory: URL?
            do {
                let directory = fileManager.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)
                tempDirectory = directory
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let upscaled = directory.appendingPathComponent("upscaled.png", isDirectory: false)
                // 目標を超えた出力は、ファイルサイズを抑えるため目標長辺へ縮小する。
                let longEdge = batch.resizeLongEdge
                let needsResize =
                    longEdge.map { edge in
                        guard let dimensions = UpscaleService.imageDimensions(of: item.output)
                        else { return false }
                        return max(dimensions.width, dimensions.height) > edge
                    } ?? false
                if needsResize, let longEdge {
                    try ImageResizer.resize(input: item.output, output: upscaled, longEdge: longEdge)
                    try? fileManager.removeItem(at: item.output)
                } else {
                    try fileManager.moveItem(at: item.output, to: upscaled)
                }
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: .upscale, succeeded: true, fileDone: false))
                await context.queue.push(
                    UpscaledItem(
                        index: item.index, upscaled: upscaled, tempDirectory: directory,
                        outputName: Self.outputFileName(
                            for: item.file.lastPathComponent, format: context.config.format),
                        quality: context.plans[item.index].quality,
                        source: item.file))
            } catch {
                if let tempDirectory { try? fileManager.removeItem(at: tempDirectory) }
                AppLogger.shared.error(
                    "upscale batch: failed to enqueue \(item.file.path): \(error.localizedDescription)")
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: .upscale, succeeded: false, fileDone: true))
                counts.failure += 1
            }
        }
        return counts
    }

    /// 圧縮・出力を担当するCPUワーカー。ファイル完了ごとに集計を返す。
    func compressionWorker(queue: UpscaledQueue, context: CompressionContext) async -> RunCounts {
        let fileManager = FileManager.default
        var counts = RunCounts()
        while let item = await queue.next() {
            var stage = ConvertStage.compress
            do {
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: .compress, succeeded: false, fileDone: false, started: true))
                let compressed = item.tempDirectory.appendingPathComponent(
                    item.outputName, isDirectory: false)
                try await compression.run(
                    input: item.upscaled, output: compressed,
                    format: context.config.format,
                    profile: Self.compressionProfile(
                        config: context.config, quality: item.quality),
                    threads: context.encoderThreads, paths: context.paths,
                    source: item.source)
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: .compress, succeeded: true, fileDone: false))
                stage = .output
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: .output, succeeded: false, fileDone: false, started: true))
                try Self.installOutput(
                    from: compressed,
                    to: context.outputDirectory.appendingPathComponent(item.outputName, isDirectory: false))
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: .output, succeeded: true, fileDone: true))
                counts.success += 1
            } catch is CancellationError {
                // タスクキャンセルで止めた圧縮・出力は失敗に数えず、このワーカーを終える（ADR 0054）。
                try? fileManager.removeItem(at: item.tempDirectory)
                break
            } catch {
                // キャンセルで止めた圧縮・出力は失敗に数えず、このワーカーを終える（ADR 0054）。
                if await context.control.isCancelled {
                    try? fileManager.removeItem(at: item.tempDirectory)
                    break
                }
                AppLogger.shared.error(
                    """
                    compress/output: failed at \(stage) file=\(item.upscaled.path) \
                    output=\(item.outputName): \(error.localizedDescription)
                    """)
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: stage, succeeded: false, fileDone: true))
                counts.failure += 1
            }
            try? fileManager.removeItem(at: item.tempDirectory)
        }
        return counts
    }

    /// エンジンに応じたアップスケールの実行。Real-CUGANはモデル指定が必須で、
    /// 無ければ従来の `upscayl-bin` へフォールバックする。
    private func runUpscaleBatch(
        inputDirectory: URL,
        outputDirectory: URL,
        batch: UpscaleBatch,
        scale: Int,
        config: ConvertConfig,
        paths: AppPaths
    ) async throws {
        // 自動モードでは倍率ごとに合うReal-CUGANモデルがバッチへ入っている。
        if let model = batch.model {
            try await upscale.runRealCUGANDirectory(
                inputDirectory: inputDirectory, outputDirectory: outputDirectory,
                model: model, paths: paths)
            return
        }
        try await upscale.runDirectory(
            inputDirectory: inputDirectory, outputDirectory: outputDirectory,
            scale: scale, model: config.model, paths: paths)
    }

    /// モードに応じた圧縮プロファイル。自動モードは品質をファイルごとに補正済み。
    static func compressionProfile(config: ConvertConfig, quality: Int) -> CompressionProfile {
        switch config.mode {
        case .fixed:
            return CompressionService.profile(optimizeType: config.optimizeType, quality: quality)
        case .auto:
            return CompressionService.profile(
                contentType: config.contentType, preset: config.qualityPreset, quality: quality)
        }
    }

    /// 一時入力ディレクトリへ元ファイルを持ち込む。同一ボリュームならhard linkで
    /// コピーせず、異なるボリュームのときだけコピーする。
    /// シンボリックリンクは upscayl-bin のディレクトリ走査で無視されるため使わない。
    private static func linkOrCopy(_ source: URL, to destination: URL) throws {
        do {
            try FileManager.default.linkItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    /// アップスケールのステージング。HEIF/AVIF は外部ツールが読めないため、
    /// 先頭フレームをPNGへデコードしてから持ち込む（ADR 0069）。
    /// Why not デコードだけして通すか: デコードは先頭フレームしか取り出さないため、
    /// アニメーション（イメージシーケンス）を黙って1枚に潰して成功扱いにしてしまう。
    /// 超解像をかけない経路では `postVerify` のフレーム数検査も通らないので、ここで落とす。
    private static func stageFile(_ source: URL, to destination: URL) throws {
        guard TargetFiles.needsDecodeToPNG(source) else {
            try linkOrCopy(source, to: destination)
            return
        }
        guard let frames = UpscaleService.imageFrameCount(of: source), frames == 1 else {
            throw AppError.verificationFailed(
                "input is multi-frame, still images only: \(source.path)")
        }
        try CompressionService.convertToPNG(input: source, output: destination)
    }
}

private struct PreparedBatchItem: Sendable {
    var index: Int
    var file: URL
    var output: URL
}

struct RunCounts: Sendable {
    var success = 0
    var failure = 0

    mutating func merge(_ other: RunCounts) {
        success += other.success
        failure += other.failure
    }
}
