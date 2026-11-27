# GitHub運用ルール

GitHub 上の PR・ラベル・リリースに関するルールをまとめる。コミットメッセージやブランチ名など
Git の操作に関するルールは [Git運用ルール](./git.md) を参照する。

## ブランチ運用

- `main` への直接pushは禁止。必ず `feature/*` または `fix/*` ブランチから PR を作成する。
- `main` へは PR 経由でマージする。

## PR運用

- PRタイトルも Conventional Commits 形式を推奨する（例: `feat: 変換結果のサマリーを固定表示`）。
- PRタイトルの type 接頭辞から `.github/workflows/label-pr.yml` がラベルを自動付与する。接頭辞を正しく付ける。
- PRのラベルはリリースノートの自動分類（`.github/release.yml`）に利用されるため、適切なラベルを付与する。
- PR作成前に [コードレビュー](./code-review.md) を実施する。対象はSwift関連のみで、ドキュメントは不要。

## リリースタグ

- アプリ本体のタグは `vMajor.Minor.Patch` 形式（例: `v0.1.0`）とし、通常リリースとして公開する。
- ツールは `tools-latest` の事前リリースとして公開する。アプリの「Latest」を隠さないため、必ず事前リリースを維持する。
- アプリのタグはReleaseワークフロー、ツールのAssetsはRelease Toolsワークフロー（いずれも `workflow_dispatch`）で公開する。
  リリース手順の全体は [リリースフロー](./release-flow.md) を参照する。

## スタックプルリクエスト

- [stacked pull requests](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs) を使った方が効率が良い場合は使う。

## プルリクエストは自分でマージする

- エージェントがPRを作成した場合、CIが成功したらマージする。
- マージが成功したら、ローカルの該当ブランチを削除し、mainブランチをpullして最新化する。
