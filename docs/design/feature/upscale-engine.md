# アップスケールエンジン

アップスケールは外部バイナリを外部プロセスとして実行する。エンジンは2種類で、
エンジン設定が設定値とUIの選択肢を兼ねる。

| エンジン      | バイナリ                | 拡大率 | モデル                      |
| :------------ | :---------------------- | :----- | :-------------------------- |
| `upscayl-bin` | `upscayl-bin`           | 1〜4   | `tools/upscal/models/*.bin` |
| `Real-CUGAN`  | `realcugan-ncnn-vulkan` | 2〜4   | `tools/realcugan/models-*`  |

初期値は `upscayl-bin`。Real-CUGANは1xモデルを持たないため、拡大率を2〜4に制限する。

## Real-CUGAN

### 実行コマンド

```shell
realcugan-ncnn-vulkan \
  -i "${INPUT}" \
  -o "${OUTPUT}" \
  -s "${SCALE}" \
  -n "${NOISE_LEVEL}" \
  -m "${MODELS_DIR}"
```

- `${SCALE}` は `2`〜`4`。1xモデルが存在しないため `1` は使えない。
- `${NOISE_LEVEL}` は選択したモデルから導出する。`conservative` = `-1`、
  `no-denoise` = `0`、`denoise1x` / `denoise2x` / `denoise3x` = `1` / `2` / `3`。
- `${MODELS_DIR}` は `models-se`、`models-pro`、`models-nose` のフォルダ名をそのまま渡す。
  フォルダ名を変えるとバイナリの前処理量判定が `(unknown model dir type)` で失敗する。

### モデル

同梱するのは `models-se` のみ。2x/3x/4xの主要な組み合わせをカバーする。
モデルIDは `models-se/up2x-conservative` のように
「フォルダ名 + ファイル名」で表し、設定JSONへ保存する。

- モデル一覧は `.param` と `.bin` が揃っているものだけを走査して作る。
- 選択中の拡大率に合うモデルだけを候補にする。
- 拡大率を変えて現在のモデルが存在しなくなった場合は、conservative
  （無ければ先頭）へ切り替える。
- エンジンごとに前回のモデルを復元し、片方の選択がもう片方へ影響しないようにする。
- 表示順はノイズ除去が弱い順（no-denoise → conservative → denoise1x → denoise2x →
  denoise3x）。ファイル名の辞書順や `-n` の値順では強弱と一致しないため、
  専用の並び順で並べ替える。

### 実行前後の検証

- 実行前に、対象モデルの `.param` と `.bin` が揃っていることを確認する。
  欠けていても終了コード0で黒画像を出力する組み合わせがあるため。
- 実行後に、出力ファイルの存在・サイズ・入力の `${SCALE}` 倍の寸法を検証する。

### 未配置時

Real-CUGANは必須ツールのため、`realcugan-ncnn-vulkan` が無い場合は起動時の
ブートストラップが修復する。修復に失敗すると再試行画面になり、アプリは操作できない。

バイナリはあるがモデルが揃っていない場合は、エンジン選択後に
`Real-CUGANのツールが配置されていないため、使用できません。` と表示し、
実行を無効化する。

## ディレクトリ一括実行

`upscayl-bin` と `realcugan-ncnn-vulkan` は `-i` / `-o` にディレクトリを受け付ける。
アプリは最大4ファイルを1バッチにまとめ、`0000.png` のような連番を付けた一時入力
ディレクトリを渡して1プロセスで処理する。モデル読み込みとMoltenVK初期化の固定費を
ファイルごとに払わないため。

- 入力は一時ディレクトリへhard linkし、異なるボリュームのときだけコピーする。
- シンボリックリンクは `upscayl-bin` のディレクトリ走査で無視されるため使わない。
- プロセスの終了コードだけでなく、出力ファイルごとに存在と寸法を検証する。

詳細は [ADR 0035](../../adr/0035-upscale-directory-batch.md) を参照する。

## 配布

`tools/realcugan` は次の構成で `tools/` に置き、Releaseではツール単位のZIPとして
配布する（[ADR 0064](../../adr/0064-separate-tools-distribution/0064-separate-tools-distribution.md)）。

```text
tools/realcugan/
├── bin/macos/realcugan-ncnn-vulkan
├── models-se/
│   ├── up2x-conservative.param
│   ├── up2x-conservative.bin
│   └── ...
├── LICENSE
└── .version
```

Real-CUGANは必須ツールとして扱う。バージョンの正本は `.version` で、
起動時のブートストラップと `tools-info.json` の差分更新がこの値を参照する。
