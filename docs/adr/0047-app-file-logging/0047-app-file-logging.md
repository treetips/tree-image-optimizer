# アプリ全体のファイルログ

## ステータス

- 承認済み (Accepted)

## 背景・課題

ADR 0007 は変換実行時のログを `~/Library/Application Support/tree-image-optimizer/logs/app.yyyyMMdd.log` に残すと決めているが、実装は OSLog のみでファイルを出力していなかった。

そのため、ツール展開に失敗して起動できない場合に `log show` を使わないと原因を追えず、ユーザー環境では調査できなかった。
特に `~/Library/Application Support/tree-image-optimizer` を削除した直後の初回起動は、ツールの再配置とダウンロードが走るため、失敗箇所を特定できるログが必要になる。

## 決定

- `AppLogger` を追加し、`logs/app.yyyyMMdd.log` へ追記する。
- ツール展開、ダウンロード、外部コマンドの実行、変換の失敗を対象にログを残す。
  - ツール展開では探索したパス、欠損フォルダ、コピー元・コピー先、ダウンロードURLと保存先を記録する。
  - 外部コマンドは実行ファイル、引数、作業ディレクトリ、終了コード、標準出力・標準エラーを記録する。
- ログは30日を超えたファイルを起動時と日付が変わった最初の書き込みで削除する。
- OSLog にも同じ内容を流し、Console.app からも追えるようにする。

## 代替案

- OSLog のみを継続する
  - 却下: `log show` の手順を知らないと調査できず、ユーザーからログを回収できないため。

## 結果

- 起動時のツール展開失敗と変換時のコマンド失敗を、ログファイルだけで追跡できる。
- 実装箇所: `TreeImageOptimizer/Services/AppLogger.swift`、`ProcessRunner.swift`、`ToolInstaller.swift`、`ToolBootstrapModel.swift`
