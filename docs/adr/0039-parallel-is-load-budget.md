# 並列数をエンコーダの負荷予算として扱う

## ステータス

- 承認済み (Accepted)
- ADR 0033 のうち「総スレッド数がコア数に収まる」「コアを余らせる理由がない」を変更する。

## 背景・課題

ADR 0033 でエンコーダのスレッド数を `コア数 / ワーカー数` にしたため、
ワーカー数 × スレッド数の積が並列数に関係なく常にコア数になった。
Pコア12のマシンで並列数ごとに計算すると次のとおりで、次の問題が起きていた。

| 並列数 | GPU | 圧縮ワーカー | 1プロセス | エンコーダ総スレッド | Pコア比 |
|---:|---:|---:|---:|---:|---:|
| 1〜6 | 1〜2 | 1〜4 | 3〜12 | 12 | 100% |
| 7 | 2 | 5 | 2 | 10 | 83% |
| 8 | 2 | 6 | 2 | 12 | 100% |
| 9 | 3 | 6 | 2 | 12 | 100% |
| 10 | 3 | 7 | 1 | 7 | 58% |
| 11 | 3 | 8 | 1 | 8 | 67% |
| 12 | 3 | 9 | 1 | 9 | 75% |

- 並列数を下げても負荷が下がらない。並列1〜9のいずれもPコアをほぼ満杯にする。
- 除算の端数で負荷が並列数に対して単調にならない。並列10が最も軽くなる。
- スライダーの色は `設定値 / 最大` だけで判定しており、実際のCPU負荷と一致しない。
- 既定値が `最大 - 1`（11/12）だったので、初期状態のままスライダーが赤色になる。

日常使い（動画視聴やブラウジング）を妨げない初期値にしたいという要件に対して、
初期値だけ変更しても負荷は下がらない。

## 決定

- `CompressionService.encoderThreads(parallelCount:workers:processorCount:)` の予算を
  `コア数` から `並列数`（Pコア数で頭打ち）へ変更し、ワーカー数で割って切り捨てる。
  - 全プロセスの合計スレッド数は `<= 並列数` になる。
  - スライダーの割合がそのままCPU負荷の目安になるため、色の警告が実態と一致する。
- 並列数の既定値を `max(1, 最大 / 2)` にする。
  - `HardwareInfo.defaultParallelCount(maxParallel:)` にまとめ、
    一括変換・かんたん変換の設定既定値とViewModelの初期値の4箇所で使う。
  - Pコア12なら既定値は6（GPU2プロセス・エンコーダ4スレッド）。
- スライダーの色の閾値は `0.7` 以上を黄色、`0.9` 以上を赤のまま維持する。
  - 負荷と一致するようになったため、閾値の変更はしない。
  - 設計ドキュメントの4分割の記述はコードに合わせて修正した。

### 負荷の対応表（Pコア12）

| 並列数 | エンコーダ総スレッド | GPU | 旧 総スレッド |
|---:|---:|---:|---:|
| 1 | 1 | 1 | 12 |
| 3 | 2 | 1 | 12 |
| 6（既定） | 4 | 2 | 12 |
| 9 | 6 | 3 | 12 |
| 12 | 9 | 3 | 9 |

## 代替案

- 既定値だけ下げてスレッド設計は変えない
  - 却下: 並列1〜9はいずれもコア数ぶんを使うため、負荷が下がらない。
- 予備コアを固定で空ける（例: `コア数 - 3`）
  - 却下: 並列数を変えてもCPU負荷が変わらず、スライダーの色が負荷を表さなくなる。
- 合計が予算ぴったりになるよう不均等にスレッドを配る（切り上げを使う）
  - 却下: 実装が複雑になり、端数で予算を超える。切り捨てで予算以下を保証する。
- 既定値の変更を既存の保存設定にも適用する（移行処理を追加）
  - 却下: 保存値の上書きはADR 0033以降の方針と異なり、ユーザーが選んだ値を壊す。

## 結果

- 並列1〜12のエンコーダ総スレッド数は `1, 2, 2, 3, 4, 4, 5, 6, 6, 7, 8, 9` と単調に増え、
  いずれも並列数を超えない。
- 既定値6ではエンコーダ4スレッド＋GPU2プロセスになり、日常使いと併用しやすい。
- 並列数を上げたときの処理速度は従来より落ちる。従来は並列数に関係なく
  コア数ぶんのスレッドを使っていたため。最大（12）でもエンコーダは9スレッド（75%）で、
  GPUプロセスのCPU使用分を含めてようやくコア数に近づく。
- 並列数1は1スレッドになる。最も負荷を下げる設定として整合するが、1ファイルあたりの
  エンコードは遅い。
- 既存の保存値は上書きされない。新しい既定値は新規作成時のみ適用される。
- 単体テスト:
  - `ConvertPipelineTests.encoderThreads`
  - `ConvertPipelineTests.encoderThreadBudgetIsMonotonic`
  - `SettingsStoreTests.createsDefaultsWhenMissing`（既定値の変更を反映）
  - `SliderLoadLevelTests`（閾値据え置きを確認）
- 実装箇所:
  - `TreeImageOptimizer/TreeImageOptimizer/Core/HardwareInfo.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Services/CompressionService.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Services/ConvertOrchestrator.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Services/SettingsStore.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Features/Convert/ConvertViewModel.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Features/EasyConvert/EasyConvertViewModel.swift`
