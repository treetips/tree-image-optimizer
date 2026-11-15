import Foundation

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
    /// ファイルごとの圧縮品質。自動モードでは入力BPPで補正されている。
    var quality: Int
}

/// 倍率・縮小先のグループをまたがないようにバッチを配る。
/// 処理枠（並列数）の考え方は `FileBatcher` と同じで、出力完了で枠を返す（ADR 0038）。
///
/// Why not `FileBatcher` を拡張するか: あちらは連番の範囲を配るため、
/// バッチが異なる倍率をまたいでしまい、1プロセス1倍率の制約を守れない（ADR 0049）。
actor BatchScheduler {
    private let groups: [UpscaleGroup]
    private let batchSize: Int
    private let capacity: Int
    private var groupIndex = 0
    private var offset = 0
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(groups: [UpscaleGroup], batchSize: Int, capacity: Int) {
        self.groups = groups
        self.batchSize = max(1, batchSize)
        self.capacity = max(1, capacity)
    }

    /// 空き枠の数だけ次のバッチを返す。空きが無ければ空きが出来るまで待つ。
    /// 同一グループ内で収まる範囲だけを切り出す。
    func next() async -> UpscaleBatch? {
        while groupIndex < groups.count, offset >= groups[groupIndex].indices.count {
            groupIndex += 1
            offset = 0
        }
        guard groupIndex < groups.count else { return nil }
        while inFlight >= capacity {
            await withCheckedContinuation { waiters.append($0) }
        }
        let group = groups[groupIndex]
        let take = min(batchSize, capacity - inFlight, group.indices.count - offset)
        let indices = Array(group.indices[offset..<(offset + take)])
        offset += take
        inFlight += take
        return UpscaleBatch(
            scale: group.scale, resizeLongEdge: group.resizeLongEdge, model: group.model,
            indices: indices)
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
