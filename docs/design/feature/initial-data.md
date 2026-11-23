# 初期データ

画面の操作ではなく、リポジトリへ最初から配置しておく外部ツールのデータです。
`tools/` 配下が開発時の正本で、実行時に
`~/Library/Application Support/tree-image-optimizer/tools/` へ展開されます。
アプリ本体の配布ZIPには同梱せず、Releaseではツール単位のZIPとして配布します
（[ADR 0064](../../adr/0064-separate-tools-distribution/0064-separate-tools-distribution.md)）。

## 共通ルール

- macOS専用のため、バイナリは `bin/macos/` に置きます（Windows/Linux版は持たない）。
- ライセンスファイルがある場合は、ツールのルートフォルダに配置します。
- バージョンは各ツールの `.version` に1行で書きます。`.version` を持たないツールは
  アプリ内のバージョン定数を正本にします。
- アップデートする際は元のファイルを全削除してから置き換えます。

## upscayl-bin

- [GitHub Releasesのlatestタグ](https://github.com/upscayl/upscayl-ncnn/releases/latest)
  からダウンロードし、解凍したものを配置します。
- `tools/upscal/bin/upscayl-bin` を配置します。
- `tools/upscal/.version` にバージョン（例: `upscayl-bin-20251207-174704`）を書きます。
- 現在のバージョンから更新されていた場合のみ、`.version` を更新します。

## upscale models

- [Gitプロジェクトのzipファイル](https://github.com/upscayl/custom-models/archive/refs/heads/main.zip)
  からダウンロードし、解凍したものを配置します。

- `tools/upscal/models/` 配下に `.bin` と `.param` のペアを配置します。

- モデルは全ファイルを配置します。

  ```text
  4xHFA2k.bin
  4xHFA2k.param
  4xLSDIR.bin
  4xLSDIR.param
  realesr-animevideov3-x2.bin
  realesr-animevideov3-x2.param
  realesr-animevideov3-x4.bin
  realesr-animevideov3-x4.param
  ...
  ```

- アプリは `.bin` を走査してプルダウンの選択肢を作ります。

## Real-CUGAN

- [GitHub Releasesの20220728タグ](https://github.com/nihui/realcugan-ncnn-vulkan/releases/tag/20220728)
  の `realcugan-ncnn-vulkan-20220728-macos.zip` を使用します。

- `tools/realcugan/` に次の構成で配置します。

  ```text
  tools/realcugan/
  ├── bin/macos/realcugan-ncnn-vulkan
  ├── models-se/
  ├── LICENSE
  └── .version
  ```

- ZIPに含まれる `models-se` をそのまま配置します。フォルダ名はバイナリが前処理の
  パディング量の判定に使うため、変更しないでください。

- ライセンスファイル（`LICENSE`、nihuiのMIT）も配置します。

- `.version` にバージョン（例: `realcugan-ncnn-vulkan-20220728`）を書きます。

- 起動時に未配置なら、[GitHub Releases](https://github.com/nihui/realcugan-ncnn-vulkan/releases)
  から自動ダウンロードします。ユーザーによる手動配置は不要です。

## JPEG（jpegoptim）

- `tools/jpegoptim/bin/macos/jpegoptim` を配置します。
- バージョンはアプリ内のJPEGツールのバージョン定数（例: `v1.5.6`）で管理します。

## PNG（pngoptim）

- `tools/pngoptim/bin/macos/pngoptim` を配置します。
- バージョンはアプリ内のPNGツールのバージョン定数（例: `v0.6.3`）で管理します。

## JPEG XL（libjxl）

- v0.13.0 はソースからビルドし、`CJXL_ENABLE_SHARED=ON` 相当で生成した
  `cjxl` と依存 dylib をまとめて配置します（[ADR 0056](../../adr/0056-libjxl-source-build.md)）。
- `tools/libjxl/bin/macos/` に `cjxl` と `*.dylib` を配置します。
  dylib は `@loader_path` で解決するため、`cjxl` と同じ階層に置きます
  （[ADR 0017](../../adr/0017-bundle-libjxl-dylibs/0017-bundle-libjxl-dylibs.md)）。
- `tools/libjxl/.version` にバージョン（例: `v0.13.0`）を書きます。

## AV1（libavif）

- [GitHub Releasesのlatestタグ](https://github.com/AOMediaCodec/libavif/releases/latest)
  からソースを取得し、SVT-AV1を含めて自前でビルドします。
  - 公開アーティファクトには SVT-AV1 が含まれていないため、そのままでは使えない。
  - ビルド手順は [ADR 0037](../../adr/0037-hybrid-av1-encoder.md) を参照してください。
- `tools/libavif/bin/macos/avifenc` を配置します。
  libaom と SVT-AV1 の両方を静的リンクしたものを置きます。
- `tools/libavif/.version` にバージョン（例: `v1.4.2`）を書きます。

## WebP（libwebp）

- Google Storage の
  `https://storage.googleapis.com/downloads.webmproject.org/releases/webp/` から
  macOS用アーカイブを取得します。
- `tools/libwebp/bin/macos/cwebp` を配置します。
- バージョンはアプリ内のWebPツールのバージョン定数（例: `1.6.0`）で管理します。
- デコーダ（`dwebp` 等）は同梱しません。
