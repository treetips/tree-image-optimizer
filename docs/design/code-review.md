# コードレビュー

## 環境

- [Open Code Review](https://open-codereview.ai/) でレビューする。
- 初回だけAPIキーを Keychain に登録し、`~/.opencodereview/config.json` を設定する。

## 運用

- 疎通確認: `ocr llm test`
- 実行: `ocr review`（ワークスペース）、`ocr review --from main --to <branch>`（ブランチ区間）
  重要な内容の際は `--effort high`、モデルを上げるときは `ocr config set model deepseek-v4-pro`。
- レビュー対象はSwift関連のみで、`.md` 等のドキュメントは不要。
  - `ocr` はMarkdownをレビューしない（`unsupported_ext`）。ドキュメントだけの変更では指摘が0件になる。
- レビューはPR作成前に実行する。
  - 指摘はそのまま適用せず、本当に必要かどうかを検討する。
- レビュー観点は `.opencodereview/rule.json` で共有。観点を変える場合はすぐに確認する。

## レビュー結果

- レビュー結果もgitで管理する。
- 指摘があった場合のみ、`docs/code-review/<yyyy-MM-dd>/<HH-mm-ss>/` 配下に保存する。
  - 日時部分には実行時の現在日時を入れる（`date +%Y-%m-%d/%H-%M-%S`）。
  - 指摘が無い場合はディレクトリを作らない。
- 正とする成果物は `review.md`。指摘の一覧に採否と、却下した場合はその理由を書き込む。
  - 再集計や比較を機械的に行いたい場合のみ、`ocr review --format json --output <dir>/review.json` の出力を併置する。
