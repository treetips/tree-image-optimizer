# ファイルダウンロード

## アプリのデータフォルダ

[path_provider](https://pub.dev/packages/path_provider) で `~/Library/Application Support/tree-image-optimizer/` にダウンロードしたファイル等を格納しておきます。

| OS      | 保存先                                   |
|---------|---------------------------------------|
| macOS   | ~/Library/Application Support/AppName |
| Windows | %APPDATA%\AppName                     |
| Linux   | ~/.local/share/AppName                |

上記は却下します。

却下理由は、toolsフォルダ配下は `365MByte` しか無いことが分かったので、プロジェクトに同梱したいです。
