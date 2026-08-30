# アプリケーションのリリースフロー

## 目的

GitHub上で管理するソースコードから、検証済みのmacOSアプリケーションをGitHub Releasesへ公開し、利用者が更新確認できる状態にする。

リリース処理では、以下を満たすことを重視する。

- リリースされるソースコードと成果物の内容を一致させる。
- アプリケーションのバージョンとGitHub Releasesのタグを一致させる。
- **手動作業を「PRマージ」と「GitHub Actionsの実行ボタン押下（入力なし）」の2ステップに限定する。**
- バージョン番号の読取、タグ作成、テスト、ビルド、パッケージング、Release作成、ノート生成はすべてGitHub Actionsで自動化する。
- 失敗したリリースを利用者へ公開しない。

---

## 全体フロー概要

```text
1. [手動] feature/* または fix/* で開発・pubspec.yamlのバージョン更新
   ↓ PR作成
2. [自動] GitHub Actions CI（analyze / test / build）が通過
   ↓ レビュー・マージ
3. [手動] main ブランチへマージ
   ↓
4. [手動] GitHub Web画面の Actions タブから「Release」の [Run workflow] をクリック（入力不要）
   ↓
5. [自動] GitHub Actions Releaseワークフローが全自動実行
   ├─ pubspec.yaml からバージョン（例: 0.0.1）を自動取得
   ├─ タグの二重作成チェック
   ├─ flutter analyze & flutter test
   ├─ macOS Releaseビルド
   ├─ .app を .zip へアーカイブ & SHA-256 チェックサム生成
   ├─ main 上に Git タグ（v0.0.1）を自動作成・push
   └─ GitHub Release を自動作成（成果物添付・リリースノート自動生成）
```

---

## ブランチ構成

### `main`

- リリース候補となる安定版ブランチ。
- 直接pushは禁止する。
- 必ずPR経由でマージする。

### `feature/*`

- 機能追加用のブランチ。
- 1つの変更単位でPRを作成する。

### `fix/*`

- バグ修正用のブランチ。

---

## バージョン管理

### 管理元

アプリケーションのバージョンは `pubspec.yaml` の `version` を唯一の管理元とする。

```yaml
version: 0.0.1+1
```

- `0.0.1`: ユーザーへ表示するセマンティックバージョン（Major.Minor.Patch）。
- `1`: macOS Bundleのビルド番号。

About画面のバージョン表示は `package_info_plus` でBundleのバージョンを取得する。ソースコード内にアプリバージョンを重複定義しない。

### バージョンの決め方（セマンティックバージョニング）

- `Major`: 互換性を保証できない大きな変更。
- `Minor`: 後方互換性を維持した機能追加。
- `Patch`: バグ修正や小さな改善。

Stable版（正式版）になるまでは `0.x.y` を使用する。

| バージョン例 | 意味 |
| :--- | :--- |
| `0.0.1+1` | 初期開発版 |
| `0.0.2+2` | 開発版のバグ修正・小さな改善 |
| `0.1.0+3` | 開発版の機能追加 |
| `1.0.0+4` | 正式版の初回リリース |

> **重要: ビルド番号（`+N`）はリリースごとに必ずインクリメントする。**
>
> 自動アップデート（`desktop_updater`）は `buildNumber`（ビルド番号）を主に比較する。
> そのため、セマンティックバージョンを上げてもビルド番号が同じだと、更新が検出されない。
>
> 例:
> - `v0.0.2` → `0.0.2+2`（ビルド番号 2）
> - `v0.0.3` → `0.0.3+3`（ビルド番号 3）
> - `v0.0.4` → `0.0.4+4`（ビルド番号 4）

### タグとの対応

`pubspec.yaml` のバージョン `0.0.1+1` に対して、自動生成されるGitタグは `v0.0.1` とする。

```text
pubspec.yaml:   0.0.1+1
Git tag:         v0.0.1
Bundle version:  0.0.1
Bundle build:    1
```

---

## リリースの具体的手順

### ステップ1: 開発とバージョン更新（PR作成）

1. `feature/*` または `fix/*` ブランチで機能実装・修正を行う。
2. 今回のリリース内容に合わせて `pubspec.yaml` の `version` を更新する（例: `0.0.1+1` → `0.0.2+2`）。
3. PRを作成し、CI（`.github/workflows/ci.yml`）が通過したことを確認して `main` へマージする。

### ステップ2: GitHub Actionsでワンクリックリリース

