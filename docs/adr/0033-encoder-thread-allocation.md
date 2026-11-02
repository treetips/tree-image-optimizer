# エンコードのスレッド配分をコア数と並列数から決める

## ステータス

- 承認済み (Accepted)

## 背景・課題

一括変換の並列数はファイル単位のワーカー数であり、エンコーダのスレッド数とは
別の概念だったが、実装では `ConvertOrchestrator.processFile` が
`config.parallelCount` をそのまま `cjxl --num_threads` に渡していた。
そのため並列数Nで実行すると、各cjxlがNスレッドを起動し、最悪N²のスレッドが
コアを取り合っていた。コンテキストスイッチが増え、並列数を上げるほど
効率が落ちる可能性があった。

`avifenc` には `-j` を渡しておらず、既定値の `all` により各プロセスが
全コアを使おうとしていた。そのため並列数Nで実行すると、Nプロセスが
全コアを取り合っていた。

さらに既定の並列数が `コア数 / 2 - 1` で、ワーカー数とエンコーダの
スレッド数の関係が実態と合っていなかった。

## 決定

- `CompressionService.encoderThreads(parallelCount:processorCount:)` を新設し、
  1プロセスあたりのスレッド数を `max(1, コア数 / 並列数)` で求める。
- 並列数は設定値ではなく、実際に起動するワーカー数
  `min(config.parallelCount, files.count)` を使う。
  対象ファイルが少ないときに過剰なスレッドを渡さないため。
- 求めたスレッド数を `cjxl --num_threads` と `avifenc -j` の両方に渡す。
- 一括変換・かんたん変換の既定並列数を `max(1, コア数 - 1)` に変更する。
  UIとシステム用に1コアを残し、残りを変換に使う。

## 代替案

- `cjxl --num_threads=1` に固定する
  - 却下: 並列数がコア数より少ない設定では、1枚あたりのエンコードが
    シングルスレッドになり、コアを使い切れない。
- `avifenc` は1スレッドのままにする
  - 却下: ファイル数が少ないときにエンコード段でコアが余る。
- 既定並列数をコア数の半分のままにする
  - 却下: エンコード段がCPUバウンドである以上、コアを余らせる理由がない。
- ワーカーごとにスレッド数を動的に再配分する
  - 却下: スレッド数はプロセス起動時にしか渡せず、再配分にはプロセス再起動が要る。
    固定の除算で十分な精度が出る。

## 結果

- 並列数とスレッド数の積がおおむねコア数に収まり、過剰なスレッド競合がなくなる。
- AVIFエンコードも、プロセスあたりの `-j` でコア数を超えない範囲に制限される。
- 既定値の変更は新規設定に適用される。既存の保存値は維持される。
- 単体テスト: `ConvertPipelineTests.encoderThreads`、`avifencArgs`、
  `SettingsStoreTests.createsDefaultsWhenMissing` を更新。
- 実装箇所:
  - `TreeImageOptimizer/TreeImageOptimizer/Services/CompressionService.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Services/ConvertOrchestrator.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Services/SettingsStore.swift`
