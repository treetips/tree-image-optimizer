# TreeImageOptimizer (SwiftUI)

フェーズ2のUI試作ターゲット。見た目と画面遷移のみで、機能の配線は行わない。

## 前提

- Xcode 26.6 / Swift 6.3.3 / macOS Tahoe 26 SDK（`docs/design/migrate.md` 参照）
- サンドボックスは無効（フェーズ3で外部ツール実行を見据えた暫定判断）
- デプロイメントターゲットは macOS Tahoe 26.0

## 開き方・ビルド

```sh
open TreeImageOptimizer/TreeImageOptimizer.xcodeproj
xcodebuild -project TreeImageOptimizer/TreeImageOptimizer.xcodeproj \
  -scheme TreeImageOptimizer -configuration Debug build
```

署名はアドホック（`CODE_SIGN_IDENTITY=-`）のため、チーム設定なしでローカルビルドできる。

## 範囲

- `NavigationSplitView` による変換/設定/Aboutの画面遷移
- 各画面の主要コントロール配置（ダミーデータ、操作は状態確認用のみ）
- `String Catalogs`（ja/en）の枠組み
- 変換・保存・ツール実行・通知・音声・更新チェックは未配線（フェーズ3）
