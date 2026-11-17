# コードレビューにOpen Code Reviewを導入する

## ステータス

- 承認済み (Accepted)

## 背景・課題

PRのレビューは人力で行っており、見る観点がレビューアによってばらつく。
AGENTS.md には「新しい技術的決定にはADRを書く」「既存テストを削除しない」「コメントはWhy not」
といった規約があるが、差分を読みながら毎回すべてを確認するのはコストが高い。
特に、規約違反（テストの削除、ADRなしの設計変更、`.env` の混入）は
レビューで見落とすと main に入ってしまう。

一方で、コードを外部のサービスへ送ることに抵抗がある。リポジトリ全体を
常時スキャンさせるのではなく、レビューしたい差分だけを、明示した操作のときだけ送りたい。

## 決定

- Alibaba の `ocr`（Open Code Review）CLI を、開発者ローカルのレビュー補助として導入する。
  `ocr review` は staged・unstaged・untracked の差分をレビューする。
- **CIには組み込まない**。OpenCode Go はコーディングエージェント向けの利用枠で、
  PRごとの自動実行は枠を消費しやすく、利用規約上の位置づけも自動レビュー用途を想定していない。
  自動レビューが必要になった時点で、別のモデル契約と合わせて改めて判断する。
- モデルは OpenCode Go の `deepseek-v4.1-flash` を既定にする。
  1Mコンテキスト・月100ドルの枠があり、通常のPRレビューでは枠を気にせず使える。
  重要な差分では `ocr config set model deepseek-v4-pro` で切り替える。
- 接続は OpenCode Go の OpenAI 互換エンドポイントをカスタムプロバイダとして登録する。
  - `url`: `https://opencode.ai/inference/go/openai/v1`
  - `protocol`: `openai`
  - `extra_headers`: `x-opencode-session={ocr_session_key}`（無いと400 `MissingSessionID` で拒否される）
- APIキーは macOS Keychain に置き、`api_key_cmd` から読む。
  キーはリポジトリにも `~/.opencodereview/config.json` にも書かない。
- レビューコメントの言語は日本語にする（`ocr config set language 日本語`）。
- プロジェクト固有のレビュー観点は `.opencodereview/rule.json` に置き、リポジトリで共有する。
  Swiftの並行性・外部プロセス起動・エラー処理、テストの削除、CIのXcode指定、ADRの有無を見る。

設定は各自の `~/.opencodereview/config.json` に保存され、リポジトリには含めない。
共有するのはルール（`.opencodereview/rule.json`）と手順（AGENTS.md）だけにする。

## 代替案

- GitHub Actions でPRごとに自動レビューする
  - 却下: OpenCode Go の枠をPRのたびに消費する。APIキーをSecretsに置く必要もあり、
    まずはローカルで効果を測ってから判断したい。
- GitHub Copilot のコードレビューや他社SaaSを使う
  - 却下: AGENTS.md の規約をレビュー観点として注入できず、リポジトリの前提
    （Swift 6 / macOS 26、ADR必須）を知らないまま指摘が返る。
- Claude Code などの汎用エージェントにレビューさせる
  - 却下: 対象ファイルの選別やコメント位置の決定をモデルに任せることになり、
    大きな差分でレビュー漏れや位置ズレが出やすい。`ocr` はこの部分を決定的な処理で行う。
- CIで全ファイルを `ocr scan` する
  - 却下: 差分のないコードまで毎回送ることになり、コストとノイズが大きい。

## 結果

- 開発者は `ocr`（`brew install` または `npm install -g @alibaba-group/open-code-review`）と
  OpenCode Go のAPIキーを各自用意する必要がある。手順は AGENTS.md に書く。
- レビューはローカル実行なので、CIの実行時間とコストは増えない。
- 指摘はレビューアの判断材料であり、そのまま適用しない。誤検知もある前提で扱う。
- ルールはリポジトリで共有されるため、レビュー観点を変えたいときは
  `.opencodereview/rule.json` のPRで議論できる。
- モデルの提供状況は変わる。`ocr llm test` が 403 を返す場合は、
  OpenCode Go のコンソールでモデルの提供状況を確認する。
