# システム

## アプリケーション形態

- デスクトップアプリ。
- macOSのみ対応。

## アーキテクチャ

- Apple推奨のObservationベースの構成を採用します。依存関係は `View` -> `Model` -> `Service` の一方向です（パスはいずれも `TreeImageOptimizer/TreeImageOptimizer/` 配下）。
  - View（`App/`、`Features/<機能>/*View.swift`）: SwiftUIの宣言的UI。表示に必要な最小限のローカル状態（`@State`）のみを持ち、業務状態は持たずModelの公開状態を表示と操作に結びつけるだけにします。
  - Model（`Features/<機能>/*ViewModel.swift`、`Features/Convert/ConvertJobStore.swift`、`Features/EasyConvert/EasyConvertJobStore.swift`、`Core/UpdateCheckController.swift`）: `@Observable` + `@MainActor` のクラス。画面ごとの状態と操作を持ち、Serviceを呼び出します。
    - 画面固有のフォーム状態（フォルダパス・変換設定・表示フィルタ）は各 `ViewModel` が持ちます。
    - 画面遷移を跨いで存続すべき実行状態（`isRunning`・進捗・結果表）は共有の `ConvertJobStore` / `EasyConvertJobStore` が持ちます。実処理はServiceである `ConvertOrchestrator` に委譲し、各 `ViewModel` はファイル列挙と設定スナップショット作成に専念します。
    - `EasyConvertViewModel` は実行状態の読み取り専用プロキシ（`isRunning`・進捗・結果など）を公開し、既存テストとの互換性を保ちます。
  - Service（`Services/`）: 永続化・外部プロセス・Appleフレームワークの薄いラッパー。`Sendable` なstruct/class（状態を持たないenumを含む）で実装し、UIの判断ロジックを持ちません。
  - Core（`Core/`）: 機能横断の共有物。データ定義（`Models.swift`）、エラー型（`AppError.swift`）、テーマ・共通View、言語解決（`L10n.swift`）を置きます。

| 層       | 配置                                                                                                 | 例                               |
|:--------|:---------------------------------------------------------------------------------------------------|:--------------------------------|
| View    | `App/RootView.swift`、`Features/Convert/ConvertView.swift`                                          | `NavigationSplitView`、各画面のレイアウト |
| Model   | `Features/Convert/ConvertViewModel.swift`、`Features/Convert/ConvertJobStore.swift`、`Features/EasyConvert/EasyConvertJobStore.swift`、`Features/Settings/SettingsViewModel.swift` | 画面状態・検証・保存・実行指示・共有ジョブ状態        |
| Service | `Services/ConvertOrchestrator.swift`、`Services/SettingsStore.swift`、`Services/ProcessRunner.swift` | 並列変換・設定の読み書き・プロセス実行             |
| Core    | `Core/Models.swift`、`Core/AppError.swift`、`Core/L10n.swift`                                        | データ型・エラー・文言解決                   |

- `UseCase` / `Repository` 層は設けません。必要なオーケストレーションは `ConvertOrchestrator` のようなServiceに集約し、層を薄く保ちます。

## 状態管理

- [Observationフレームワーク](https://developer.apple.com/documentation/observation)（`@Observable`、`@State`、`@Environment`）で管理します。Single Source of Truthを保ち、状態は使う場所に最も近い層で所有します。
- 共有状態（設定・アップデート確認・一括変換ジョブ・かんたん変換ジョブ）は `TreeImageOptimizerApp` で生成し、下位Viewへ渡します。画面固有の状態は各Viewの `@State` で持ちます。
- 一括変換・かんたん変換の実行状態は各 `View` の `@State` で新規生成しません。`RootView` が共有の `ConvertJobStore` / `EasyConvertJobStore` を保持し、各画面とサイドナビに同一インスタンスを渡します。`NavigationSplitView` のdetail切替で画面が再生成されても `isRunning`・進捗・結果が維持され、ガードレールなしで画面遷移しても孤児タスクになりません。
- サイドナビは各ジョブの `isRunning` を購読し、実行中はメニューのアイコンをテーマカラーのローディング表示（`ProgressView` のスピナーはmacOSで着色できないためSF Symbolsの回転で自前表示）に切り替え、ラベルの下端の最背面に細いリニアバーを重ねて表示します（`.background` のためレイアウトに参加せず、行の高さは変わらないので下の項目はズレません）。一括変換は進捗連動の確定バー＋右端のテーマカラー進捗%、かんたん変換は不確定アニメーションバーのみ（1ファイルのため%なし、いずれも標準SwiftUIのみで実装）です。行は縦パディングで行高を確保し、内容は中央揃えになります。画面に戻った際は実行中のまま表示します。一括変換の実行ボタンは `jobStore.isRunning` に連動して `変換中...` のまま非活性にします。処理が終了すれば元のアイコンに戻し、進捗%を非表示にします。
- かんたん変換の入力エリア（ドロップ・クリック選択）はジョブ実行中は無効化し、終了で自動的に有効に戻します。SwiftUIの `.disabled` だけでは `NSView` のドラッグ受け付けまで止まらないため、`FileDropNSView` に `isEnabled` を持たせてAppKitレベルでも受け付けを拒否します。
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