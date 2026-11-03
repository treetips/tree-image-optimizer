import Foundation

/// アップスケールワーカーが共有する入力。
struct UpscaleBatchContext: Sendable {
    var files: [URL]
    var config: ConvertConfig
    var paths: AppPaths
    var queue: UpscaledQueue
    var onOutcome: @Sendable (FileOutcome) async -> Void
}

/// 圧縮ワーカーが共有する入力。
struct CompressionContext: Sendable {
    var config: ConvertConfig
    var encoderThreads: Int
    var outputDirectory: URL
    var paths: AppPaths
    var onOutcome: @Sendable (FileOutcome) async -> Void
}

extension ConvertOrchestrator {

    /// バッチを処理するアップスケールワーカー。1プロセスで複数ファイルを処理する。
    func upscaleWorker(batcher: FileBatcher, context: UpscaleBatchContext) async -> RunCounts {
        var total = RunCounts()
        while let range = await batcher.next() {
            let counts = await processBatch(range: range, context: context)
            total.merge(counts)
        }
        return total
    }

    /// 1バッチ分を1プロセスでアップスケールし、成功したファイルだけキューへ流す。
    /// プロセスが失敗しても、出力が揃っているファイルは成功として扱う。
    private func processBatch(range: Range<Int>, context: UpscaleBatchContext) async -> RunCounts {
        let fileManager = FileManager.default
        let batchRoot = fileManager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        let inputDirectory = batchRoot.appendingPathComponent("in", isDirectory: true)
        let outputDirectory = batchRoot.appendingPathComponent("out", isDirectory: true)

        do {
            try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            var counts = RunCounts()
            for index in range {
                await context.onOutcome(
                    FileOutcome(index: index, stage: .upscale, succeeded: false, fileDone: true))
                counts.failure += 1
            }
            return counts
        }
        defer { try? fileManager.removeItem(at: batchRoot) }

        let prepared = await prepareBatch(
            range: range, inputDirectory: inputDirectory, outputDirectory: outputDirectory,
            context: context)
        guard !prepared.prepared.isEmpty else { return prepared.counts }

        // 失敗しても部分的な出力が残ることがあるため、ここでは投げずに後段でファイル単位に検証する。
        try? await runUpscaleBatch(
            inputDirectory: inputDirectory, outputDirectory: outputDirectory,
            config: context.config, paths: context.paths)

        let finished = await enqueuePrepared(prepared.prepared, context: context)
        var result = prepared.counts
        result.merge(finished)
        return result
    }

    /// バッチの入力ディレクトリを作り、元ファイルを連番で持ち込む。
    private func prepareBatch(
        range: Range<Int>,
        inputDirectory: URL,
        outputDirectory: URL,
        context: UpscaleBatchContext
    ) async -> (prepared: [PreparedBatchItem], counts: RunCounts) {
        var prepared: [PreparedBatchItem] = []
        var counts = RunCounts()
        for index in range {
            let file = context.files[index]
            let name = String(format: "%04d.png", index)
            let input = inputDirectory.appendingPathComponent(name, isDirectory: false)
            do {
                try Self.linkOrCopy(file, to: input)
            } catch {
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
        context: UpscaleBatchContext
    ) async -> RunCounts {
        let fileManager = FileManager.default
        // Real-CUGANはモデル側の倍率で出力するため、検証もモデルの倍率に合わせる。
        let expectedScale =
            context.config.engine == .realCUGAN
            ? (context.config.realCuganModel?.scale ?? context.config.scale)
            : context.config.scale
        var counts = RunCounts()

        for item in prepared {
            guard
                (try? upscale.postVerify(output: item.output, input: item.file, scale: expectedScale)) != nil
            else {
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: .upscale, succeeded: false, fileDone: true))
                counts.failure += 1
                continue
            }
            do {
                let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)
                try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
                let upscaled = tempDirectory.appendingPathComponent("upscaled.png", isDirectory: false)
                try fileManager.moveItem(at: item.output, to: upscaled)
                await context.onOutcome(
                    FileOutcome(index: item.index, stage: .upscale, succeeded: true, fileDone: false))
                await context.queue.push(
                    UpscaledItem(
                        index: item.index, upscaled: upscaled, tempDirectory: tempDirectory,
                        outputName: Self.outputFileName(
                            for: item.file.lastPathComponent, format: context.config.format)))
            } catch {
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
                    format: context.config.format, optimizeType: context.config.optimizeType,
                    quality: context.config.quality, threads: context.encoderThreads, paths: context.paths)
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
            } catch {
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
        config: ConvertConfig,
        paths: AppPaths
    ) async throws {
        if config.engine == .realCUGAN, let realCuganModel = config.realCuganModel {
            try await upscale.runRealCUGANDirectory(
                inputDirectory: inputDirectory, outputDirectory: outputDirectory,
                model: realCuganModel, paths: paths)
            return
        }
        try await upscale.runDirectory(
            inputDirectory: inputDirectory, outputDirectory: outputDirectory,
            scale: config.scale, model: config.model, paths: paths)
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
}

/// アップスケール済みファイルを圧縮ワーカーへ渡すキュー。
/// 複数ワーカーが待機できるよう、要素が無いときはcontinuationで待たせる。
actor UpscaledQueue {
    private var items: [UpscaledItem] = []
    private var waiters: [CheckedContinuation<UpscaledItem?, Never>] = []
    private var finished = false

    func push(_ item: UpscaledItem) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: item)
            return
        }
        items.append(item)
    }

    func finish() {
        finished = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: nil)
        }
    }

    func next() async -> UpscaledItem? {
        if !items.isEmpty {
            return items.removeFirst()
        }
        if finished {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

/// 次に処理するファイル範囲を配る。処理枠（並列数）を超えないようにする。
///
/// スロットは `release` で返す。アップスケールの完了では返さないため、
/// 「1ファイルの出力が終わるまで次のファイルを開始しない」が守られる（ADR 0038）。
actor FileBatcher {
    private let count: Int
    private let batchSize: Int
    private let capacity: Int
    private var nextIndex = 0
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int, batchSize: Int, capacity: Int) {
        self.count = count
        self.batchSize = max(1, batchSize)
        self.capacity = max(1, capacity)
    }

    /// 空き枠の数だけ次のバッチ範囲を返す。空きが1件も無いと空きが出来るまで待つ。
    /// ファイルが尽きたら nil を返す。
    /// Why not: 必ず `batchSize` 件そろえると空き1件で次が始まらないため、
    /// 「1件完了ごとに次を開始する」を満たせない。
    func next() async -> Range<Int>? {
        guard nextIndex < count else { return nil }
        while inFlight >= capacity {
            await withCheckedContinuation { waiters.append($0) }
        }
        let take = min(batchSize, capacity - inFlight, count - nextIndex)
        let range = nextIndex..<(nextIndex + take)
        nextIndex += take
        inFlight += take
        return range
    }

    /// 出力が完了したファイルの分だけ処理枠を返す。
    func release(_ files: Int = 1) {
        inFlight = max(0, inFlight - files)
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

struct UpscaledItem: Sendable {
    var index: Int
    var upscaled: URL
    var tempDirectory: URL
    var outputName: String
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
