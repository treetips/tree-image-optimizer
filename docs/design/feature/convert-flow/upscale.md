# アップスケール

## ✳️ upscayl-bin

### ✏️ コマンド

```shell
cd ~/Library/Application Support/tree-image-optimizer/tools/upscal/bin
upscayl-bin \
  -i "${INPUT}" \
  -o "${OUTPUT}" \
  -s "${SCALE}" \
  -m "${MODELS_DIR}" \
  -n "${MODEL}"
```

### ✏️ help

```
❯ ./upscayl-bin -h
🚀 Starting Upscayl - Copyright © 2024
Usage: upscayl-bin -i infile -o outfile [options]...

  -h                   show this help
  -i input-path        input image path (jpg/png/webp) or directory
  -o output-path       output image path (jpg/png/webp) or directory
  -z model-scale       scale according to the model (can be 2, 3, 4. default=4)
  -s output-scale      custom output scale (can be 2, 3, 4. default=4)
  -r resize            resize output to dimension (default=WxH:default), use '-r help' for more details
  -w width             resize output to a width (default=W:default), use '-r help' for more details
  -c compress          compression of the output image, default 0 and varies to 100
  -t tile-size         tile size (>=32/0=auto, default=0) can be 0,0,0 for multi-gpu
  -m model-path        folder path to the pre-trained models. default=models
  -n model-name        model name (default=realesrgan-x4plus, can be realesr-animevideov3 | realesrgan-x4plus-anime | realesrnet-x4plus or any other model)
  -g gpu-id            gpu device to use (default=auto) can be 0,1,2 for multi-gpu
  -j load:proc:save    thread count for load/proc/save (default=1:2:2) can be 1:2,2,2:2 for multi-gpu
  -x                   enable tta mode
  -f format            output image format (jpg/png/webp, default=ext/png)
  -v                   verbose output
```

## ✳️ Real-CUGAN

### ✏️ コマンド

```shell
cd tools/realcugan/bin/macos
realcugan-ncnn-vulkan \
  -i "${INPUT}" \
  -o "${OUTPUT}" \
  -s "${SCALE}" \
  -n "${NOISE_LEVEL}" \
  -m "${MODELS_DIR}"
```

- `${SCALE}` は `2` 〜 `4` を指定します。1xモデルが存在しないため `1` は使えません。
- `${NOISE_LEVEL}` は選択したモデルから導出します。`conservative` = `-1`、`no-denoise` = `0`、`denoise1x`/`denoise2x`/`denoise3x` = `1`/`2`/`3` です。`-n` の数値とモデル名は直感と異なる対応のため、UIではモデル名を直接扱いSwift側で導出します。
- `${MODELS_DIR}` は `tools/realcugan/models-se` など上流配布物のフォルダ名をそのまま渡します。フォルダ名を変えるとバイナリの前処理量判定が `(unknown model dir type)` で失敗します。
- 実行前にモデルの `.param` と `.bin` が揃っていることを確認します。欠けていると終了コード0で黒画像を生成するためです。
- 実行後に出力ファイルの寸法が入力の `${SCALE}` 倍であることを検証します。

### ディレクトリ一括実行

`upscayl-bin` と `realcugan-ncnn-vulkan` は `-i` / `-o` にディレクトリを受け付けます。
アプリは最大4ファイルを1バッチにまとめ、`0000.png` のような連番を付けた一時入力
ディレクトリを渡して1プロセスで処理します。モデル読み込みとMoltenVK初期化の固定費を
ファイルごとに払わないためです。

- 入力は一時ディレクトリへhard linkし、異なるボリュームのときだけコピーします。
- シンボリックリンクは `upscayl-bin` のディレクトリ走査で無視されるため使いません。
- プロセスの終了コードだけでなく、出力ファイルごとに存在と寸法を検証します。

詳細は [ADR 0035](../../adr/0035-upscale-directory-batch.md) を参照してください。

### ✏️ help

```
❯ ./realcugan-ncnn-vulkan -h
Usage: realcugan-ncnn-vulkan -i infile -o outfile [options]...

  -h                   show this help
  -v                   verbose output
  -i input-path        input image path (jpg/png/webp) or directory
  -o output-path       output image path (jpg/png/webp) or directory
  -n noise-level       denoise level (-1/0/1/2/3, default=-1)
  -s scale             upscale ratio (1/2/3/4, default=2)
  -t tile-size         tile size (>=32/0=auto, default=0) can be 0,0,0 for multi-gpu
  -c syncgap-mode      sync gap mode (0/1/2/3, default=3)
  -m model-path        realcugan model path (default=models-se)
  -g gpu-id            gpu device to use (-1=cpu, default=auto) can be 0,1,2 for multi-gpu
  -j load:proc:save    thread count for load/proc/save (default=1:2:2) can be 1:2,2,2:2 for multi-gpu
  -x                   enable tta mode
  -f format            output image format (jpg/png/webp, default=ext/png)
```