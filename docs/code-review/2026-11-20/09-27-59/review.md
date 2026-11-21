# コードレビュー結果

- 実行日時: 2026-11-20 09:27
- 実行: `ocr review --from main --to feat/separate-tools-distribution --effort high`
- 対象: 5 ファイル（`.github/workflows/release.yml`、`App/RootView.swift`、
  `Core/ToolsInfo.swift`、`Core/ToolsUpdateController.swift`、
  `Services/ToolsUpdateService.swift`）
- 指摘数: 24 件

## 指摘の採否

### 対応した指摘

| #   | ファイル              | 重要度   | 内容                                                                       | 対応                                          |
| --- | --------------------- | -------- | -------------------------------------------------------------------------- | --------------------------------------------- |
| 1   | release.yml           | critical | ループ内で `ZIP_NAME` を上書きし、`zip_path` 出力が最後のツール ZIP を指す | ツール ZIP 名を `TOOL_ZIP_NAME` に分離        |
| 2   | ToolsUpdateController | high     | 進捗初期値が `nil`（不確定）で、以後の確定進捗が破棄される                 | 初期値を `fraction: 0` に変更                 |
| 3   | ToolsInfo             | high     | `.installed.json` が無い既存環境で全ツールが更新対象になる                 | `loadInstalled()` で同梱バージョンから初期化  |
| 4   | ToolsUpdateService    | medium   | 途中失敗時に成功済みツールの記録が保存されない                             | ツール単位で `saveInstalled`                  |
| 5   | ToolsUpdateService    | medium   | 削除→コピーで失敗時に必須ツールが欠落                                      | ステージング→置換に変更                       |
| 6   | ToolsUpdateService    | security | リモート由来の `tool.name` を配置先に無検証で使用                          | `toolBinaryChecks` の許可リスト照合           |
| 7   | ToolsUpdateService    | medium   | 配置後バイナリ存在を検証しない                                             | `toolBinaryChecks` で存在確認                 |
| 8   | ToolsInfo             | medium   | schemaVersion 未検証                                                       | `supportedSchemaVersion` で検証し不一致は中止 |
| 9   | ToolsInfo             | low      | 配布元 URL の二重管理                                                      | `AppInfo.githubURL` から導出                  |
| 10  | ToolsInfo             | medium   | 読み込み失敗をログなしで握りつぶし                                         | `AppLogger` に記録し同梱版へフォールバック    |
| 11  | RootView              | medium   | ダイアログに全ツール名を表示（差分と食い違う）                             | `pendingToolNames` で差分だけ表示             |
| 12  | RootView              | medium   | ツール更新中に変換を開始できる                                             | `toolsReady` に更新中を反映して抑止           |
| 13  | release.yml           | medium   | `.version` の値をそのまま使用（CR/改行混入）                               | `tr`/`head` で 1 行・空白除去                 |
| 14  | release.yml           | medium   | `grep` 失敗時に `set -euo pipefail` で即死                                 | `|| true` で握りつぶし                        |
| 15  | release.yml           | low      | `COPYFILE_DISABLE` は ditto に効かない                                     | `--norsrc --noextattr` を明示                 |
| 16  | release.yml           | medium   | LFS ポインタ混入の検証なし                                                 | ツールディレクトリ非空を確認                  |
| 17  | release.yml           | low      | `JSON_DIR` が未使用の空ディレクトリ                                        | 削除                                          |
| 18  | release.yml           | low      | ツール SHA-256 が SHA256SUMS.txt に無い                                    | 追記                                          |

### 却下した指摘（理由付き）

| #   | ファイル           | 重要度      | 内容                                                                     | 却下理由                                                                                                                                                                     |
| --- | ------------------ | ----------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 19  | release.yml        | medium      | ツール一覧の二重管理（`ToolInstaller.toolBinaryChecks` と `TOOLS` 配列） | release.yml から Swift 定数を解析するのは複雑で壊れやすい。ツールは 7 つ固定で変更頻度が低く、追加時の手順は `update-image-tools` スキルが定めている。静的チェック追加は過剰 |
| 20  | release.yml        | medium      | 全ツール毎回アップロード（ADR の「更新のあったツールのみ」と矛盾）       | v1 は全ツール配布のシンプルな方式を採る。前リリースの `tools-info.json` との差分判定は配布基盤が安定してから導入。ADR 0064 側に「v1 は全ツール配布」を明記して整合させた     |
| 21  | ToolsUpdateService | low         | 進捗が件数ベースでバイトベースでない                                     | `ToolInstaller.download` は `Data` 全体を返すためバイト進捗を取得できない。ストリーミング対応は別途改善                                                                      |
| 22  | ToolsUpdateService | test        | 更新処理のテストが無い                                                   | Runner/ダウンロードを差し替え可能にするリファクタリングが必要。`ToolsInfoTests` でストアの差分判定は検証済み。別途対応                                                       |
| 23  | ToolsUpdateService | performance | メモリ大量使用（`Data` 全体保持）                                        | 既存 `ToolInstaller.download` の再利用方針による。ストリーミング化は別途改善                                                                                                 |
| 24  | ToolsInfo          | medium      | `required` フラグ未使用                                                  | v1 は全ツール必須（`required=true`）のため実質不要。将来任意ツール導入時に使用                                                                                               |

## 補足

- ビルド検証は環境制約（ホストの Xcode 27.2 と `.xcode-version` 26.6 の不一致による
  `@Observable` マクロプラグインの失敗）により本機では実行できていない。CI で検証される。
