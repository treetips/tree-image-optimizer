# キャンセル通知をポーリングからイベント駆動に変更する

## ステータス

- 承認済み (Accepted)

## 背景・課題

一括変換の一時停止・キャンセル（ADR 0054）では、`ConvertOrchestrator.cancelMonitor` が
`RunControl.isCancelled` を 100ms 周期で確認していた。

```swift
Task {
    while !Task.isCancelled {
        if await control.isCancelled { break }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    guard await control.isCancelled else { return }
    await scheduler.close()
    await queue.finish()
}
```

キャンセルのような即応性が要る操作を周期起床で扱うことには2つの問題がある。

- 押してから反映されるまで最大100msの遅れが入る。
- 変換中は常に10回/秒の起床が発生し、CPUを消費する。

一方 `RunControl` は一時停止の待機を `CheckedContinuation` で既に実現していた（ADR 0052）。
同じ仕組みをキャンセルへ広げれば、起床はキャンセルの1回だけで済む。

## 決定

- `RunControl` にキャンセル待ちの waiter リストと `waitUntilCancelled()` を追加する。
  `cancel()` は一時停止の待機者に加えて、キャンセルの待機者も resume する。
- `cancelMonitor` は `await control.waitUntilCancelled()` で停止し、
  起床したら `scheduler.close()` と `queue.finish()` を行う。
- `waitUntilCancelled()` は actor の再入があるため、再開後にループ先頭で
  `cancelled` を読み直す。既にキャンセル済みの場合は待機に入らず即座に返る（ADR 0052）。
- 監視役の `Task` は従来どおり呼び出し側が `cancel()` で終わらせる。
  待機の再開条件はキャンセルだけではなく、**監視タスク自身の取り消し**も含める。
  `waitUntilCancelled()` は `withTaskCancellationHandler` で取り消し時にも waiter を起こし、
  ループ先頭で `Task.isCancelled` を読み直して抜ける。
  取り消しで待機を解かないと、誰も起こさない `CheckedContinuation` に止まったタスクが
  `RunControl` とワーカー群を掴んだまま解放されない（実行のたびに1つ残留する）。

## 代替案

- ポーリング周期を短くする（例: 10ms）
  - 却下: 遅れは減るが起床回数が10倍になり、CPU消費の問題が残る。
- `AsyncStream` や `NotificationCenter` でキャンセルを配信する
  - 却下: 待機者が購読を開始する前に `cancel()` が走ると取りこぼす。
    `RunControl` の内部状態と waiter を同じアクターに置けば取りこぼしがない。
- キャンセルを待たず、各ワーカーが `isCancelled` を都度確認する
  - 却下: スケジューラの空き枠待ちとキューの取り出し待ちは continuation で
    止まっており、自発的に起きられない（ADR 0054）。

## 結果

- キャンセルの反映が周期に依存しなくなり、押した直後に待機中のワーカーが起きる。
- 変換中の無駄な周期起床がなくなる。監視役が周期を決めなくてよい。
- 一時停止・再開ではキャンセルの待機者は起きないため、従来の挙動は変わらない。
- 実行完了で監視タスクを取り消しても待機が解けるため、タスクが残留しない。
- 変更箇所: `Services/BatchScheduling.swift`、`Services/ConvertOrchestrator.swift`。
  回帰テスト: `TreeImageOptimizerTests/ConvertPauseCancelTests.swift`。
