# システム

## アプリケーション形態

- デスクトップアプリ。
- macOSのみ対応。

## アーキテクチャ

- Apple推奨のObservationベースの構成を採用します。依存関係は `View` -> `Model` -> `Service` の一方向です（パスはいずれも `TreeImageOptimizer/TreeImageOptimizer/` 配下）。
  - View（`App/`、`Features/<機能>/*View.swift`）: SwiftUIの宣言的UI。表示に必要な最小限のローカル状態（`@State`）のみを持ち、業務状態は持たずModelの公開状態を表示と操作に結びつけるだけにします。
  - Model（`Features/<機能>/*ViewModel.swift`、`Core/UpdateCheckController.swift`）: `@Observable` + `@MainActor` のクラス。画面ごとの状態と操作を持ち、Serviceを呼び出します。
  - Service（`Services/`）: 永続化・外部プロセス・Appleフレームワークの薄いラッパー。`Sendable` なstruct/class（状態を持たないenumを含む）で実装し、UIの判断ロジックを持ちません。
  - Core（`Core/`）: 機能横断の共有物。データ定義（`Models.swift`）、エラー型（`AppError.swift`）、テーマ・共通View、言語解決（`L10n.swift`）を置きます。

| 層       | 配置                                                                                                 | 例                               |
|:--------|:---------------------------------------------------------------------------------------------------|:--------------------------------|
| View    | `App/RootView.swift`、`Features/Convert/ConvertView.swift`                                          | `NavigationSplitView`、各画面のレイアウト |
| Model   | `Features/Convert/ConvertViewModel.swift`、`Features/Settings/SettingsViewModel.swift`              | 画面状態・検証・保存・実行指示                 |
| Service | `Services/ConvertOrchestrator.swift`、`Services/SettingsStore.swift`、`Services/ProcessRunner.swift` | 並列変換・設定の読み書き・プロセス実行             |
| Core    | `Core/Models.swift`、`Core/AppError.swift`、`Core/L10n.swift`                                        | データ型・エラー・文言解決                   |

- `UseCase` / `Repository` 層は設けません。必要なオーケストレーションは `ConvertOrchestrator` のようなServiceに集約し、層を薄く保ちます。

## 状態管理

- [Observationフレームワーク](https://developer.apple.com/documentation/observation)（`@Observable`、`@State`、`@Environment`）で管理します。Single Source of Truthを保ち、状態は使う場所に最も近い層で所有します。
- 共有状態（設定・アップデート確認）は `TreeImageOptimizerApp` で生成し、下位Viewへ渡します。画面固有の状態は各Viewの `@State` で持ちます。
- Swift 6言語モードを採用します。UI状態は `@MainActor` で隔離し、Serviceは `Sendable` にして、非同期処理は `async/await` と `Task` による構造化並行処理で記述します。

## Linter・Formatter

- Linterは [SwiftLint](https://github.com/realm/SwiftLint) を使う。設定はリポジトリ直下の `.swiftlint.yml` で管理する。
- Formatterは [swift-format](https://github.com/swiftlang/swift-format) を使う。設定はリポジトリ直下の `.swift-format`（JSON）で管理する。
- 導入方法:
  - swift-formatはXcode 16以降のツールチェーンに同梱されており、追加インストールなしで `swift format` として実行できる（`xcrun --find swift-format` で配置を確認できる）。
  - SwiftLintはHomebrewで導入する（`brew install swiftlint`）。ホストへのインストールを前提とする。
- 実行手順（AGENTS.md「ビルド・テスト・検証方法」の順序に従う）:
  1. `swiftlint` で規約違反を検出・修正する（自動修正は `swiftlint --fix`）。
  2. `swift format format -i -r TreeImageOptimizer` でフォーマットする（確認のみは `swift format lint -r TreeImageOptimizer`）。
  3. フォーマット後は `xcodebuild` でビルドし、コンパイルエラーが無いことを確認する。

## アップデート

- 起動時にバックグラウンドで確認し（`UpdateCheckController.refreshAvailability()`、ダイアログなし・サイドナビ通知のみ反映）、About画面・メニューバー・サイドナビ通知から手動確認もできる（`checkForUpdate()`）。
- `UpdateService` がGitHub Releasesの `update-info.json` を取得し、セマンティックバージョン→ビルド番号の順で比較する。GitHub側が新しい場合のみアップデートダイアログを表示する。
- ダウンロード・SHA-256検証・展開までは `UpdateService` が行う。適用（差し替え・再起動）は配布方式確定後に実装する。

## サウンドの再生

- [AVFoundation](https://developer.apple.com/av-foundation/)（`AVAudioPlayer`）を `SoundService` 経由で使います。音声ファイルはXcodeのリソースとして同梱します。
- 再生対象のフォルダは以下の通りです。
  - アプリバンドル内の `assets/sounds/success` 。最初から同梱されている `成功音声` のフォルダです。このフォルダには必ず音声ファイルが配置されています。
  - アプリバンドル内の `assets/sounds/error` 。最初から同梱されている `失敗音声` のフォルダです。このフォルダには必ず音声ファイルが配置されています。
  - `~/.config/tree-image-optimizer/sounds/success` 。ユーザーが自分で用意した `成功音声` のフォルダです。このフォルダはユーザーが任意に配置するので、フォルダ・ファイルが存在しない場合があります。
  - `~/.config/tree-image-optimizer/sounds/error` 。ユーザーが自分で用意した `失敗音声` のフォルダです。このフォルダはユーザーが任意に配置するので、フォルダ・ファイルが存在しない場合があります。

## 通知

- [UserNotifications](https://developer.apple.com/documentation/usernotifications/)（`UNUserNotificationCenter`）を `NotificationService` 経由で使います。起動時に許可を求め、アプリ前面表示中もバナーを出します。

## 国際化

- String Catalogs（`Resources/Localizable.xcstrings`、ja/en）を使います。SwiftUIの `.environment(\.locale)` が届かない箇所（メニュー・通知・ダイアログ文言）は `L10n.string(_:language:)` で設定言語に従わせます。

## アプリケーション

- アプリケーションアイコンは `Resources/TreeImageOptimizer.icns` を使用します。
- About画面の表示アイコンは `assets/images/icon-tree-01.png` を使用します。