# 更新インストール中の進捗をサイドナビに表示する

## ステータス

- 承認済み (Accepted)

## 背景・課題

サイドナビの「アップデートが有ります」からインストールダイアログを開き `インストール` を押すと、
ダイアログが閉じた後、アプリが新しいバージョンで再起動して終了するまで画面に何も変化が無かった。
配布ZIPはツール一式を同梱するため約379MBあり、回線によってはダウンロードに数十秒から数分かかる。
その間、処理が動いているのか・失敗したのか・完了したのかをユーザーが判断できず、
操作が効いたのかどうかも分からない状態だった。

Superlogical Rex や DeepSeek Harness のように、ダウンロード進捗を%でリアルタイム表示したいという要望があった。

## 決定

- インストール開始時に確認ダイアログを閉じ、サイドナビ下部のカードを
  「インストール中」に差し替える（`UpdateCard.installing(UpdateInstallProgress)`）。
- ダウンロードは `URLSessionDownloadTask` の `URLSessionDownloadDelegate` から
  `totalBytesWritten` / `totalBytesExpectedToWrite` を受け取り、1%刻みでカードへ反映する。
  GitHub Releases のアセットは `Content-Length`（2026年11月時点で 379,030,417 bytes）と
  `Accept-Ranges: bytes` を返すため、実際の受信バイト数に基づく確定バーにできる。
- `Content-Length` が無いサーバーでは0%固定にせず、不確定バーと「ダウンロード中」にフォールバックする。
- ダウンロード後は `verifying`（SHA-256検証）・`extracting`（unzip展開）・`installing`
  （`/Applications` へのコピー）の段階を表示する。これらはバイト進捗を取得できるAPIが無いため
  不確定バーにする。
- 既存の `URLSession.data(for:)` による一括読み込みをやめ、`URLSessionDownloadTask` の
  一時ファイルへ直接受信する。379MBをメモリに載せないため。SHA-256もファイルを4MBずつ読みながら
  逐次計算する。
- 適用（コピー）は `Task.detached` で実行し、メインアクターをブロックしない。
  ブロックするとバーの更新・アニメーションが止まり、進捗表示の意味が失われるため。
- 失敗時はカードを「アップデートが有ります」へ戻し、従来どおりエラーダイアログを出す（再試行可能）。
- インストール中は手動確認（About画面・メニューバー）を無効化し、進捗カードを
  別の確認結果で上書きしない。

## 代替案

- `URLSession.bytes(for:)` で受信しながらファイルへ書く
  - 却下: バイト単位のAsyncSequenceで実装が複雑になり、379MBではオーバーヘッドも大きい。
    DownloadTaskのdelegateで必要十分。
- `URLSession.data(for:)` のまま `Progress` をポーリングする
  - 却下: 一括読み込みでメモリを圧迫するうえ、レスポンス取得まで総バイト数が分からず
    初動の表示が不安定になる。
- 検証・展開・コピーも自前でバイト進捗を数える
  - 却下: unzipやdittoの内部進捗は取れず、コピーを自前実装するとシンボリックリンクや
    リソースフォークの再現リスクがある。短時間の段階は不確定表示で十分。
- 進捗をダイアログ内に表示し続ける
  - 却下: 要望は「ダイアログを閉じた後もサイドナビで分かる」こと。ダイアログは操作の確認であり、
    実行状態は常時見えるサイドナビに置く方が良い。

## 結果

- インストール開始後、サイドナビに「インストール中」とダウンロード%・バーが表示され、
  完了すると新バージョン起動後にアプリが終了する。
- 進捗は受信バイト数ベースで、GitHub Releases では実際のダウンロードと一致する。
- 実装箇所: `Services/UpdateService.swift`（DownloadTask・段階通知・逐次SHA-256）、
  `Core/UpdateCheckController.swift`（カード状態）、`App/RootView.swift`（カードUI）、
  `Resources/Localizable.xcstrings`。
- テスト: 受信バイト数→進捗率の変換（クランプ・Content-Length不明時nil）と、
  進捗文言のローカライズ。
