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
        while true {
            guard nextIndex < count else { return nil }
            if inFlight < capacity { break }
            // actorはawaitで再入するため、待機から再開した時点で他のワーカーが
            // 残りを取得している可能性がある。ループ先頭へ戻って必ず再評価する。
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
/// 一覧表の最も上にある未処理ファイルから順にバッチを開始し、先読み `lookahead` 件以内に
/// ある同じグループのファイルをまとめる。飛び越しは最大 `lookahead` 行に収まる（ADR 0053）。
actor BatchScheduler {
    private struct Entry: Sendable {
        var fileIndex: Int
        var groupIndex: Int
    }

    private let groups: [UpscaleGroup]
    private let batchSize: Int
    private let capacity: Int
    private let lookahead: Int
    /// 一覧表の順（ファイルindex昇順）に並べた全ファイル。
    private let entries: [Entry]
    /// バッチへ配ったか。バッチ内のファイルは同時に処理を開始する。
    private var taken: [Bool]
    /// まだ配っていない先頭位置。先頭から順に進める。
    private var cursor = 0
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(groups: [UpscaleGroup], batchSize: Int, capacity: Int, lookahead: Int = 8) {
        self.groups = groups
        self.batchSize = max(1, batchSize)
        self.capacity = max(1, capacity)
        self.lookahead = max(1, lookahead)
        var entries: [Entry] = []
        entries.reserveCapacity(groups.reduce(0) { $0 + $1.indices.count })
        for (groupIndex, group) in groups.enumerated() {
            for fileIndex in group.indices {
                entries.append(Entry(fileIndex: fileIndex, groupIndex: groupIndex))
            }
        }
        self.entries = entries.sorted { $0.fileIndex < $1.fileIndex }
        self.taken = Array(repeating: false, count: entries.count)
    }

    /// 空き枠の数だけ次のバッチを返す。空きが無ければ空きが出来るまで待つ。
    /// 一覧表で最も上にある未処理ファイルから、先読みの範囲で同じグループをまとめる。
    func next() async -> UpscaleBatch? {
        while true {
            // actorはawaitで再入するため、待機から再開したら必ず先頭から選び直す。
            // 待機前の位置をそのまま使うと、他ワーカーが取得済みのファイルを
            // 二重に配ったり、状態がずれたりする。
            guard let start = firstUntakenPosition() else { return nil }
            if inFlight < capacity {
                return makeBatch(startPosition: start)
            }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// まだバッチへ配っていない最も上のファイル位置。全ファイルを配り終えたらnil。
    private func firstUntakenPosition() -> Int? {
        while cursor < taken.count, taken[cursor] {
            cursor += 1
        }
        return cursor < taken.count ? cursor : nil
    }

    /// 先頭のファイルを含むグループから、先読み `lookahead` 件以内の同じグループを
    /// 1バッチにまとめる。間にある別グループのファイルを飛ばすのは最大 `lookahead` 行。
    private func makeBatch(startPosition: Int) -> UpscaleBatch {
        let groupIndex = entries[startPosition].groupIndex
        let limit = min(batchSize, capacity - inFlight)
        var positions: [Int] = []
        var scanned = 0
        var position = startPosition
        while position < entries.count, scanned < lookahead, positions.count < limit {
            if !taken[position] {
                scanned += 1
                if entries[position].groupIndex == groupIndex {
                    positions.append(position)
                }
            }
            position += 1
        }
        for position in positions {
            taken[position] = true
        }
        inFlight += positions.count
        let group = groups[groupIndex]
        let indices = positions.map { entries[$0].fileIndex }
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
