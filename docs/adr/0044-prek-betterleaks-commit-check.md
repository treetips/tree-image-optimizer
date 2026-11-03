# commit時にprekでrumdlのフォーマットとBetterleaksの漏洩チェックを行う

## ステータス

- 承認済み (Accepted)

## 背景・課題

Markdownの整形（rumdl）と機密情報の漏洩チェックはAGENTS.mdの手順に依存し、
実行の有無が開発者の記憶に左右されていた。rumdlの違反はCIで後から判明するが、
機密情報の混入は一度commitを許すと検知手段が無い。
また、GitHub Desktop等のGUIからcommitする場合、hookプロセスのPATHには
Homebrewのbinが含まれないため、hookからツールを直接呼んでは起動できない。

## 決定

- 開発ツール（rumdl・prek・betterleaks）は`Brewfile`で管理し、`./setup.sh`から
  `brew bundle install`で導入する。git hooksフレームワークには
  [prek](https://prek.j178.dev/)を採用し、設定をリポジトリ直下の`prek.toml`で管理する。
  Git shimはリポジトリごとに`prek install`で`.git/hooks/pre-commit`へ設置する
  （Git LFSの既存フックはそのまま維持する）。
- commit時に2つのhookを実行する。
  - `rumdl fmt`によるMarkdownのフォーマット。整形で差分が出た場合はcommitを中断し、
    変更を確認して再ステージさせる（prekのformatter前提の挙動）。
  - [Betterleaks](https://github.com/betterleaks/betterleaks)による機密情報チェック。
    検査対象はこのcommitが持ち込む差分だけにし、`git --pre-commit --staged`で
    ステージ済み差分を検査する（v1の公式pre-commit連携と同じ形式）。
- ツールの起動は`tools/rumdl.sh`と`tools/betterleaks.sh`を経由する。
  ラッパーは環境変数（`RUMDL_BIN`・`BETTERLEAKS_BIN`）→PATH→既知のインストール先の
  順に実体を探し、GUIから呼ばれても起動できるようにする。
- BetterleaksはHomebrewのv1（v1.9.0 stable）を使う。v2はまだHomebrewに提供されておらず、
  手動配置ではセットアップが再現しないため。v2がHomebrewに入ったらhookの引数を
  v2形式（`betterleaks stdin --git-diff --redact`）に更新して移行する。

## 代替案

- pre-commit（Python）を使う
  - 却下: Pythonランタイムの導入が必要。prekは単一バイナリでpre-commit互換の
    設定やhookリポジトリをそのまま使える。
- hookからツールを直接呼び、PATHに頼る
  - 却下: GitHub Desktop等からcommitするとコマンドが見つからず、hookが必ず失敗する。
- Betterleaks v2 RCを手動で配置する
  - 却下: Homebrewに提供されておらず、クローン後のセットアップが再現しない。
    ツールの導入はBrewfileで揃え、v2はHomebrew提供後に移行する。
- commitのたびにリポジトリ全体の履歴を走査する
  - 却下: 毎回の走査は遅く、既知の過去findingも再報告される。全体の走査は
    必要に応じて`tools/betterleaks.sh git .`で手動実行する。

## 結果

- commit時にMarkdownの整形と機密情報チェックが自動で実行され、手順の属人性が消える。
- GUI・ターミナルのどちらからcommitしても同じhookが動く。
- 実装箇所: `Brewfile`・`setup.sh`・`prek.toml`・`tools/rumdl.sh`・`tools/betterleaks.sh`。
- hookの手動実行は`prek run --all-files`。
