# setup.shで.vscode/extensions.jsonからVSCode拡張を導入する

## ステータス

- 承認済み (Accepted)

## 背景・課題

VSCode拡張の導入は手作業で、環境ごとに必要な拡張が揃わなかった。
リポジトリには推奨拡張の`.vscode/extensions.json`があるが、VSCodeが表示する
通知を個人が許可するだけの扱いで、セットアップ手順に反映されていない。

## 決定

- `setup.sh`に「VSCode Extension のインストール」を追加し、jqで
  `.vscode/extensions.json`の`recommendations`を列挙して`code --install-extension`で
  全件導入する。導入済みの拡張はスキップされるため、何度実行しても同じ結果になる。
- 拡張の正は`.vscode/extensions.json`に置き、追加・削除はこのファイルで行う。
- `code`コマンドが無い環境ではエラーにせずスキップする。
  VSCodeを使わない環境でもツールのセットアップを完結させるため。

## 代替案

- BrewfileのVSCode拡張エントリ（`brew bundle add --vscode`）で管理する
  - 却下: 拡張の情報源がBrewfileと`.vscode/extensions.json`に分かれ、
    VSCodeの「ワークスペースの推奨拡張」と食い違う。extensions.jsonに一本化する。
- `code`が無い場合はエラーで終了する
  - 却下: VSCodeを使わない開発環境で、拡張と関係ないツール導入まで失敗する。

## 結果

- `./setup.sh`の実行だけで開発ツール・git hooks・VSCode拡張の導入が揃う。
- 実装箇所: `setup.sh`。
