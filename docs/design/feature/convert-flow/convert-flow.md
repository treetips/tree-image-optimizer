# 変換処理フロー

1. [対象ファイル一覧を選定](./input-folder-selection.md)
1. [変換実行](./execute-convert.md)
  1. [アップスケール](./upscale.md)
  1. [画像圧縮](./compression.md)
1. [ファイル出力](./output-folder-selection.md)

## 並列処理の単位

3ファイルが対象の場合、以下の1行を並列の単位とします。

- `aaa.jpg` を `アップスケール` -> `圧縮` -> `出力` という順番で処理。
- `bbb.jpg` を `アップスケール` -> `圧縮` -> `出力` という順番で処理。
- `ccc.jpg` を `アップスケール` -> `圧縮` -> `出力` という順番で処理。

並列数が `3` の場合、`aaa.jpg` と `bbb.jpg` を並列に処理し、 `ccc.jpg` は待機。
`aaa.jpg` か `bbb.jpg` の一連の処理が終わったら、 `ccc.jpg` の処理が始まります。