1. GitHubリポジトリの **「Actions」** タブを開く。
2. 左メニューから **「Release」** ワークフローを選択する。
3. 右上の **[Run workflow]** ボタンをクリックする（`main` ブランチのまま実行）。
   - **初回リリース時のみ**: `initialize_feed` を `true` にする（ホスト上に `app-archive.json` がまだ存在しないため）。
   - 2回目以降は `initialize_feed` を `false`（デフォルト）で実行する。
    4. ワークフローが自動的に以下を完了する:
   - `pubspec.yaml` からバージョンを読み取る
   - 既存タグとの重複を検証
   - 静的解析・テストを実行
   - desktop_updater 用の配布物（`app-archive.json` / `release.json` / zip）を生成し、
     **GitHub Pages（gh-pages ブランチ）** へ自動デプロイ
   - 配布用 `.zip` と SHA-256 チェックサムを生成
   - `v0.0.2` タグを自動作成してpush
   - GitHub Releases を作成し、成果物を添付・リリースノートを自動生成

---

## 自動化ワークフロー一覧

### 1. CI ワークフロー (`.github/workflows/ci.yml`)

- **トリガー**: `main` へのPR作成・更新、および `main` へのpush
- **処理内容**:
  - Flutter環境セットアップ（FVM指定バージョン `3.47.1`）
  - 依存解決 (`flutter pub get`)
  - 静的解析 (`flutter analyze`)
  - ユニット & ウィジェットテスト (`flutter test`)
  - macOS Releaseビルドの検証 (`flutter build macos --release`)

### 2. Release ワークフロー (`.github/workflows/release.yml`)

- **トリガー**: `workflow_dispatch`（手動実行、`initialize_feed` の入力あり — 初回のみ `true`）
- **処理内容**:
  - `pubspec.yaml` からセマンティックバージョンとビルド番号を抽出
  - タグ存在チェック（同名タグが既に存在する場合は多重リリース防止のためエラー終了）
  - 静的解析とテストの実行
  - リリース署名鍵（`DESKTOP_UPDATER_KEY_BUNDLE` + `DESKTOP_UPDATER_KEY_PASSPHRASE`）を import
  - desktop_updater の `publish` で .app を zip 化・配布物を生成
  - `app-archive.json` / `release.json` / zip を **gh-pages ブランチ** へ push（GitHub Pages で配信）
  - 手動インストール用 `.app` の `.zip` アーカイブ化および SHA-256 チェックサム生成
  - Gitタグ（`vX.Y.Z`）の自動作成とリモートへのpush
  - `gh release create` による GitHub Release 作成（成果物添付・リリースノート自動生成）

### 3. リリースノート設定 (`.github/release.yml`)

GitHubの自動リリースノート生成において、PRのラベルに応じて以下のように分類する:

- ✨ 新機能 (Features): `feature`, `enhancement`
- 🐛 バグ修正 (Bug Fixes): `fix`, `bug`
- ⚡ パフォーマンス・改善 (Improvements): `performance`, `improvement`, `refactor`
- 📦 依存パッケージ更新 (Dependencies): `dependencies`
- 📝 ドキュメント (Documentation): `documentation`, `docs`
- 🔧 その他 (Other Changes): その他すべてのPR

---

## GitHub Releases の成果物構成

Releaseには以下が自動的に含まれる:

- タグ: `v0.0.2`
- タイトル: `Tree Image Optimizer v0.0.2`
- 配布用アーカイブ: `Tree-Image-Optimizer-v0.0.2-macos.zip`
- チェックサムファイル: `SHA256SUMS.txt`
- リリースノート（PR履歴から自動分類・生成）

加えて、自動アップデート用の配布物（desktop_updater 用）は **GitHub Pages** に公開される:

- `https://treetips.github.io/tree-image-optimizer/app-archive.json`
- `https://treetips.github.io/tree-image-optimizer/releases/<version>/macos/release.json`
- `https://treetips.github.io/tree-image-optimizer/releases/<version>/macos/<zip>`

---

## 失敗時の対応

### CI / リリースビルド失敗時

- ビルドやテストが失敗した場合、Releaseワークフローは途中で安全に停止し、GitタグやGitHub Releaseは作成されない。
- 失敗原因を修正するPRを作成し、`main` にマージ後、再度 [Run workflow] を実行する。

### Release作成後の不具合対応

1. 公開済みのRelease成果物を直接上書き・差し替えない。
2. 重大な不具合がある場合は、GitHub上で対象Releaseを一時的にDraftにするか削除する。
3. バグ修正を行い、Patchバージョン（例: `0.0.2` → `0.0.3`）を上げたPRを `main` にマージする。
4. 再度 [Run workflow] を実行して新バージョンのReleaseを公開する。

---

## 配布時の注意事項

現在は署名なし（unsigned）で配布しています。以下の制限があります：

- **Gatekeeper 警告**: ユーザーが初回起動時に「開く」ボタンをクリックする必要がある
- **自動アップデートの制限**: `desktop_updater` の `verifyMacOSNativeGates` が `spctl --assess` で署名を検証するため、自動インストールが失敗する場合がある
- **手動インストール**: ユーザーは `右クリック > 開く` でアプリを起動する必要がある

将来的に Apple Developer Program（年額 $99）に加入し、Developer ID Application 証明書で署名・notarize することで、これらの制限を解消できます。
