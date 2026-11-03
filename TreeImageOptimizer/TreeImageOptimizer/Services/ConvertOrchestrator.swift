import Foundation

/// 変換設定のスナップショット。
struct ConvertConfig: Sendable {
    var scale: Int
    var model: String
    var format: OutputFormat
    var optimizeType: OptimizeType
    var quality: Int
    var parallelCount: Int
    /// アップスケーラーのエンジン。既定は従来の `upscayl-bin`。
    var engine: UpscaleEngine = .upscayl
    /// Real-CUGAN選択時のモデル。`model` はエンジン側のID（`models-se/...`）を持つ。
    var realCuganModel: RealCUGANModel? = nil
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

/// ステージ別ワーカー数。GPU側のアップスケールとCPU側の圧縮を分けて動かす。
struct StageWorkers: Sendable, Equatable {
    var upscale: Int
    var compression: Int
}

/// 1ファイル単位でアップスケール→圧縮→出力を並列実行する。
/// Flutter版 `ConvertViewModel._processParallel/_processFile` に対応する。
///
/// アップスケール（GPUバウンド）と圧縮（CPUバウンド）を別々のワーカー群で動かし、
/// キューでつなぐ。片方が終わるのを待たずにもう片方が次々と処理できる（ADR 0034）。
/// アップスケールはディレクトリ一括実行でプロセス起動の固定費を抑える（ADR 0035）。
/// 処理枠（並列数）は出力が完了したファイルだけが返す（ADR 0038）。
struct ConvertOrchestrator: Sendable {
    /// 1プロセスでまとめてアップスケールするファイル数。
    /// 大きくするほど起動固定費は減るが、後段の圧縮が動き出すまでの待ち時間が増える。
    static let upscaleBatchSize = 4

    let upscale: UpscaleService
    let compression: CompressionService

    init(
        upscale: UpscaleService = UpscaleService(),
        compression: CompressionService = CompressionService()
    ) {
        self.upscale = upscale
        self.compression = compression
    }

    /// 並列数をGPU（アップスケール）とCPU（圧縮）に配分する。
    /// GPUは最大3ワーカーに抑え、残りを圧縮へ回す。小さな並列数でも
    /// 両ステージが同時に動くよう、最低1ずつ確保する。
    static func stageWorkerCounts(parallelCount: Int) -> StageWorkers {
        let total = max(1, parallelCount)
        let upscale = max(1, min(3, total / 3))
        return StageWorkers(
            upscale: upscale,
            compression: max(1, total - upscale)
        )
    }

    /// 出力ファイル名を組み立てる。拡張子直前の `.` ではなく最初の `.` で切る（Flutter版踏襲）。
    static func outputFileName(for inputName: String, format: OutputFormat) -> String {
        let base =
            inputName.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(
                String.init)
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

    /// 出力の完了（`fileDone`）を処理枠の解放に結び付ける完了通知を作る。
    /// Why not: 各処理箇所から直接解放を呼ぶと、1ファイルで二重に返す（または
    /// 取りこぼして枠が減り続ける）危険があるため、通知1件につき1枠に一本化する。
    static func trackingOutcome(
        deliver: @Sendable @escaping (FileOutcome) async -> Void,
        release: @Sendable @escaping () async -> Void
    ) -> @Sendable (FileOutcome) async -> Void {
        { outcome in
            await deliver(outcome)
            if outcome.fileDone {
                await release()
            }
        }
    }

    /// - Returns: (成功件数, 失敗件数)
    func run(
        files: [URL],
        config: ConvertConfig,
        outputDirectory: URL,
        paths: AppPaths,
        onOutcome: @Sendable @escaping (FileOutcome) async -> Void
    ) async -> (success: Int, failure: Int) {
        guard !files.isEmpty else { return (0, 0) }

        let workers = Self.stageWorkerCounts(parallelCount: config.parallelCount)
        let batchCount = (files.count + Self.upscaleBatchSize - 1) / Self.upscaleBatchSize
        let upscaleWorkers = min(workers.upscale, batchCount, files.count)
        let compressionWorkers = min(workers.compression, files.count)
        // 圧縮ワーカー数からエンコーダのスレッド配分を決める。
        let encoderThreads = CompressionService.encoderThreads(parallelCount: compressionWorkers)

        // 処理枠は並列数ぶん。出力が完了したファイルだけが枠を返す（ADR 0038）。
        let batcher = FileBatcher(
            count: files.count, batchSize: Self.upscaleBatchSize, capacity: config.parallelCount)
        let trackedOutcome = Self.trackingOutcome(deliver: onOutcome) {
            await batcher.release()
        }
        let queue = UpscaledQueue()
        let upscaleContext = UpscaleBatchContext(
            files: files, config: config, paths: paths, queue: queue, onOutcome: trackedOutcome)
        let compressionContext = CompressionContext(
            config: config, encoderThreads: encoderThreads, outputDirectory: outputDirectory,
            paths: paths, onOutcome: trackedOutcome)

        // アップスケール群が終わったらキューを閉じ、圧縮群を排水する。
        let upscaleTask = Task { () -> RunCounts in
            let counts = await withTaskGroup(of: RunCounts.self) { group in
                for _ in 0..<upscaleWorkers {
                    group.addTask {
                        await self.upscaleWorker(batcher: batcher, context: upscaleContext)
                    }
                }
                var total = RunCounts()
                for await counts in group {
                    total.merge(counts)
                }
                return total
            }
            await queue.finish()
            return counts
        }

        var total = RunCounts()
        await withTaskGroup(of: RunCounts.self) { group in
            for _ in 0..<compressionWorkers {
                group.addTask {
                    await self.compressionWorker(queue: queue, context: compressionContext)
                }
            }
            for await counts in group {
                total.merge(counts)
            }
        }
        let upscaleCounts = await upscaleTask.value
        total.merge(upscaleCounts)
        return (total.success, total.failure)
    }

    /// 中間ファイルを出力先へ確定する。同一ボリュームならコピーではなくrenameで移動する。
    /// renameはコピー置き換えに比べI/OがO(1)であり、大きな画像ほど差が出る（Why not: copyは移動元が残るため置換前に削除が必要）。
    static func installOutput(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
    }
}
