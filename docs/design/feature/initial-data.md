# 初期データ

画面の操作ではなく、プロジェクトを作成する際に最初からプロジェクト内にで配置しておくデータです。

## upscale-bin

- [GitHub Releasesのlatestタグ](https://github.com/upscayl/upscayl-ncnn/releases/latest) からダウンロードし、解凍したものを配置します。
- `~/Library/Application Support/tree-image-optimizer/tools/upscal/bin` 配下にバイナリを配置してください。（例）`~/Library/Application Support/tree-image-optimizer/tools/upscal/bin/upscayl-bin`
- ライセンスファイルが有る場合、 `~/Library/Application Support/tree-image-optimizer/tools/upscal` フォルダに同梱してください。
- バイナリは以下だけを抽出してプロジェクトに同梱してください。
  - upscayl-bin
- `~/Library/Application Support/tree-image-optimizer/tools/upscal/.version` を作成し、現在のバージョンを書き込んでください。（例）upscayl-bin-20251207-174704
  - 現在のバージョンから更新されていた場合のみ、 `.version` を更新してください。
- アップデートする際は、元のファイルを全削除してから更新してください。

## upscale models

- [Gitプロジェクトのzipファイル](https://github.com/upscayl/custom-models/archive/refs/heads/main.zip) からダウンロードし、解凍したものを配置します。
- `~/Library/Application Support/tree-image-optimizer/tools/upscal/models` 配下にバイナリを配置してください。（例）`~/Library/Application Support/tree-image-optimizer/tools/upscal/models/realesr-animevideov3-x4.bin`
- `models` は、例えば以下のようなファイルが含まれます。
  ```
  ❯ ll
  Permissions Size User   Date Modified Git Name
  .rw-r--r--@  67M tester  2 Aug 01:03   --  4x_NMKD-Siax_200k.bin
  .rw-r--r--@ 108k tester  2 Aug 01:03   --  4x_NMKD-Siax_200k.param
  .rw-r--r--@  67M tester  2 Aug 01:03   --  4x_NMKD-Superscale-SP_178000_G.bin
  .rw-r--r--@ 108k tester  2 Aug 01:03   --  4x_NMKD-Superscale-SP_178000_G.param
  .rw-r--r--@  33M tester  2 Aug 01:03   --  4xHFA2k.bin
  .rw-r--r--@ 108k tester  2 Aug 01:03   --  4xHFA2k.param
  .rw-r--r--@  33M tester  2 Aug 01:03   --  4xLSDIR.bin
  .rw-r--r--@ 108k tester  2 Aug 01:03   --  4xLSDIR.param
  .rw-r--r--@ 1.2M tester  2 Aug 01:03   --  4xLSDIRCompactC3.bin
  .rw-r--r--@ 2.8k tester  2 Aug 01:03   --  4xLSDIRCompactC3.param
  .rw-r--r--@  33M tester  2 Aug 01:03   --  4xLSDIRplusC.bin
  .rw-r--r--@ 108k tester  2 Aug 01:03   --  4xLSDIRplusC.param
  .rw-r--r--@  33M tester  2 Aug 01:03   --  4xNomos8kSC.bin
  .rw-r--r--@ 108k tester  2 Aug 01:03   --  4xNomos8kSC.param
  .rw-r--r--@ 1.2M tester  2 Aug 01:03   --  realesr-animevideov3-x2.bin
  .rw-r--r--@ 3.2k tester  2 Aug 01:03   --  realesr-animevideov3-x2.param
  .rw-r--r--@ 1.2M tester  2 Aug 01:03   --  realesr-animevideov3-x3.bin
  .rw-r--r--@ 3.2k tester  2 Aug 01:03   --  realesr-animevideov3-x3.param
  .rw-r--r--@ 1.2M tester  2 Aug 01:03   --  realesr-animevideov3-x4.bin
  .rw-r--r--@ 3.1k tester  2 Aug 01:03   --  realesr-animevideov3-x4.param
  .rw-r--r--@ 2.4M tester  2 Aug 01:03   --  RealESRGAN_General_WDN_x4_v3.bin
  .rw-r--r--@ 5.0k tester  2 Aug 01:03   --  RealESRGAN_General_WDN_x4_v3.param
  .rw-r--r--@ 2.4M tester  2 Aug 01:03   --  RealESRGAN_General_x4_v3.bin
  .rw-r--r--@ 5.0k tester  2 Aug 01:03   --  RealESRGAN_General_x4_v3.param
  .rw-r--r--@  33M tester  2 Aug 01:03   --  uniscale_restore.bin
  .rw-r--r--@ 108k tester  2 Aug 01:03   --  uniscale_restore.param
  .rw-r--r--@  33M tester  2 Aug 01:03   --  unknown-2.0.1.bin
  .rw-r--r--@ 140k tester  2 Aug 01:03   --  unknown-2.0.1.param
  ```
- ライセンスファイルが有る場合、 `~/Library/Application Support/tree-image-optimizer/tools/upscal` フォルダに同梱してください。
- モデルファイルは全ファイル同梱してください。

## Real-CUGAN

- 起動時に未配置なら、[GitHub Releasesの20220728タグ](https://github.com/nihui/realcugan-ncnn-vulkan/releases/tag/20220728) から `realcugan-ncnn-vulkan-20220728-macos.zip` をダウンロードし、`tools/realcugan` へ自動展開します。ユーザーによる手動配置は不要です。
- 開発環境ではリポジトリ同梱の `tools/realcugan`（初回起動より先に存在する場合）がそのまま使われます。
- ZIPに含まれる `models-se` / `models-pro` / `models-nose` はすべて配置します。フォルダ名はバイナリが前処理のパディング量の判定に使うため、`models-se` 等のまま変更しないでください。
- ライセンスファイル（`LICENSE`、nihuiのMIT）はZIPから `tools/realcugan` へ配置します。
- `tools/realcugan/.version` にバージョン（例）`realcugan-ncnn-vulkan-20220728` を書き込みます。
- アップデートする際は、元のファイルを全削除してから更新してください。

## JPEG XL

- [GitHub Releasesのlatestタグ](https://github.com/libjxl/libjxl/releases/latest) からダウンロードします。
- 注意点として、GitHub Releasesには `macOS版が無い` です。
- `linux-artifacts.zip` `macOS-artifacts.zip` `windows-artifacts.zip` 等と3つのOSそれぞれのアーティファクトが有るので、それぞれダウンロードし、解凍したものを配置します。
- `~/Library/Application Support/tree-image-optimizer/tools/libjxl/bin` 配下にバイナリを配置してください。
  - （例）`~/Library/Application Support/tree-image-optimizer/tools/libjxl/bin/macos/cjxl`
  - （例）`~/Library/Application Support/tree-image-optimizer/tools/libjxl/bin/linux/cjxl`
  - （例）`~/Library/Application Support/tree-image-optimizer/tools/libjxl/bin/windows/cjxl.exe`
- ライセンスファイルが有る場合、 `~/Library/Application Support/tree-image-optimizer/tools/libjxl` フォルダに同梱してください。
- バイナリは以下だけを抽出してプロジェクトに同梱してください。
  - cjxl （エンコード用）
- `~/Library/Application Support/tree-image-optimizer/tools/libjxl/.version` を作成し、現在のバージョンを書き込んでください。（例）v0.12.0
  - 現在のバージョンから更新されていた場合のみ、 `.version` を更新してください。
- アップデートする際は、元のファイルを全削除してから更新してください。

## AV1

- [GitHub Releasesのlatestタグ](https://github.com/AOMediaCodec/libavif/releases/latest) からソースを取得し、SVT-AV1を含めて自前でビルドします。
  - 公開アーティファクトには SVT-AV1 が含まれていないため、そのままでは使えない。
  - ビルド手順は [ADR 0037](../../adr/0037-hybrid-av1-encoder.md) を参照してください。
- `~/Library/Application Support/tree-image-optimizer/tools/libavif/bin` 配下にバイナリを配置してください。
  - （例）`~/Library/Application Support/tree-image-optimizer/tools/libavif/bin/macos/avifenc`
  - （例）`~/Library/Application Support/tree-image-optimizer/tools/libavif/bin/linux/avifenc`
  - （例）`~/Library/Application Support/tree-image-optimizer/tools/libavif/bin/windows/avifenc.exe`
- ライセンスファイルが有る場合、 `~/Library/Application Support/tree-image-optimizer/tools/libavif` フォルダに同梱してください。
- バイナリは以下だけを抽出してプロジェクトに同梱してください。
  - avifenc （エンコード用。libaom と SVT-AV1 の両方を静的リンクしたもの）
- `~/Library/Application Support/tree-image-optimizer/tools/libavif/.version` を作成し、現在のバージョンを書き込んでください。（例）v1.4.2
  - 現在のバージョンから更新されていた場合のみ、 `.version` を更新してください。
- アップデートする際は、元のファイルを全削除してから更新してください。
