# 外部ツールのダウンロードにチェックサム検証と再試行を導入する

## ステータス

- 承認済み (Accepted)

## 背景・課題

`ToolInstaller` は `downloadRealcugan()` と `downloadLibwebp()` でGitHub Releases・Google Storageから
アーカイブを取得し、`tools/` 配下に展開したバイナリへ `0o755` の実行権を付与していた。

しかし取得したデータのSHA-256検証が一切無く、`sha256Hex(of:)` は実装済みながらダウンロード経路から
呼ばれていなかった。アプリ更新経路（`UpdateService.downloadAndPrepare`）は ADR 0051 系の実装で
SHA-256検証を行っているため、外部バイナリを実行権付きで配置する経路としては不揃いだった。
通信経路・ミラー・キャッシュのいずれかが改ざんされれば、検知できないまま実行される。

また再試行が無く、`request.timeoutInterval = 300` のみに依存していたため、
一時的なタイムアウトや接続断がそのまま修復失敗になり、ユーザーは再実行UIからやり直す必要があった。

さらに `libwebpArchiveName(version:platform:arch:)` は `windows` / `linux` の分岐を持っていたが、
AGENTS.md・READMEでmacOS専用と明言しており、到達しない分岐が残滓として残っていた。

## 決定

- 取得したアーカイブ（`Data`）のSHA-256を計算し、期待値と一致するか検証する。
  - 検証は **配置・実行権付与の前** に行う。不一致なら `AppError.verificationFailed` で落とす。
  - 期待ハッシュはToolInstallerのstatic定数で持つ（`realcuganArchiveSHA256`、
    `libwebpArchiveSHA256`）。
  - libwebpはアーキテクチャごとに別アーカイブなので、期待ハッシュもアーカイブ名をキーにした辞書で持つ。
- 期待ハッシュは実測値を入れる。`curl -sL <URL> | shasum -a 256` で2回取得して
  同一値になることを確認したものを採用する（実測環境: realcugan `20220728`、
  libwebp `1.6.0` のmac-arm64 / mac-x86-64）。
  - **期待値が空文字または `nil` の場合は検証をスキップし、警告ログを出して継続する。**
    将来バージョンを上げてハッシュ未更新の状態でも、ダウンロード自体は成立させて
    復旧可能にするため。ダミー値を入れると不一致で取得が成立せずデバッグも困難になるため避ける。
- 一時的なネットワークエラーに対して指数バックオフ付きの再試行を行う。
  - 最大3回、初回1秒→2秒→4秒。
  - 再試行対象はタイムアウト・接続断等の一時的エラー（`NSURLErrorDomain` と
    `NSPOSIXErrorDomain` の該当コード）のみ。404等のHTTPステータス異常は即座にエラーにする。
  - リトライ状況は `AppLogger.shared` に `warning` で出力する。
  - 再試行時は `.reloadIgnoringLocalCacheData` でキャッシュを使い回さない（ADR 0051と同一方針）。
- `libwebpArchiveName` から `platform` 引数と `windows` / `linux` 分岐を削除し、
  macOS専用（`mac-arm64` / `mac-x86-64`）に単純化する。呼び出し側と既存テストも合わせて修正する。

## 代替案

- 期待ハッシュなしでダウンロードを続行する（現状維持）
  - 却下: 実行権を付与する外部バイナリであり、改ざんを検知できないのは更新経路との不揃いも大きい。
- 期待ハッシュ未設定時にエラーにしてダウンロードを止める
  - 却下: 上流がハッシュを公開していない場合や将来のバージョン更新時に、
    ツール修復が一切できなくなり復旧手段が失われる。警告付きスキップが安全側。
- すべてのエラーを再試行する
  - 却下: ADR 0051 で自動再試行の無限ループを避けた判断と同様、恒久的失敗では成功せず
    エラー通知が遅れるだけ。
- チェックサム不一致時に自動で再ダウンロードする
  - 却下: ミラーが差し替えられている場合は何度でも不一致になり、
    ユーザーの意図しない通信を続ける。再実行は明示操作に任せる。
- プラットフォーム分岐を残したままmacOS固定値を渡す
  - 却下: 到達しないコードが保守時に誤修正される恐れがあり、macOS専用という前提も壊れる。

## 結果

- 改ざんされたアーカイブは実行権付与前に検出され、`AppError.verificationFailed` になる。
- 一時的なネットワーク不良は最大3回の再試行で吸収される。
- `libwebpArchiveName` のシグネチャがmacOS専用になり、到達しない分岐が消えた。
- 実装箇所: `Services/ToolInstaller.swift`（期待ハッシュ定数・`verifyArchive`・
  `isTransientNetworkError`・`download(url:)` の再試行）、
  `TreeImageOptimizerTests/ToolInstallerTests.swift`（検証と再試行判定のテスト追加）。
- 既存テストは削除せず、プラットフォーム依存のアサーションのみmacOS分に更新した。
