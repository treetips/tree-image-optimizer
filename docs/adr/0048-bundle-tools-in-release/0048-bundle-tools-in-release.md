# 配布ビルドにツール一式を同梱する

## ステータス

- 承認済み (Accepted)

## 背景・課題

配布した `TreeImageOptimizer.app` を初回起動すると、次のエラーでツール準備に失敗していた。

```text
ツールの準備に失敗しました
必要なツールが見つかりません: tools unavailable locally: upscal
```

`~/Library/Application Support/tree-image-optimizer/tools` は空のまま作成され、
ログも残らないため原因を追えなかった。

調査の結果、次の3点が原因だった。

1. Release ビルドの `.app` に `tools/` が含まれていなかった。
2. `Info.plist` の `DevToolsPath` はビルドマシンの
   `/Users/runner/work/.../tools` に展開されたまま配布され、ユーザー環境には存在しない。
3. `upscal` / `jpegoptim` / `pngoptim` / `libjxl` / `libavif` はダウンロード処理を持たず、
   ローカルコピーにしか対応していなかった。

そのため、Application Support を削除した直後の初回起動では復元元が無く、
必ず `upscal` のコピーで失敗していた。

## 決定

- Xcode のビルドフェーズに `Copy Tools` を追加し、**Release ビルドだけ**
  `tools/` を `.app/Contents/Resources/tools` へ同梱する。
  - Debug ビルドは `DevToolsPath` がリポジトリ直下を指すため、約434MBの複製を避ける。
- `ToolInstaller.defaultDevToolsCandidates()` は同梱物を最優先にし、
  `DevToolsPath` はパスが実在する場合だけ候補に加える。
  - 配布ビルドに残るビルドマシンのパスを無視するため。
- 起動時のログに探索した候補パスを出し、失敗時はオーバーレイに
  ログ出力先と「ログフォルダを開く」ボタンを表示する。

## 代替案

- `tools-vVERSION.zip` を GitHub Releases で別配布し、初回起動時にダウンロードする
  - 却下: SHA-256 検証・展開・失敗時の再試行など配布基盤の追加実装が必要で、
    現時点ではアプリ同梱で要件を満たせるため。
- Debug ビルドにも常に同梱する
  - 却下: 開発中のビルド時間とディスク消費が増える割に、開発時は
    リポジトリ直下の `tools/` を参照できるため利点が無い。

## 結果

- Application Support を削除しても、初回起動時にアプリ内の `tools/` から復元できる。
- 配布物の `.app` は約434MB増えるが、外部ダウンロード無しで起動できる。
- 失敗時は `logs/app.yyyyMMdd.log` と画面の案内から原因を追える。
- 実装箇所: `project.pbxproj` の `Copy Tools`、`ToolInstaller.swift`、`ToolBootstrapModel.swift`、
  `RootView.swift`
