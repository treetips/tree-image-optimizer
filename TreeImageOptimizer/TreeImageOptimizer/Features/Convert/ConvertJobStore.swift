import Foundation

/// 一括変換の実行状態を保持する共有ジョブ層。
/// 画面（`ConvertView` / `ConvertViewModel`）ではなくアプリ層で所有し、
/// サイドナビ切替でViewが再生成されても進捗・結果を維持するために使う。
/// 実処理は `ConvertOrchestrator`（Service）に委譲する。
@Observable
@MainActor
final class ConvertJobStore {
    var isRunning: Bool = false
    /// 一時停止中か。停止しても処理枠や進捗は保持する（ADR 0054）。
    var isPaused: Bool = false
    /// キャンセルを受け付けて、ワーカーの終了を待っている状態か。
    var isCancelling: Bool = false
    var progressPercent: Double = 0
    var successCount: Int = 0
    var failureCount: Int = 0
    var elapsedMinutes: Double = 0
    var rows: [FileRow] = []
    var resultMessage: String = ""

    /// 残り時間の概算（分）。完了件数と経過時間から1件あたりの所要時間を出して残件数を掛ける。
    /// 完了がまだ無い、または全件終わっている場合は nil（ADR 0067）。
    var estimatedRemainingMinutes: Double? {
        Self.estimatedRemainingMinutes(
            elapsed: elapsedMinutes, completed: completedCount, total: rows.count)
    }

    /// 残り時間の概算を返す純粋関数。単体テスト可能にするため型メソッドへ切り出す。
    static func estimatedRemainingMinutes(elapsed: Double, completed: Int, total: Int) -> Double? {
        guard completed > 0, completed < total else { return nil }
        return elapsed / Double(completed) * Double(total - completed)
    }

    private var completedCount: Int = 0
    /// 実行中・再実行で、ファイルindex→行indexを対応付ける写像（ADR 0066）。
    private var indexMap: [Int] = []
    /// 直近の実行で使った設定。失敗のみ再実行で再利用する（ADR 0066）。
    private var lastConfig: ConvertConfig?
    /// 直近の実行で使った出力先。失敗のみ再実行で再利用する（ADR 0066）。
    private var lastOutputDirectory: URL?
    private var runTask: Task<Void, Never>?
    /// 実行中の停止・再開・キャンセルをワーカーへ伝える共有状態。
    private var control: RunControl?
    /// 一時停止していた合計時間。実行時間の表示から除く（ADR 0054）。
    private var pausedTotal: TimeInterval = 0
    /// 現在の一時停止が始まった時刻。停止中でなければnil。
    private var pausedStartedAt: Date?

    private let paths: AppPaths
    private let store: SettingsStore
    private let orchestrator: ConvertOrchestrator
    private let completionService: ConversionCompletionService
    private let maxParallel: Int

    init(
        paths: AppPaths = AppPaths(),
        store: SettingsStore? = nil,
        orchestrator: ConvertOrchestrator = ConvertOrchestrator(),
        soundService: SoundService? = nil
    ) {
        let resolvedStore = store ?? SettingsStore(paths: paths)
        let resolvedMaxParallel = max(1, HardwareInfo.performanceCoreCount())
        self.paths = paths
        self.store = resolvedStore
        self.orchestrator = orchestrator
        self.maxParallel = resolvedMaxParallel
        self.completionService = ConversionCompletionService(
            paths: paths, store: resolvedStore, soundService: soundService,
            maxParallel: resolvedMaxParallel)
    }

    /// 進捗表の初期行を組み立てる。実行前の待機中状態で、変換前後のフルパスを保持する。
    /// 出力パスは実行時と同じ命名（`outputFileName`）で先に確定させる（Why not: 実行後に都度計算すると表の再描画ごとに組み立てが必要になる）。
    static func makeRows(files: [URL], format: OutputFormat, outputDirectory: URL) -> [FileRow] {
        files.map { file in
            FileRow(
                fileName: file.lastPathComponent,
                sourcePath: file.path,
                outputPath: outputDirectory.appendingPathComponent(
                    ConvertOrchestrator.outputFileName(for: file.lastPathComponent, format: format),
                    isDirectory: false
                ).path,
                upscale: .waiting,
                compress: .waiting,
                output: .waiting
            )
        }
    }

    /// 変換を開始する。実行中は受け付けない。
    func start(files: [URL], config: ConvertConfig, outputDirectory: URL) {
        guard !isRunning else { return }
        guard !files.isEmpty else { return }
        runTask?.cancel()
        lastConfig = config
        lastOutputDirectory = outputDirectory
        let control = RunControl()
        self.control = control
        runTask = Task {
            // 新規実行: 進捗・件数・結果表を初期化してから実行する。
            progressPercent = 0
            successCount = 0
            failureCount = 0
            completedCount = 0
            rows = Self.makeRows(files: files, format: config.format, outputDirectory: outputDirectory)
            await run(
                files: files, config: config, outputDirectory: outputDirectory,
                rowIndices: Array(files.indices), control: control)
        }
    }

