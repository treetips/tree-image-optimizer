# アプリケーションの更新

## 更新の条件

- アプリケーションのバージョン（ビルド番号 `+N`）と、公開先の `app-archive.json` が示す
  最新リリースのビルド番号を比較し、新バージョンが見つかるかどうか。
- 更新メタデータ（`app-archive.json` / `release.json`）は `desktop_updater` の
  Ed25519 公開鍵（`trustedReleasePublicKeys`）で署名・検証される。

## 仕組み

- [desktop_updater](https://pub.dev/packages/desktop_updater)（旧 `auto_updater` の後継）を使用する。
- 配布物は **GitHub Pages** にホストする:
  - `https://treetips.github.io/tree-image-optimizer/app-archive.json`（更新インデックス・署名付き）
  - `https://treetips.github.io/tree-image-optimizer/releases/<version>/macos/release.json`（リリース記述・署名付き）
  - `https://treetips.github.io/tree-image-optimizer/releases/<version>/macos/<zip>`（アプリ本体）
- アプリは起動時に `app-archive.json` を参照し、状態遷移に応じて組み込みの更新カード／
  ダイアログでダウンロード・再起動インストールを案内する。

## 更新確認の起動経路

- macOS メニューバーの `Tree Image Optimizer` → `アップデートを確認`
  - 手動チェック。結果（更新あり / 最新 / 失敗）は組み込みダイアログで表示。
- アプリケーション起動時
  - バックグラウンドで自動チェック。ダイアログは表示せず、更新が見つかった場合は
    組み込み更新カードに反映される。
- About画面
  - `アップデートを確認` ボタン（手動チェック・ダイアログ表示）。
  - 更新カード（`DesktopUpdateDirectCard`）を表示。

## 配布・設定

### 設定ファイル

- アプリ側: `lib/core/constants/app_constants.dart`
  - `appArchiveUrl` / `expectedPackageId` / `trustedReleasePublicKeys`（keygen で生成した公開鍵）
- リリース設定: リポジトリルートの `desktop_updater.yaml`（`updates.baseUrl` = GitHub Pages URL）

### 公開鍵の管理

- 公開鍵プロファイル `desktop_updater.keys.json` は **コミット対象**（秘密鍵を含まない）。
- 秘密鍵 `release-key.dukey` は **コミット禁止**（`.gitignore` で除外済み）。
  GitHub Actions シークレット `DESKTOP_UPDATER_KEY_BUNDLE` + `DESKTOP_UPDATER_KEY_PASSPHRASE` で管理し、
  ワークフロー内で `release keys import` により runner へ復元する。

### 更新ホスト（GitHub Pages）

- GitHub Releases のアセットはフラットで、ネスト階層（`releases/<ver>/<plat>/...`）を配信できない。
- そのため desktop_updater の配布物は GitHub Pages（gh-pages ブランチ）に置き、
  GitHub Releases は手動インストール用の `.app` zip と SHA-256・リリースノートを提供する。
- Release ワークフロー（`.github/workflows/release.yml`）が `publish` → gh-pages デプロイを自動実行する。

### 初回リリース時の注意

- 初回は Release ワークフローの `initialize_feed` 入力を `true` にして実行する
  （ホスト上に `app-archive.json` が存在しないため）。2回目以降は `false`。