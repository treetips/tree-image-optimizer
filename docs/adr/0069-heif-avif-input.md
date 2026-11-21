# HEIF/HEIC/AVIF を入力フォーマットとして受け付ける

## ステータス

- 承認済み (Accepted)

## 背景・課題

入力フォーマットは `jpg` / `jpeg` / `png` / `webp` の4種のみだった。iPhone で撮影した
写真（HEIC）や近年の配信で増えている AVIF はそのまま扱えず、別途 JPEG/PNG へ変換してから
渡す必要があった。

外部アップスケーラ（`upscayl-bin` / `realcugan-ncnn-vulkan`）と各エンコーダ
（`cjxl` / `avifenc` / `cwebp` / `jpegoptim` / `pngoptim`）は HEIF/AVIF を直接読めない。
そのため、パイプラインへ入れる前に中間 PNG へデコードする必要がある。

## 決定

HEIF/HEIC/AVIF を入力として受け付け、アップスケールの**直前に中間 PNG へデコードする**。

### 対象と変換

- `TargetFiles.supportedExtensions` に `heic` / `heif` / `avif` を追加する。
- デコードは macOS の ImageIO（`CGImageSource`）で行い、先頭フレームを PNG へ書き出す。
  既存の `CompressionService.convertToPNG` を再利用する。
- デコードはアップスケールのステージング時（`prepareBatch`）と、
  超解像をかけない経路（`processResizeOnlyBatch`）の両方に挟む。

### 静止画前提の維持

HEIF/AVIF もアニメーション（イメージシーケンス）として扱わない。デコードは先頭フレームのみを
取り出すが、`UpscaleService.postVerify` が入力の総フレーム数を検査するため、
マルチフレーム入力は従来どおり検証で落ちる（ADR 0063）。実務上、iPhone の HEIC 写真や
一般的な静止 AVIF は総フレーム数が1であり、そのまま処理できる。

## 代替案

- **各エンコーダ・アップスケーラに直接 HEIF/AVIF を渡す**: 対応していないため不可。
- **入力フィルタで HEIF/AVIF を弾き続ける（現状）**: iPhone 写真を扱えない制約が残る。却下。
- **専用のデコーダを追加する**: ImageIO が対応しており、自前実装は不要。

## 結果

- iPhone の HEIC 写真と静止 AVIF をそのまま一括変換・かんたん変換へ渡せる。
- 中間 PNG へのデコード分の I/O が増えるが、静止画前提と既存パイプラインを保つ。
- 実装箇所: `TargetFiles.swift`、`ConvertOrchestratorWorkers.swift`、`docs/CONTEXT.md`。