    /// 実行を一時停止する。実行中のプロセスは完了させ、次のバッチから止める（ADR 0054）。
    func pause() {
        guard isRunning, !isPaused, !isCancelling else { return }
        isPaused = true
        pausedStartedAt = Date()
        let control = self.control
        Task { await control?.pause() }
    }

    /// 一時停止した実行を再開する。進捗と処理枠は停止前のまま続きから処理する。
    func resume() {
        guard isRunning, isPaused, !isCancelling else { return }
        closePauseWindow()
        isPaused = false
        let control = self.control
        Task { await control?.resume() }
    }

    /// 実行をキャンセルする。変換済みの出力は残し、未完了の行はキャンセルとして表示する（ADR 0054）。
    func cancel() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        isPaused = false
        closePauseWindow()
        let control = self.control
        let runTask = self.runTask
        // Why not control のフラグを立てるだけか: 実行中の子プロセスを止めるのは
        // ProcessRunner の withTaskCancellationHandler であり、タスクをキャンセルしないと
        // upscayl / Real-CUGAN が終わるまで待たされる（ADR 0054）。
        // Why not 先にタスクをキャンセルするか: CancellationError が control のフラグより先に
        // 飛ぶと、ワーカーがそれを通常の失敗として数えてしまうため。
        Task {
            await control?.cancel()
            runTask?.cancel()
        }
    }

    /// オーケストレータを起動して完了まで駆動する。新規実行と失敗のみ再実行の両方から呼ぶ。
    /// `rowIndices` はオーケストレータのファイルindexを行indexへ写像する（ADR 0066）。
    private func run(
        files: [URL], config: ConvertConfig, outputDirectory: URL,
        rowIndices: [Int], control: RunControl
    ) async {
        isRunning = true
        isPaused = false
        isCancelling = false
        elapsedMinutes = 0
        resultMessage = ""
        pausedTotal = 0
        pausedStartedAt = nil
        indexMap = rowIndices
        let started = Date()
        // 実行時間をリアルタイム表示するための更新ループ。
        // 一時停止中は表示を止め、停止していた時間は実行時間に含めない。
        let elapsedTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                guard !self.isPaused else { continue }
                self.elapsedMinutes = self.activeElapsed(since: started) / 60.0
            }
        }
        defer {
            elapsedTask.cancel()
            closePauseWindow()
            isRunning = false
            isPaused = false
            isCancelling = false
            elapsedMinutes = activeElapsed(since: started) / 60.0
        }
        _ = await orchestrator.run(
            files: files, config: config, outputDirectory: outputDirectory, paths: paths,
            control: control
        ) { [weak self] outcome in
            guard let self else { return }
            await MainActor.run {
                self.apply(outcome)
            }
        }
        await finish(control: control)
    }

    /// 結果を集計して表示用のメッセージを作る。キャンセル時は完了通知もサウンドも出さない。
    /// 件数は行の状態から再集計する。再実行は表の一部だけを更新するため、
    /// オーケストレータの戻り値（再実行した件数）をそのまま全体件数に当てない（ADR 0066）。
    private func finish(control: RunControl) async {
        let language = (try? store.load(maxParallel: maxParallel).settings.language) ?? ""
        if await control.isCancelled {
            // 途中経過だけを「キャンセル」として残す。
            applyCancellation()
            recount()
            resultMessage = String(
                format: L10n.string("c.done.cancelled", language: language), successCount,
                cancelledCount)
            return
        }
        recount()
        // キャンセル行など未処理の行が残る場合は成功扱いにしない。
        // Why not 失敗0件だけで判定するか: 途中キャンセル後の再実行で成功しても、
        // 未処理行が残ったまま成功通知（音・OS通知）を出すと実態と食い違うため。
        let allSuccess = failureCount == 0 && successCount > 0 && successCount == rows.count
        if allSuccess {
            resultMessage = String(format: L10n.string("c.done.success", language: language), successCount)
        } else {
            resultMessage = String(
                format: L10n.string("c.done.mixed", language: language), successCount, failureCount)
        }
        await completionService.complete(
            allSuccess: allSuccess, language: language, notify: true)
    }

    private func apply(_ outcome: FileOutcome) {
        guard let rowIndex = rowIndex(for: outcome.index) else { return }
        if outcome.started {
            switch outcome.stage {
            case .upscale:
                rows[rowIndex].upscale = .running
            case .compress:
                rows[rowIndex].compress = .running
            case .output:
                rows[rowIndex].output = .running
            }
            return
        }
        switch outcome.stage {
        case .upscale:
            rows[rowIndex].upscale = outcome.succeeded ? .success : .failure
        case .compress:
            rows[rowIndex].compress = outcome.succeeded ? .success : .failure
        case .output:
            rows[rowIndex].output = outcome.succeeded ? .success : .failure
        }
        // 件数は完了都度リアルタイムに集計する。
        if outcome.fileDone {
            completedCount += 1
            if outcome.succeeded {
                successCount += 1
            } else {
                failureCount += 1
            }
        }
        if !rows.isEmpty {
            progressPercent = Double(completedCount) / Double(rows.count) * 100
        }
    }
}

