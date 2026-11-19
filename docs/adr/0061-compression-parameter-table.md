# 圧縮パラメータを最適化種別ごとの1テーブルに集約する

## ステータス

- 承認済み (Accepted)

## 背景・課題

`CompressionService` は最適化種別（`OptimizeType`: anime / photo / speed / quality）ごとの
パラメータを、以下の8本以上の独立した static 辞書で保持していた。

- `jpegQuality`, `pngQuality`, `jxlEffort`, `jxlExtraOpts`
- `avifSpeed`, `avifYuv`, `avifCodec`, `avifAomOpts`, `avifSvtOpts`
- `webpPreset`, `webpMethod`

さらに `profile(optimizeType:quality:)` 内に次のような分岐があり、AVIF の設定が
5つの辞書（`avifCodec` / `avifYuv` / `avifSpeed` / `avifAomOpts` / `avifSvtOpts`）に分散していた。

```swift
let codec = avifCodec[optimizeType, default: "aom"]
avifAdvanced: codec == "svt" ? (avifSvtOpts[optimizeType] ?? []) : (avifAomOpts[optimizeType] ?? [])
```

この構造には次の問題があった。

- 最適化種別を1つ追加するのに8〜11か所の修正が必要で、修正漏れが実行時まで検出されない。
- `codec == "svt"` のように文字列の値を見て別の表を選ぶため、
  タイポや対応崩れをコンパイラが検出できない。
- `avifSvtOpts` は photo / speed の2件しか定義がなく、他の種別は暗黙のフォールバック
  （`?? []`）に依存していた。
- ある種別のパラメータを確認するにはテーブルを横断して見比べる必要があった。

自動モード側も `QualityPreset` の extension に `jxlEffort` / `avifSpeed` / `webpMethod` の
3本の `switch` が並び、プリセット1つを調整するのに3か所を見比べる必要があった。

## 決定

### 最適化種別ごとのパラメータを1構造体にまとめる

`OptimizeTypeParameters`（`Core/Models.swift`）を新設し、`CompressionService.parameters`
の1テーブルに集約する。種別の追加・変更はこの1か所だけで済む。

```swift
static let parameters: [OptimizeType: OptimizeTypeParameters] = [
    .anime: OptimizeTypeParameters(
        jpegQuality: 75, pngQuality: 75, jxlEffort: 7, jxlExtra: ["--lossless_jpeg=0"],
        avif: AvifParameters(codec: .aom, speed: 3, yuv: 444,
                             advanced: ["-a", "end-usage=q", "-a", "cq-level=22"]),
        webpPreset: "drawing", webpMethod: 4),
    // ...
]
```

### AVIF の codec と advanced を1つの値にする

`String` の `"aom"` / `"svt"` を enum `AvifCodec` にし、構造体 `AvifParameters` が
`codec` / `speed` / `yuv` / `advanced` をまとめて持つ。
これにより `codec == "svt"` の実行時分岐が消え、「どの advanced option を渡すか」は
表の定義そのものになる。

`AvifParameters.init` は SVT-AV1 に `444` が渡されたら `420` に矯正する。
SVT-AV1 は 4:2:0 しか受け付けず（ADR 0037）、`444` のままだとエンコードが失敗するため、
制約を生成時に担保する。

### 画質プリセットも1構造体にまとめる

`QualityPresetParameters` を新設し、`QualityPreset.parameters` で effort / speed / method の
対応を1か所に置く。既存の `jxlEffort` / `avifSpeed` / `webpMethod` は
互換のため計算プロパティとして残す。

### 型の配置

新設した型は `Core/Models.swift` に置く。
`CompressionService` に置くと1ファイルの行数と型の行数が規約上限を超えるためで、
`OptimizeType` / `QualityPreset` と同じ場所にある方が対応関係も追いやすい。

## 代替案

- 辞書を `OptimizeType` の extension にする（`OptimizeType.avifSpeed` 等）
  - 却下: 項目ごとの extension になり、「1種別のパラメータ」が依然として散在する。
    構造体なら種別1件の定義が1ブロックにまとまる。
- codec を enum にするだけで辞書の構成は変えない
  - 却下: `codec == .svt` の分岐は残り、advanced option が別表のままになる。
    分岐そのものを消すためには advanced も同じ値に入れる必要がある。
- `avifYuv` を `AvifCodec` から導出して表から消す
  - 却下: 4:2:0 を選ぶ根拠がエンコーダの制約ではなく「この種別は420で良い」という
    画質判断でもある。両方を表に残し、制約違反だけを `init` で矯正する。
- 構造体の `advanced` を `[String]` でなく型付きにする（`cqLevel` / `crf` を分離）
  - 保留: libaom の `cq-level` と SVT の `crf` は意味が違い（ADR 0037）、
    共通の型に落とすと値の意味を誤解しやすい。引数は結局 `-a key=value` の並びなので、
    当面は表の中に実測値をそのまま書く。

## 結果

- 最適化種別1件の追加・変更が `CompressionService.parameters` の1か所になった。
- `codec == "svt"` の実行時分岐が消え、codec と advanced option の対応が定義時に決まる。
- **出力される引数は従来と完全に一致する**。
  固定モード（4種別 × 品質5値）と自動モード（2コンテンツ × 4プリセット × 品質4値）の
  `cjxlArguments` / `avifencArguments` / `cwebpArguments` / `jpegoptimArguments` /
  `pngoptimArguments` およびプロファイルの全項目を、変更前後の実装で実行して
  254行すべてが同一であることを確認した。ADR 0037 / 0040 の実測チューニング結果は壊れていない。
- `CompressionProfile` の AVIF 4項目（`avifCodec` / `avifSpeed` / `avifYuv` / `avifAdvanced`）
  は計算プロパティとして残るため、既存の呼び出しと既存テストは変更不要
  （`ConvertPipelineTests.avifencArgs`、`ConversionPlannerTests.autoProfiles` 等）。
- `ConvertPipelineTests.avifCodecMatchesYuv` は削除された `CompressionService.avifCodec` /
  `avifYuv` 辞書を参照していたため、プロファイル経由の検証に書き換えた。
  保証内容（SVT-AV1 を使う種別は 420）は変わらない。
- 実装箇所:
  - `TreeImageOptimizer/TreeImageOptimizer/Core/Models.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Services/CompressionService.swift`
