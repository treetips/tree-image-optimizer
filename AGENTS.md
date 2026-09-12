# AGENTS.md

## 共通

- 思考は `英語` で、結果は `日本語` で出力してください。
- 日本語は `natural-japanese` のskillsを活用してください。

## ドキュメント参照ポリシー
- 技術的決定・変更を行う際は `docs/adr/INDEX.md` を確認し、新たな決定は新しいADRファイルを作成して記録してください。

## プロジェクト概要
- SwiftUIによるmacOSデスクトップアプリケーション。
- フォルダ内の画像を一括で最適化する。最適化とは、超解像技術でアップスケールし、エンコードして圧縮すること。
- フォルダを選択 -> アップスケール種別を選択 -> エンコード種別(av1, jpeg-xl)を選択して一括並列変換。

## ビルド・テスト・検証方法
- ソースの変更後はlintを実行してコーディング規約を守っていない部分を修正する。
- lint後にフォーマッターでフォーマットする。
- フォーマット後はビルドしてコンパイルエラーが無いことを確認する。
- コードの変更後は必ず上記を実行して確認する。

## メンテナンス
- Xcodeのバージョンは `.xcode-version` で管理する。CIはこのファイルを参照してXcodeを選択する。
- 依存はSwift Package Manager（Xcodeの `packageProductDependencies`）で管理する。
- Swiftバージョンは `project.pbxproj` の `SWIFT_VERSION`、デプロイメントターゲットは `MACOSX_DEPLOYMENT_TARGET`（現行: macOS 26.0）で維持する。
- Swift/Xcodeはホストコンピューターにインストール済みであることを前提とする。

## コーディング規約
- コミットメッセージは [Conventional Commits](https://www.conventionalcommits.org/ja/v1.0.0/) に準拠し、日本語で記述。
- mainブランチへの直接pushは禁止。必ずfeatureブランチからPRを作成。

## 禁止事項
- .envファイルの内容をコミット・表示しないこと。
- 既存のテストを削除しないこと。
- こちらからの指示が無い場合はgitの操作は行わないこと。
