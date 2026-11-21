import Foundation
import Testing

@testable import TreeImageOptimizer

/// 一括変換の一時停止・キャンセルの回帰テスト（ADR 0054）。
/// 停止中に新しい作業を配らず、キャンセルでワーカーが終わることを確かめる。
@Suite("ConvertPauseCancel")
struct ConvertPauseCancelTests {
    /// ワーカーが受け取った値を記録する。停止中に配られていないことの確認に使う。
    private actor Recorder {
        private(set) var batch: UpscaleBatch?
        private(set) var item: UpscaledItem?

        func record(batch: UpscaleBatch?) {
            self.batch = batch
        }

        func record(item: UpscaledItem?) {
            self.item = item
        }
    }

    private static func sampleItem(index: Int) -> UpscaledItem {
        UpscaledItem(
            index: index,
            upscaled: URL(fileURLWithPath: "/tmp/\(index)/upscaled.png"),
            tempDirectory: URL(fileURLWithPath: "/tmp/\(index)", isDirectory: true),
            outputName: "\(index).webp",
            quality: 80,
            source: URL(fileURLWithPath: "/tmp/\(index)/source.png"))
    }

    @Test("一時停止中はバッチを配らず、再開すると配る")
    func schedulerWaitsWhilePaused() async {
        let control = RunControl()
        await control.pause()
        let scheduler = BatchScheduler(
            groups: [UpscaleGroup(scale: 2, resizeLongEdge: nil, model: nil, indices: [0, 1])],
            batchSize: 1, capacity: 2, control: control)
        let recorder = Recorder()
        let task = Task {
            let batch = await scheduler.next()
            await recorder.record(batch: batch)
        }
        // 停止中はバッチが配られないことを、少し待って確かめる。
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await recorder.batch == nil)
        await control.resume()
        _ = await task.value
        #expect(await recorder.batch?.indices == [0])
    }

    @Test("再開後は一時停止した位置から続きを配る")
    func schedulerResumesFromPausedPosition() async {
        let control = RunControl()
        let scheduler = BatchScheduler(
            groups: [UpscaleGroup(scale: 2, resizeLongEdge: nil, model: nil, indices: [0, 1, 2])],
            batchSize: 1, capacity: 1, control: control)
        let first = await scheduler.next()
        #expect(first?.indices == [0])
        await control.pause()
        // 停止中でも処理枠は返る。次に配るのは再開後になる。
        await scheduler.release()
        let second = Task { await scheduler.next() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await control.resume()
        #expect(await second.value?.indices == [1])
    }

    @Test("キャンセル後はバッチを配らない")
    func schedulerStopsAfterCancel() async {
        let control = RunControl()
        let scheduler = BatchScheduler(
            groups: [UpscaleGroup(scale: 2, resizeLongEdge: nil, model: nil, indices: [0])],
            batchSize: 1, capacity: 1, control: control)
        await control.cancel()
        #expect(await scheduler.next() == nil)
    }

    @Test("キャンセルで空き枠を待つワーカーを起こす")
    func schedulerCloseReleasesWaiters() async {
        let control = RunControl()
        let scheduler = BatchScheduler(
            groups: [UpscaleGroup(scale: 2, resizeLongEdge: nil, model: nil, indices: [0, 1])],
            batchSize: 1, capacity: 1, control: control)
        let first = await scheduler.next()
        #expect(first?.indices == [0])
        let waiter = Task { await scheduler.next() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await scheduler.close()
        #expect(await waiter.value == nil)
    }

    @Test("一時停止中に積んだファイルは再開後に圧縮へ渡す")
    func queueHoldsItemsWhilePaused() async {
        let control = RunControl()
        let queue = UpscaledQueue(control: control)
        await control.pause()
        await queue.push(Self.sampleItem(index: 0))
        let recorder = Recorder()
        let task = Task {
            let item = await queue.next()
            await recorder.record(item: item)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await recorder.item == nil)
        await control.resume()
        _ = await task.value
        #expect(await recorder.item?.index == 0)
    }

    @Test("停止中に届いたファイルは待機へ戻し、再開後に処理する")
    func queueDefersItemDeliveredWhilePaused() async {
        let control = RunControl()
        let queue = UpscaledQueue(control: control)
        let recorder = Recorder()
        let waiting = Task {
            let item = await queue.next()
            await recorder.record(item: item)
        }
        // ワーカーが取り出し待ちになるまで待つ。
        try? await Task.sleep(nanoseconds: 100_000_000)
        await control.pause()
        await queue.push(Self.sampleItem(index: 3))
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await recorder.item == nil)
        await control.resume()
        _ = await waiting.value
        #expect(await recorder.item?.index == 3)
    }

    @Test("キャンセル後はキューから取り出さず、残りは回収できる")
    func queueStopsAfterCancel() async {
        let control = RunControl()
        let queue = UpscaledQueue(control: control)
        await queue.push(Self.sampleItem(index: 0))
        await control.cancel()
        #expect(await queue.next() == nil)
        #expect(await queue.drainRemaining().map(\.index) == [0])
    }

    @Test("受付を閉じたあと残りが無ければ、停止中でもワーカーは終わる")
    func queueFinishesWhilePaused() async {
        let control = RunControl()
        let queue = UpscaledQueue(control: control)
        // 最後の1件を処理している間に停止し、そのままアップスケール群が終わる状況。
        await control.pause()
        await queue.finish()
        #expect(await queue.next() == nil, "再開を待たずにワーカーが終わること")
    }

    // MARK: - キャンセル待機（ポーリング排除）

    @Test("キャンセル待ちは通知で再開し、一時停止・再開では起きない")
    func waitUntilCancelledWakesOnlyOnCancel() async {
        let control = RunControl()
        let waiter = Task { await control.waitUntilCancelled() }
        // 待機に入る前に操作すると取りこぼすため、少し待ってから一時停止・再開する。
        try? await Task.sleep(nanoseconds: 50_000_000)
        await control.pause()
        await control.resume()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(!waiter.isCancelled, "一時停止・再開では待機が終わらないこと")
        await control.cancel()
        await waiter.value
        #expect(await control.isCancelled)
    }

    @Test("キャンセル済みのcontrolに対する待機は即座に返る")
    func waitUntilCancelledReturnsImmediatelyWhenAlreadyCancelled() async {
        let control = RunControl()
        await control.cancel()
        // ポーリング実装だと周期ぶん待たされるが、通知であれば即座に戻る。
        await control.waitUntilCancelled()
        #expect(await control.isCancelled)
    }

    @Test("複数の待機者がいても全員がキャンセルで再開する")
    func waitUntilCancelledWakesAllWaiters() async {
        let control = RunControl()
        let first = Task { await control.waitUntilCancelled() }
        let second = Task { await control.waitUntilCancelled() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await control.cancel()
        await first.value
        await second.value
        #expect(await control.isCancelled)
    }
}
