# 並列数の上限をPコア数にし、外部ツールのQoSを明示する

## ステータス

- 承認済み (Accepted)

## 背景・課題

並列数の上限と初期値を `ProcessInfo.processInfo.processorCount`（全論理コア数）で
決めていた。Apple Siliconには性能の異なるPコアとEコアがあり、全コア数を上限にすると
Eコアまでワーカーを広げてしまう。Eコアで動くワーカーの完了を待つ間、Pコアが遊ぶため、
台数あたりの処理時間は短くなっても全体の完了時刻が遅くなることがある。

また、`Process` で起動した外部ツールはQoSを明示していなかった。既定では
バックグラウンド寄りの扱いになり、エンコード処理がEコアへ配置されやすかった。

## 決定

- `HardwareInfo.performanceCoreCount()` を新設する。
  - `sysctlbyname("hw.perflevel0.logicalcpu")` でPコアの論理数を取得する。
  - 取得できない環境（Intel Mac等）では全論理コア数へフォールバックする。
- 並列数の上限・初期値・設定値の補正にPコア数を使う。
  - 初期値は `max(1, Pコア数 - 1)`。
  - 保存済み設定がPコア数を超える場合はPコア数へ補正する。
- エンコーダのスレッド配分（ADR 0033）もPコア数を基準にする。
- `ProcessRunner` で起動する外部ツールの `qualityOfService` を `.userInitiated` にする。
  - `TASK_POLICY_THROUGHPUT` は公開APIではないため、公開されているQoSで
    前景処理としての優先度を明示する。

## 代替案

- 全論理コア数を上限のままにする
  - 却下: Eコアの遅いワーカーが末尾に残り、全体の完了時刻を遅らせる。
- PコアとEコアを別々のワーカー種別に割り当てる
  - 却下: どのスレッドがどちらのコアで動くかを公開APIから制御できず、
    QoSによる間接的な誘導しかできない。
- `task_policy_set` を直接呼ぶ
  - 却下: 公開SDKに `TASK_POLICY_THROUGHPUT` が露出しておらず、
    将来のOSで壊れる可能性がある。まず公開APIのQoSで様子を見る。

## 結果

- 並列数の上限がPコア数になり、Eコアの完了待ちによる末尾の遅れを避けられる。
- 既存ユーザーの保存値がPコア数を超えている場合、読み込み時に補正される。
- 外部ツールは前景処理のQoSで起動され、Eコアへ回されにくくなる。
- 単体テスト: `ConvertPipelineTests.performanceCoreCount`。
- 実装箇所:
  - `TreeImageOptimizer/TreeImageOptimizer/Core/HardwareInfo.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Services/ProcessRunner.swift`
  - 並列数を使う各ViewModel・JobStore