/// 結果表の状態分類・集計と、失敗のみ再実行（ADR 0054 / ADR 0066）。
/// クラス本体の行数制限（type_body_length）を守るためextensionに分離する。
extension ConvertJobStore {
    /// 失敗のみ再実行が可能か。実行中でなく、失敗行が1件以上あること（ADR 0066）。
    var canRetryFailed: Bool {
        !isRunning && rows.contains { Self.isFailure($0) }
    }

    /// 失敗したファイルだけを同じ設定・出力先で再実行する（ADR 0066）。
    /// 成功済みの行は残し、失敗行だけを待機中へ戻して処理する。
    func retryFailed() {
        guard canRetryFailed else { return }
        let failedIndices = rows.indices.filter { Self.isFailure(rows[$0]) }
        guard !failedIndices.isEmpty else { return }
        guard let config = lastConfig, let outputDirectory = lastOutputDirectory else { return }
        let files = failedIndices.map { URL(fileURLWithPath: rows[$0].sourcePath) }
        runTask?.cancel()
        let control = RunControl()
        self.control = control
        runTask = Task {
            // 失敗行だけを待機中へ戻す。成功済みの行の結果は保持する。
            for index in failedIndices {
                rows[index].upscale = .waiting
                rows[index].compress = .waiting
                rows[index].output = .waiting
            }
            // 失敗行ぶんを実行中から除いた状態へ件数・進捗を再集計する。
            recount()
            completedCount = rows.filter { Self.isFinished($0) }.count
            await run(
                files: files, config: config, outputDirectory: outputDirectory,
                rowIndices: failedIndices, control: control)
        }
    }

    /// キャンセル時に、完了していない段階だけを「キャンセル」に切り替える。
    /// 完了済みの段階（成功・失敗）は結果として残す。
    private func applyCancellation() {
        for index in rows.indices {
            rows[index].upscale = Self.cancelStatus(rows[index].upscale)
            rows[index].compress = Self.cancelStatus(rows[index].compress)
            rows[index].output = Self.cancelStatus(rows[index].output)
        }
    }

    private static func cancelStatus(_ status: ProcessStatus) -> ProcessStatus {
        status == .success || status == .failure ? status : .cancelled
    }

    /// キャンセルで未完了になった行の数。途中で失敗した行は失敗として数えるため除く。
    private var cancelledCount: Int {
        rows.filter { row in
            !Self.isFailure(row) && [row.upscale, row.compress, row.output].contains(.cancelled)
        }.count
    }

    /// 一時停止していた時間を除いた実行時間。
    private func activeElapsed(since started: Date) -> TimeInterval {
        let pausedNow = pausedStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        return max(0, Date().timeIntervalSince(started) - pausedTotal - pausedNow)
    }

    /// 現在の一時停止を合計へ繰り入れる。停止していなければ何もしない。
    private func closePauseWindow() {
        if let started = pausedStartedAt {
            pausedTotal += Date().timeIntervalSince(started)
            pausedStartedAt = nil
        }
    }

    /// 行の状態から件数を数え直す。キャンセル時は途中終了の段階があるため、
    /// 実行中の集計値ではなく行そのものを正とする。
    private func recount() {
        successCount = rows.filter { $0.output == .success }.count
        failureCount = rows.filter(Self.isFailure).count
        let finished = rows.filter { Self.isFinished($0) }.count
        if !rows.isEmpty {
            progressPercent = Double(finished) / Double(rows.count) * 100
        }
    }

    /// 失敗として数える行か。途中の段階で失敗した行を含み、出力まで成功した行は除く。
    private static func isFailure(_ row: FileRow) -> Bool {
        row.output != .success
            && (row.output == .failure || row.upscale == .failure || row.compress == .failure)
    }

    /// そのファイルの処理が決着したか。途中の段階で失敗した時点で決着とみなす。
    private static func isFinished(_ row: FileRow) -> Bool {
        row.output == .success || row.output == .failure
            || row.upscale == .failure || row.compress == .failure
    }

    /// オーケストレータのファイルindexを、現在の結果表の行indexへ写像する（ADR 0066）。
    /// 範囲外なら nil。通常の新規実行では indexMap が恒等写像になるため同じ値が返る。
    private func rowIndex(for fileIndex: Int) -> Int? {
        guard indexMap.indices.contains(fileIndex), rows.indices.contains(indexMap[fileIndex]) else {
            return nil
        }
        return indexMap[fileIndex]
    }
}
