# AV1エンコーダにSVT-AV1を併用する

## ステータス

- 承認済み (Accepted)

## 背景・課題

同梱している `avifenc`（libavif v1.4.2）は libaom 3.14.1 しかエンコーダとして持っていなかった。
libaom は圧縮率と画質に定評があるが、SVT-AV1 に比べて速度が遅い。
一括変換では AVIF のエンコードがボトルネックになりやすく、エンコーダの差し替えが性能改善の候補になった。

SVT-AV1 は macOS arm64 向けの静的ビルドを自前で作れるか、画質を落とさずどれだけ速くなるか、
現行のパラメータをそのまま適用できるかを実測で確認した。

## 調査結果

### 入手可否

libavif v1.4.2 の `AVIF_CODEC_SVT=LOCAL` で SVT-AV1 v4.1.0 を自動取得してビルドできる。
完全静的リンク（依存は `libSystem` / `libc++` のみ）で、`avifenc` は 12MB（従来 8.3MB）。
libaom と同居できるため、1つのバイナリで `-c` によりエンコーダを選択できる。

### 速度と画質（実測）

入力は 1536x2752 の画像。VMAF は元画像との比較。

| 条件 | エンコーダ | サイズ | 時間 | VMAF |
|---|---|---|---|---|
| 実写 speed4 | libaom `cq-level=22` | 122KB | 0.91s | 95.31 |
| 実写 speed4 | SVT `crf=11` | 113KB | 0.21s | 95.41 |
| 実写 speed4 | SVT `crf=12` | 104KB | 0.18s | 94.88 |
| 速度優先 speed8 | libaom | 144KB | 0.09s | 94.67 |
| 速度優先 speed8 | SVT | 85KB | 0.07s | 94.24 |

実写・写真は SVT の方が約 4.5 倍速く、`crf=11` で VMAF・ファイルサイズとも libaom とほぼ同じ。

### 制約

SVT-AV1 は **4:2:0 しか受け付けない**（v4.2.0 でも `Only support 420 now` で拒否）。
アプリの「アニメ・イラスト」「画質最優先」は設計上 `-y 444` を指定しているため、そのままでは使えない。
420 に強制すると色度 PSNR が約 1.2dB 低下し、イラストの色のにじみとして現れる。

## 決定

- 同梱の `avifenc` を libaom と SVT-AV1 の両方を静的リンクしたビルドへ差し替える。
- 最適化種別ごとにエンコーダを振り分ける。
  - 実写・写真、速度優先（420）→ SVT-AV1
  - アニメ・イラスト、画質最優先（444）→ libaom
- SVT-AV1 の品質は CRF で指定する。実写・写真は `crf=11`（libaom の `cq-level=22` と同等）。
  速度優先は libaom と同じく advanced option を渡さず `-q` に従わせる。
- `avifYuv` と `avifCodec` の対応が壊れないことを単体テストで担保する。
  SVT を使う種別が 444 を指定するとエンコードに失敗するため。

## 代替案

- SVT-AV1 に全置換し、444 指定を 420 へ変える
  - 却下: イラストの色度品質が約 1.2dB 下がる。画質仕様の変更を伴う。
- libaom のまま据え置く
  - 却下: 実写・写真で 4.5 倍の速度差があり、利用できる改善を見逃す。
- rav1e を使う
  - 却下: 未調査。SVT-AV1 との速度・画質の比較が取れていない。

## 結果

- 実写・写真と速度優先の AVIF エンコードが速くなり、実写・写真はファイルサイズも同程度か小さい。
- アニメ・イラストと画質最優先の出力仕様（444、libaom）は変えない。
- バイナリは 8.3MB → 12MB に増える。依存は `libSystem` / `libc++` のままで配布条件は変わらない。
- 単体テスト: `ConvertPipelineTests.avifencArgs`、`ConvertPipelineTests.avifCodecMatchesYuv`。
- 実装箇所:
  - `TreeImageOptimizer/TreeImageOptimizer/Services/CompressionService.swift`
  - `tools/libavif/bin/macos/avifenc`

## ビルド方法

```shell
cmake -S libavif -B build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DAVIF_BUILD_APPS=ON -DAVIF_BUILD_EXAMPLES=OFF -DAVIF_BUILD_TESTS=OFF \
  -DAVIF_CODEC_AOM=LOCAL -DAVIF_CODEC_SVT=LOCAL -DAVIF_CODEC_DAV1D=OFF \
  -DAVIF_ZLIBPNG=LOCAL -DAVIF_JPEG=LOCAL -DAVIF_LIBYUV=LOCAL
cmake --build build --target avifenc -j 8
```

`AVIF_CODEC_DAV1D=OFF` にしているのは `avifenc` が AVIF を入力に取らないため。
dav1d を入れると ninja が必要になる。
