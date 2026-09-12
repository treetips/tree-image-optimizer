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
1. [手動] feature/* または fix/* で開発・Xcodeプロジェクトのバージョン更新
   ↓ PR作成
2. [自動] GitHub Actions CI（build / test）が通過
   ↓ レビュー・マージ
3. [手動] main ブランチへマージ
   ↓
4. [手動] GitHub Web画面の Actions タブから「Release」の [Run workflow] をクリック（入力不要）
   ↓
5. [自動] GitHub Actions Releaseワークフローが全自動実行
   ├─ Xcodeプロジェクトからバージョン（例: 0.1.0）とビルド番号（例: 1）を自動取得
   ├─ タグの二重作成チェック
   ├─ xcodebuild build & xcodebuild test
   ├─ macOS Releaseビルド
   ├─ .app を .zip へアーカイブ & SHA-256 チェックサム生成 & update-info.json 生成
   ├─ main 上に Git タグ（v0.1.0）を自動作成・push
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

アプリケーションのバージョンは `TreeImageOptimizer/TreeImageOptimizer/Info.plist` の `CFBundleShortVersionString` と `CFBundleVersion` を唯一の管理元とする。

- `CFBundleShortVersionString`（例: `0.1.0`）: ユーザーへ表示するセマンティックバージョン（Major.Minor.Patch）。
- `CFBundleVersion`（例: `1`）: macOS Bundleのビルド番号。
- `project.pbxproj` の `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`（および `INFOPLIST_KEY_*`）は `GENERATE_INFOPLIST_FILE=NO` のためビルド結果に反映されない。整合のため同じ値を保つこと。

About画面のバージョン表示は `Bundle.main` から取得する（`AppInfo.bundleVersion`、`UpdateCheckController.currentVersion()`）。ソースコード内にアプリバージョンを重複定義しない。

### バージョンの決め方（セマンティックバージョニング）

- `Major`: 互換性を保証できない大きな変更。
- `Minor`: 後方互換性を維持した機能追加。
- `Patch`: バグ修正や小さな改善。

Stable版（正式版）になるまでは `0.x.y` を使用する。

| バージョン例 | 意味 |
| :--- | :--- |
| `0.1.0 (1)` | 初期開発版 |
| `0.1.1 (2)` | 開発版のバグ修正・小さな改善 |
| `0.2.0 (3)` | 開発版の機能追加 |
| `1.0.0 (4)` | 正式版の初回リリース |

> **重要: ビルド番号（`CFBundleVersion`）はリリースごとに必ずインクリメントする。**
>
> 自前アップデート（`UpdateService.isNewerThan`）はセマンティックバージョンを先に比較し、同点の場合にビルド番号を比較する。
> そのため、セマンティックバージョンを上げてもビルド番号が同じだと、同バージョン内での更新が検出されない。
>
> 例:
> - `v0.1.0` → `0.1.0 (1)`（ビルド番号 1）
> - `v0.1.1` → `0.1.1 (2)`（ビルド番号 2）
> - `v0.2.0` → `0.2.0 (3)`（ビルド番号 3）

### タグとの対応

`CFBundleShortVersionString` が `0.1.0`、ビルド番号が `1` の場合、自動生成されるGitタグは `v0.1.0` とする。

```text
CFBundleShortVersionString: 0.1.0
Git tag:                    v0.1.0
Bundle version:             0.1.0
Bundle build:               1
```

---

## リリースの具体的手順

### ステップ1: 開発とバージョン更新（PR作成）

1. `feature/*` または `fix/*` ブランチで機能実装・修正を行う。
2. 今回のリリース内容に合わせて `Info.plist` の `CFBundleShortVersionString` と `CFBundleVersion` を更新する（例: `0.1.0 (1)` → `0.1.1 (2)`。整合のため `project.pbxproj` 側の対応値も合わせる）。
3. PRを作成し、CI（`.github/workflows/ci.yml`）が通過したことを確認して `main` へマージする。

### ステップ2: GitHub Actionsでワンクリックリリース

1. GitHubリポジトリの **「Actions」** タブを開く。
2. 左メニューから **「Release」** ワークフローを選択する。
3. 右上の **[Run workflow]** ボタンをクリックする（`main` ブランチのまま実行）。
    4. ワークフローが自動的に以下を完了する:
   - 最新リリースタグから次バージョン・ビルド番号を算出し、`Info.plist` に書き込む
   - 既存タグとの重複を検証
   - ビルド・テストを実行
   - 配布用 `.zip` と SHA-256 チェックサム、`update-info.json`（`version` / `build` / `url` / `sha256`）を生成
   - `v0.1.1` タグを自動作成してpush
   - GitHub Releases を作成し、成果物を添付・リリースノートを自動生成

---

## 自動化ワークフロー一覧

### 1. CI ワークフロー (`.github/workflows/ci.yml`)

- **トリガー**: `main` へのPR作成・更新、および `main` へのpush（`TreeImageOptimizer/**` などのパスフィルタあり）
- **処理内容**:
  - `.xcode-version` 指定のXcodeを選択（`xcode-select`）
  - macOS Debugビルドの検証（`xcodebuild -project TreeImageOptimizer/TreeImageOptimizer.xcodeproj -scheme TreeImageOptimizer -configuration Debug build`）
  - テストの実行（`xcodebuild ... -configuration Debug test`、Swift Testing）

### 2. Release ワークフロー (`.github/workflows/release.yml`)

- **トリガー**: `workflow_dispatch`（手動実行、`bump`: major/minor/patch の選択あり — 既定は patch）
- **処理内容**:
  - 最新リリースタグから次バージョンを算出し、`Info.plist` に書き込む（`main` への push は行わない）
  - タグ存在チェック（同名タグが既に存在する場合は多重リリース防止のためエラー終了）
  - `.xcode-version` 指定のXcodeを選択
  - Git LFS オブジェクトの取得（`tools/` 実体）
  - ビルドとテストの実行（`xcodebuild test`）
  - macOS Releaseビルド
  - アドホック再署名と検証（`codesign`）
  - 手動インストール用 `.app` の `.zip` アーカイブ化および SHA-256 チェックサム生成
  - 自前アップデート用の `update-info.json`（`version` / `build` / `url` / `sha256`）を生成
  - Gitタグ（`vX.Y.Z`）の自動作成とリモートへのpush
  - `gh release create` による GitHub Release 作成（`.zip`・`SHA256SUMS.txt`・`update-info.json` を添付・リリースノート自動生成）

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

- タグ: `v0.1.1`
- タイトル: `Tree Image Optimizer v0.1.1`
- 配布用アーカイブ: `Tree-Image-Optimizer-v0.1.1-macos.zip`
- チェックサムファイル: `SHA256SUMS.txt`
- アップデート情報: `update-info.json`（`version` / `build` / `url` / `sha256`）
- リリースノート（PR履歴から自動分類・生成）

アプリは `https://github.com/treetips/tree-image-optimizer/releases/latest/download/update-info.json` から `update-info.json` を取得し、`UpdateService` でバージョン比較・ダウンロード・SHA-256検証を行う。

> 現状の `UpdateService` は確認・ダウンロード・検証までの実装であり、適用（差し替え・再起動）は配布方式確定後に行う（`docs/design/migrate.md` §9参照）。

---

## 失敗時の対応

### CI / リリースビルド失敗時

- ビルドやテストが失敗した場合、Releaseワークフローは途中で安全に停止し、GitタグやGitHub Releaseは作成されない。
- 失敗原因を修正するPRを作成し、`main` にマージ後、再度 [Run workflow] を実行する。

### Release作成後の不具合対応

1. 公開済みのRelease成果物を直接上書き・差し替えない。
2. 重大な不具合がある場合は、GitHub上で対象Releaseを一時的にDraftにするか削除する。
3. バグ修正を行い、Patchバージョンとビルド番号（例: `0.1.1 (2)` → `0.1.2 (3)`）を上げたPRを `main` にマージする。
4. 再度 [Run workflow] を実行して新バージョンのReleaseを公開する。

---

## 配布時の注意事項

現在はアドホック署名（`CODE_SIGN_IDENTITY=-`）で配布しています。以下の制限があります：

- **Gatekeeper 警告**: ユーザーが初回起動時に「開く」ボタンをクリックする必要がある
- **手動インストール**: ユーザーは `右クリック > 開く` でアプリを起動する必要がある
- **macOS専用**: SwiftUI移行後はmacOSのみを配布対象とする（Windows/Linuxバイナリは提供しない）

将来的に Apple Developer Program（年額 $99）に加入し、Developer ID Application 証明書で署名・notarize することで、これらの制限を解消できます。
