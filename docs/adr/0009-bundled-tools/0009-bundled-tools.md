# tools・logsのプロジェクト内蔵

## ステータス

- 承認済み (Accepted)

## 背景・課題

当初 ADR 0004 / 0008 では、ツール類とログを
`~/Library/Application Support/tree-image-optimizer/` に配置していた。
しかし tools フォルダは約365MBと判明し、配布・管理を容易にするため
プロジェクト内に同梱したい。

## 決定

- `tools` と `logs` は **プロジェクト直下**に配置する。
  - `<project>/tools`
  - `<project>/logs`
- `PathService` は基準ディレクトリを **プロジェクト直下(作業ディレクトリ)** とする。
  - `flutter run` で起動した場合、作業ディレクトリはプロジェクト直下になる。
- ADR 0004（Application Supportへダウンロード）は棄却(Rejected)とする。

## 代替案

- Application Supportに置き続ける
  - 却下: 約365MBをアプリ外に置くと配布・バージョン管理が煩雑になるため。

## 結果

- `tools` と `logs` がプロジェクト内に存在し、リポジトリとして管理できる。
- 実装箇所: `lib/data/services/path_service.dart`