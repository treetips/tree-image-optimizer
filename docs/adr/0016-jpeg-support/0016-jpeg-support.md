# JPEG (libjpeg-turbo) サポート追加

## ステータス

- 承認済み (Accepted)

## 背景・課題

従来 JPEG XL と AV1 の2フォーマットのみ対応していた。
ユーザーから JPEG 形式での出力要望があったため、libjpeg-turbo を利用して
JPEG 圧縮機能を追加する。

## 決定

- `OutputFormat` enum に `jpeg('JPEG')` を追加する。
- エンコーダーとして libjpeg-turbo の `cjpeg` を利用する。
- バイナリは `tools/libjpeg/bin/{os}/cjpeg` に配置する。
- 品質は `cjpeg -quality N` (1-100) で指定する。
- 最適化種別に応じたスムージングパラメータを適用する。

### パラメータマッピング

| 最適化種別 | スムージング | 備考 |
|-----------|------------|------|
| アニメ     | 0          | そのまま出力 |
| 写真      | 0          | そのまま出力 |
| 速度優先   | 2          | 軽微なスムージングでノイズ低減 |
| 画質優先   | 0          | そのまま出力 |

## 代替案

- libjpeg のみを使用
  - 却下: SIMD 最適化がなく速度が劣るため。
- MozJPEG を使用
  - 却下: ビルドが複雑で、libjpeg-turbo と互換性があるため利点が少ない。

## 結果

- `OutputFormat.jpeg` が選択可能になる。
- 実装箇所: `compression_service.dart`, `path_service.dart`, `output_format.dart`
