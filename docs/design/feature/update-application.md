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
  - 手動チェック。結果（更新あり / 最新 / 失敗）は組み込みダイアログで表示し、
    失敗時を除きサイドナビ下部の更新カードにも反映する。
- アプリケーション起動時
  - バックグラウンドで自動チェック。ダイアログは表示せず、更新が見つかった場合は
    組み込み更新カードに反映される。
- About画面
  - `アップデートを確認` ボタン（手動チェック）。メニューバーと同じ挙動で、
    結果はダイアログとサイドナビ下部の更新カードの双方に表示する（確認失敗時は
    更新カードを変更しない。ネットワーク失敗で「更新なし」と表示するのは誤解を招くため）。

## インストールの流れ

1. サイドナビ下部の `アップデートが有ります` をクリックする。
2. インストール確認ダイアログが表示される。
3. `インストール` をクリックするとダイアログが閉じ、更新カードが `インストール中` に変わる。
4. ダウンロード中は受信バイト数に基づく進捗率（%）と確定バーを表示する。
5. ダウンロード後は検証・展開・配置の段階を不確定バーで表示する。
6. 完了すると新しいバージョンを起動し、旧プロセスを終了する。
7. 失敗した場合は赤い `インストールに失敗` カードに切り替わり、`再実行` でダウンロードからやり直せる。
8. 開発ビルドなど実行中のアプリがインストール先と一致しない場合は終了せず、Finderで表示する。

## 更新カード仕様

### 更新が有る場合

- 左サイドナビの下部に `アップデートが有ります` と表示。
- クリックすると、アップデートのインストールダイアログを表示。
- 更新カードの背景色は、OSのテーマカラーで表示。
- 更新カードのテキスト色は、ライトモード・ダークモードのどちらでも強調した見やすい色にします。
- LiquidGlassで表示。

### インストール中の場合

- 左サイドナビの下部に `インストール中` と進捗の補足を表示。
- ダウンロード中は `ダウンロード 42%` と確定バーを表示する。総バイト数が不明な場合は
  `ダウンロード中` と不確定バーにする。
- 検証・展開・コピー中は `ダウンロードを検証中`・`展開中`・`アプリを配置中` と不確定バーを表示する。
- カードはクリックできない。背景色・テキスト色は更新ありカードと同じ。
- 失敗時は背景を赤色にした `インストールに失敗` カードへ切り替える。
  - カード内に `再実行` ボタンを表示し、クリックするとダウンロードからやり直す。
  - 失敗の詳細理由はエラーダイアログとAbout画面のメッセージに表示する。
- インストール中は手動の更新確認を無効化する。

### 更新が無い場合

- 左サイドナビの下部に `アップデートは有りません` と表示。
- クリックすると、何もせず更新カードを非表示化。
- 更新カードは10秒後に自動的に非表示化。
- 更新カードの背景色は、透明で目立たない色で表示。
- 更新カードのテキスト色は、左サイドナビのメニュー項目と同様のテキスト色にします。
- LiquidGlassで表示。

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
