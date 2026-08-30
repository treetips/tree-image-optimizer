# サンドボックス無効化とApplication Supportパスの決定

> 注記: 本ADRの「基準パスの決定」部分は [ADR 0009](./../0009-bundled-tools/0009-bundled-tools.md) により、
> `~/Library/Application Support/tree-image-optimizer` からプロジェクト直下に変更された。
> サンドボックス無効化の決定は有効のまま。

## ステータス

- 承認済み (Accepted)

## 背景・課題

変換処理が全件失敗していた。ログ調査の結果、2つの原因が判明した。

1. **サンドボックスによるパス隔離**
   アプリが `com.apple.security.app-sandbox` 有効でビルドされていたため、
   `getApplicationSupportDirectory()` がコンテナ
   `~/Library/Containers/<bundle-id>/Data/Library/Application Support` を返していた。
   一方、ツール類（initial-data.md で配置）とログ（ADR 0007）は
   非コンテナの `~/Library/Application Support/tree-image-optimizer/` に置かれており、
   アプリから参照できず、アップスケール／圧縮コマンドの実行ファイルが見つからず全件失敗していた。

2. **アプリ名サブディレクトリが付与されていなかった**
   `path_provider` の `getApplicationSupportDirectory()` は
   macOS では AppKit の規約によりバンドルIDのサブディレクトリ
   `~/Library/Application Support/com.treeimageoptimizer.treeImageOptimizer`
   を返すため、docs が示す `~/Library/Application Support/tree-image-optimizer`
   と一致しなかった。ログが `.../com.treeimageoptimizer.treeImageOptimizer/tree-image-optimizer/logs`
   に出力されていた。

## 決定

- **サンドボックスを無効化**する（`com.apple.security.app-sandbox = false`）。
  - 本アプリはユーザーが任意に選択した入力／出力フォルダを読み書きし、
    さらに非コンテナの `~/Library/Application Support/tree-image-optimizer` 配下の
    ツール・ログを参照するため、サンドボックスを維持できないため。
  - ファイル選択（`files.user-selected.read-write`）とネットワーク（`network.client`）は
    エンタイトルメントとして残す。
- **PathService は環境変数ベースで基準パスを決定**し、docs の絶対パスと完全に一致させる。
  - macOS: `$HOME/Library/Application Support/tree-image-optimizer`
  - Windows: `%APPDATA%\tree-image-optimizer`
  - Linux: `$HOME/.local/share/tree-image-optimizer`
  - 環境変数が取得できない場合のみ `path_provider` をフォールバックに用いる。

## 代替案

- ツールをサンドボックスコンテナ内にコピーしてサンドボックスを維持する
  - 却下: docs（initial-data.md / ADR 0007）が非コンテナの
    `~/Library/Application Support/tree-image-optimizer` を固定しているため、経路が二重化する。
- セキュリティスコープ付きブックマークでコンテナ外へアクセスする
  - 却下: ツールはユーザー操作なしで自動参照する必要があり、ブックマークの獲得フローが複雑になるため。

## 結果

- `~/Library/Application Support/tree-image-optimizer` がdocsどおりの基準パスになる。
- 実装箇所: `lib/data/services/path_service.dart`、
  `macos/Runner/DebugProfile.entitlements`、`macos/Runner/Release.entitlements`