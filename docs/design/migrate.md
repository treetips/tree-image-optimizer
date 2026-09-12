# SwiftUI 移行計画（フェーズ1）

本書は `docs/adr/0019-migrate-from-flutter-to-swiftui/0019-migrate-from-flutter-to-swiftui.md`
のフェーズ1成果物である。実装は行わず、移行の方針・範囲・順序を定義する。
フェーズ2（UIのみ）・フェーズ3（機能＋先にテスト）の前提条件とする。

- 機能は完全に踏襲する
- UIは仕様書の見た目をそのまま写すのではなく、Finderのサイドナビや
  Liquid Glassのような **AppleらしいUI** に置き換える
- バージョンは **2026/09時点の最新** を使う

## 1. バージョン方針（2026/09時点）

| 項目 | 採用 | 備考 |
|---|---|---|
| Xcode | 26.6（17F113, Stable） | 手元の実行環境と一致。Xcode 27は2026/09時点でBeta 6のため原則使わない |
| Swift | 6.3.3（Xcode 26.6付属） | 手元 `swift --version` で確認。Xcode 27系のSwift 6.4はBeta扱いのため見送り |
| SwiftUI / SDK | macOS Tahoe 26 SDK | `macos versions` の意味ではなく、Xcode 26.6付属の最新安定SDK |
| 実行/検証OS | macOS Tahoe 26.6.2（25G83） | 手元の `sw_vers` で確認。後方互換の下限はフェーズ2開始前に確定する |
| 言語モード | Swift 6言語モード | 並行処理の安全性をコンパイル時に担保する。`Sendable`/`@MainActor`を徹底する |

判断理由：

- ADRが「2026/09時点での最新」と言う場合、BetaではなくStable最新を指すと解釈する
- Xcode 27 / Swift 6.4 / macOS 27 SDKは2026/09時点でBetaのため、フェーズ2のUI試作には使わない
- 安定版で土台を作り、Xcode 27が正式版になった時点で追従する

## 2. 現行Flutterアプリの棚卸し

### 2.1 技術スタック

- Flutter 3.47.1（`.fvm/fvm_config.json`）、Dart `^3.12.0`
- 状態管理：`flutter_riverpod`
- アーキテクチャ：`UI -> Logic -> Data` の一方向、MVVM
  - `lib/ui/screens`：`convert_screen` / `settings_screen` / `about_screen` / `tool_bootstrap`
  - `lib/ui/widgets`：`section` / `glass_card` / `glass_effect` / `status` / `glass_button`
  - `lib/ui/theme`：`app_colors` / `glass_constants`
  - `lib/logic/viewmodels`：`convert`（469行） / `settings`（265行） / `about` / `tool_install` / `update`
  - `lib/logic/usecases`：`compress` / `upscale` / `get_target_files` / `get_upscale_models` / `notify_completion`
  - `lib/logic/update`：`updater_service` / `update_actions` / `update_info`
  - `lib/data/repositories`：`convert_repository` / `settings_repository`（363行）
  - `lib/data/services`：`compression`（367行） / `upscale` / `tool_installer`（830行） / `path` / `process` / `log` / `notification` / `sound` / `wallpaper`
  - `lib/app`：`app` / `home_shell` / `providers` / `main`
  - `lib/core`：`models`（`convert_config` / `convert_settings` / `settings_screen_settings` / `output_format` / `optimize_type` / `target_filter` / `file_progress` / `process_status` / `result` / `sound_option` / `wallpaper_option`）+ `constants/app_constants`
- 国際化：`l10n.yaml` + `lib/l10n/app_en.arb` / `app_ja.arb`（BCP 47: `ja-JP` / `en-US`、空文字=自動）
- 主要パッケージ：`file_selector` / `path_provider` / `just_audio` / `flutter_desktop_notifications` / `material_ui` / `syncfusion_flutter_sliders` / `package_info_plus` / `archive` / `crypto` / `http` / `image` / `liquid_glass_easy` / `url_launcher` / `flutter_color_picker_plus`
- テスト：`test/` に9ファイル（`convert_screen` / `convert_view_model` / `settings_repository` / `sound` / `path` / `notify_completion` / `tool_install_view_model` / `update_button` / `widget`）
- CI/Release：`.github/workflows/ci.yml`（analyze/test/build macos）、`release.yml`（手動dispatchでpatch/minor/major bump、Git LFS取得、macOSビルド、タグpush、GitHub Release）

### 2.2 画面と機能

画面構成は `docs/design/ui.md`（左サイドナビ＋右コンテンツ：変換/設定/About）と
`docs/design/feature/images/` のスクリーンショットが正とする。

1. 変換画面（`docs/design/feature/convert.md`）
   - 入力：対象フォルダ選択＋手入力＋存在チェック、対象ファイル絞り込み（1/3/7/30日/全件）
   - アップスケール：拡大率1〜4（初期値2）、モデル選択（`tools/upscal/models/*.bin`一覧、初期値`realesr-animevideov3-x4`）
   - 圧縮：フォーマット（JPEG/PNG/JPEG XL/AV1/WebP、初期値JPEG XL）、最適化種別（アニメ/実写/速度/画質）、品質1〜100（初期値80）
   - 処理：並列数1〜CPUコア数（初期値 `コア数/2 - 1`）
   - 出力：出力フォルダ選択＋手入力＋存在チェック
   - 実行：非活性条件、多重防止、進捗表/進捗率/結果表のリアルタイム更新、完了時スナックバー（5秒、成功=緑/失敗=赤）、自動スクロール、先頭に戻るボタン
   - 完了時アクション：OS通知、サウンド再生
   - 変換フロー：対象選定→アップスケール→圧縮→出力、ファイル単位の並列実行（`docs/design/feature/convert-flow/convert-flow.md`）
2. 設定画面（`docs/design/feature/settings.md`）
   - 変換終了時のアクション：OS通知ON/OFF、サウンドON/OFF、成功/失敗サウンド選択（同梱＋ユーザー配置、試聴▶付き）
   - 基本設定：言語（自動/ja-JP/en-US）、背景画像（同梱`assets/images/wallpaper/wallpaper[1-3].jpg`＋ユーザー配置、jpg/png、ソート、サンプルprefix、フォールバック、同梱背景画像1）、透明度スライダー0.0〜1.0（初期値1.0）、背景色カラーピッカー（初期値白）
3. About画面（`docs/design/feature/about.md`）
   - アプリ名/アイコン/バージョン/GitHub/copyright表、アップデート確認ボタンと結果alert、ツールバージョン表（upscal-bin/models、JPEG/PNG/JPEG XL/AV1/WebP）
4. 初回起動（`tool_bootstrap` + `tool_install_view_model`）
   - tools展開の進捗表示、完了/失敗/再試行
5. アップデート（`update-application.md`、`logic/update/`）
   - 起動時バックグラウンドチェック＋手動チェック、`update-info.json`比較、ダウンロード＋適用

### 2.3 外部ツール（移行後も再利用）

`tools/` 配下のバイナリはSwiftUI移行後も `Process`（`Foundation.Process`）から呼び出す。
Flutter資産ではなく独立したCLI群として扱う。

| ツール | 用途 | 備考 |
|---|---|---|
| `upscal/bin/upscayl-bin` + `models/*.bin,*.param` | アップスケール | 全体で約356MBの大半を占める。Git LFS管理 |
| `jpegoptim/bin/<os>/jpegoptim` | JPEG圧縮 | |
| `pngoptim/bin/<os>/pngoptim` | PNG圧縮 | |
| `libjxl/bin/<os>/cjxl` + macOS同梱dylib群 | JPEG XL圧縮 | macOSは`*.dylib`のバンドルと`@rpath`解決が必要（ADR 0017） |
| `libavif/bin/<os>/avifenc` | AV1圧縮 | |
| `libwebp/bin/<os>/cwebp(.exe)` | WebP圧縮 | Google Storage由来。デコーダ（`dwebp`等）は未同梱 |

現行の圧縮パラメータは `docs/design/feature/convert-flow/compression.md` と
`compression_service.dart` が正とする。移行時に1:1で持ち込む。

### 2.4 永続化・パス

- 設定ファイル：`~/.config/tree-image-optimizer/settings.json`、トップレベルに`settings`/`batchConvert`/`easyConvert`セクション（`docs/design/feature/application-settings.md`、`settings_repository.dart`）
- アプリデータ基準：macOSは `~/Library/Application Support/tree-image-optimizer`（`path_service.dart`）
- `tools/` と `logs/` の配置はADR 0009に従う。SwiftUI版でも基準ディレクトリの考え方は変えない
- ユーザー配置資産：`~/.config/tree-image-optimizer/sounds/{success,error}`、`wallpaper/`
- 同梱資産：`assets/sounds/{success,error}/`、`assets/images/wallpaper/`、`assets/images/icon-tree-01.png`

### 2.5 プラットフォーム対応の変化

- 現行はクロスプラットフォーム（macOS/Windows/Linuxをコード上は考慮、ADR 0001）
- 移行後は **macOS専用** になる。これがADR 0019の主目的（Windows動作確認・配布の負荷削減）である
- 結果として `_osName()` 分岐（macos/windows/linux）や `.exe` 対応はSwiftUI版では不要になる
- 逆に失うもの：Windows/Linuxバイナリ同梱・配布、クロスプラットフォームCIの意義。リリースワークフローはmacOS単独に簡素化できる

## 3. 移行後の構成案

### 3.1 リポジトリ構成案

既存の `macos/`（Flutter製Runner）は残したまま、新規のSwiftUIアプリを追加する。
Flutter削除はフェーズ3完了後に判断し、フェーズ1〜3では共存させる。

```text
./
  docs/design/migrate.md        # 本書（フェーズ1成果物）
  TreeImageOptimizer/           # 新規SwiftUIアプリ（フェーズ2で作成）
    TreeImageOptimizer.xcodeproj
    TreeImageOptimizer/
      App/
      Features/Convert/
      Features/Settings/
      Features/About/
      Core/
      Services/
      Resources/
    TreeImageOptimizerTests/
    TreeImageOptimizerUITests/  # 必要に応じて
  tools/                        # 既存CLI群をそのまま再利用
  assets/                       # 同梱音声・壁紙・アイコンを再利用
  lib/                          # フェーズ3完了まで参照用に残す（仕様の正本扱い）
  macos/                        # 旧Flutter Runner。削除は別ADRで判断
```

Xcodeプロジェクト形式は標準の `.xcodeproj` とし、Swift Package Managerを併用する。
外部Swiftパッケージは原則使わず、まずはSwift標準＋Appleフレームワークで構成する。

### 3.2 アーキテクチャ対応表

| Flutter現行 | SwiftUI移行後 | 備考 |
|---|---|---|
| `StateNotifier` + Riverpod | `@Observable` + `@Environment` | グローバル状態は`@Environment`注入、画面固有状態は`@State` |
| ViewModel | `@Observable @MainActor`クラス | 命名は`ConvertViewModel`等を踏襲し対応関係を明確にする |
| UseCase/Repository/Service | `Service`層に集約し、必要に応じて`UseCase`を残す | Flutterの層構造を無理に再現せず、Swiftらしい薄い層にする |
| `Result<T>` | `Result<T, AppError>` または `throws` | エラー型を定義し、`LocalizedError`でUI表示文言を統一する |
| `ProcessService` | `ProcessRunner`（`Foundation.Process`ラッパー） | 終了コード・stdout/stderr・作業ディレクトリ・キャンセルを扱う |
| `PathService` | `AppPaths`（`FileManager`ラッパー） | Application Support基準、同梱リソースは`Bundle.main` |
| `LogService` | `OSLog`/`Logger`（`os`） | ログファイル出力が必要なら`logs/`への追記を維持する |
| `SettingsRepository` | `SettingsStore`（`Codable` + JSON） | `settings.json`のキー互換を維持する（後述） |
| `SoundService`（just_audio） | `AVFoundation`（`AVAudioPlayer`） | 試聴・完了時再生を置換 |
| `NotificationService` | `UserNotifications`（`UNUserNotificationCenter`） | 権限リクエストの流れを踏襲 |
| `file_selector` | `AppKit.NSOpenPanel` | フォルダ選択に使用。SwiftUIからは`NSOpenPanel`ラッパーで呼ぶ |
| `syncfusion`スライダー | SwiftUI `Slider`＋カスタムトラック | 色分けメモリはSwiftUIで再実装する |
| `flutter_color_picker_plus` | SwiftUI `ColorPicker` | 標準コントロールで代替可能 |
| `url_launcher` | `NSWorkspace.open` | GitHubリンク等に使用 |
| `package_info_plus` | `Bundle.main`のバージョン情報 | |
| `archive`/`crypto`/`http` | `Foundation`（`URLSession` + `CryptoKit`） | tools ZIP取得・SHA-256検証に使用 |
| `image`（Dart） | 必要時のみ`CoreGraphics`/`ImageIO` | 壁紙表示はSwiftUI `Image`、変換の中間処理は既存方針を踏襲する |
| `material_ui` | SwiftUI標準＋Liquid Glass | Finder風サイドバーは`NavigationSplitView`を使う |

### 3.3 UI置換方針

- 全体：`NavigationSplitView` でFinder風の左サイドナビ（変換/設定/About）＋右コンテンツ
- 外観：Liquid Glassを前提とする。macOS Tahoe 26の `.glassEffect` / ガラス系マテリアルを使い、現行の`liquid_glass_easy`の見た目を再現するのではなくApple標準に寄せる
- 変換画面：セクションカード構成は維持しつつ、トグル・ポップアップボタン・スライダ等のApple標準コントロールに置換する。進捗表・結果表は`Table`を第一候補とする
- 設定画面：サウンド試聴・言語・壁紙・透明度・背景色を同順序で配置し、help popoverは`help()`相当のUIに置換する
- About画面：アプリ情報表・バージョン表・アップデート確認ボタンを同順序で配置する
- 壁紙背景：アスペクト比維持（現行`BoxFit.contain`相当）＋背景色レターボックス＋不透明度を踏襲する
- 国際化：`.arb`ではなく`String Catalogs`（`.xcstrings`、ja/en）を使う。BCP 47の選択肢と自動判定の仕様は踏襲する

### 3.4 設定ファイル互換

`~/.config/tree-image-optimizer/settings.json` のトップレベルは `settings` / `batchConvert` / `easyConvert` とする。
当初は `convert` 単一セクションで共存させる方針だったが、かんたん変換画面の追加に伴い、
一括変換（`batchConvert`）とかんたん変換（`easyConvert`）で独立保存する形式に変更した。
旧形式の `convert` / `batch` キーは `batchConvert` として、`easy` キーは `easyConvert` として読み込み、新形式で書き換える。

- `settings`：`showOsNotification` / `playSound` / `successSound` / `errorSound` / `language` / `wallpaper` / `wallpaperOpacity` / `wallpaperBackgroundColor`
- `batchConvert`：`targetFilter` / `scale` / `model` / `format` / `optimizeType` / `quality` / `parallelCount` / `inputFolderPath` / `outputFolderPath`
- `easyConvert`：`scale` / `model` / `format` / `optimizeType` / `quality` / `parallelCount` / `outputFolderPath`
- 不正値の補正（範囲クランプ・初期値フォールバック）の仕様は `settings_repository.dart` を正本とする
- Swift側は`Codable`で読み書きし、欠損・破損時の挙動をFlutter版と一致させる

### 3.5 ツール実行・パス・署名

- バイナリの解決順序は現行`ToolInstaller`の方針を踏襲する（開発時はリポジトリ直下`tools/`、配布時はApplication Support配下）
- macOS配布時は`cjxl`同梱dylibの`@rpath`解決と実行権限（`chmod +x`相当）を維持する
- サンドボックス化する場合は外部プロセス実行・ファイルアクセスのentitlements設計が必要になる。フェーズ2開始前にサンドボックス有無を確定させること（安易に有効化しない）
- 公証（notarization）とGatekeeper警告の扱いは現行リリースフローを踏襲し、必要に応じて更新する

### 3.6 アップデート機構

現行のGitHub Releases＋`update-info.json`比較＋ダウンロード適用の仕組みは、
SwiftUI版では以下のいずれかに置換する。フェーズ3開始前に確定する。

1. Sparkle 2系（App Store外配布の定番）
2. 自前実装（`URLSession`で`update-info.json`取得＋ZIP展開＋置換）
3. App Store配布（審査・運用を含めた別検討が必要）

フェーズ2ではダミーのバージョン表示とボタン遷移のみとし、実ダウンロードは実装しない。

## 4. フェーズ分割

### フェーズ1（本書）

- 成果物：`docs/design/migrate.md`（本書）
- 完了条件：現行機能・ツール・設定・バージョン方針が文書化され、フェーズ2の着手順序が合意されること
- 実装・Xcodeプロジェクト作成は行わない

### フェーズ2（UIのみ＋画面遷移）

1. `TreeImageOptimizer/` Xcodeプロジェクトを作成（Xcode 26.6、Swift 6.3.3、macOS Tahoe 26 SDK）
2. `NavigationSplitView`＋3画面（変換/設定/About）の空UIと画面遷移を実装
3. 壁紙背景・透明度・背景色の表示枠組みのみ実装（実データはダミー）
4. `String Catalogs`（ja/en）の枠組みのみ用意
5. ユーザーレビュー：この時点でUIの誤りを指摘してもらい、フェーズ3に入らない

完了条件：ビルドが通り、3画面の遷移と主要コントロールの配置が確認できること。
機能（変換・保存・ツール実行・通知・音声・更新）は配線しない。

### フェーズ3（テスト先行＋機能実装）

原則：各機能は **先にテストクラスを作成してから実装する**。

推奨順序：

1. `AppPaths` / `SettingsStore`（設定の読み書き・補正・互換）
2. `ProcessRunner`（終了コード・出力・作業ディレクトリ・異常系）
3. `ToolInstaller`相当（存在チェック・コピー・権限・ダウンロード・SHA-256）
4. 対象ファイル選定・モデル一覧（`get_target_files` / `get_upscale_models`相当）
5. アップスケール実行（`upscayl-bin`呼び出し）
6. 圧縮実行（5形式のパラメータを`compression.md`通り実装）
7. 出力・並列実行・進捗集計（`convert-flow.md`通り）
8. 通知・サウンド・壁紙・言語・バージョン表示
9. アップデート機構（方式確定後に実装）
10. CI（`flutter analyze/test/build`相当を`xcodebuild test/build`に置換）

テストは `Swift Testing`（`@Test`）を第一候補とし、UI差分が必要な範囲のみ`XCTest/XCUITest`を使う。
Flutterの既存テスト（9ファイル）は仕様の正本として残し、Swiftテストの期待値と突き合わせる。
既存テストの削除は行わない（AGENTS.md禁止事項）。

## 5. リスクと未確定事項

| # | 項目 | 内容 | 対応 |
|---|---|---|---|
| 1 | 対象OSの下限 | Tahoe 26専用か、Sequoia等も対象か未確定 | フェーズ2開始前に確定。Liquid Glass前提ならTahoe以降に寄せる |
| 2 | Intel Mac対応 | TahoeはIntelも対象だが、新規はApple Silicon優先か要判断 | 配布アーカイブ（universal/arm64のみ）とCIランナーで確定する |
| 3 | サンドボックス | 有効化すると外部ツール実行・ファイルアクセスに影響 | フェーズ2開始前に有無を確定。安易に有効化しない |
| 4 | 署名・公証 | tools同梱dylib・バイナリの署名維持が必要 | 現行release.ymlの署名手順をSwiftUI用に移植する |
| 5 | Git LFS（約365MB超のtools） | SwiftUI用CIでもLFS取得が必須 | ワークフローを移植し、キャッシュと取得時間を検証する |
| 6 | `macos/`旧Runnerの扱い | Flutter版と共存させる期間 | 削除は別ADRで判断。本計画では共存を前提とする |
| 7 | アップデート方式 | Sparkle/自前/App Storeの三択 | フェーズ3開始前に確定する |
| 8 | `syncfusion`スライダーの再現度 | 色分けメモリ等の完全再現は工数がかかる | Apple標準に寄せて簡略化する方針をユーザーレビューで合意する |
| 9 | 音声・壁紙のユーザー配置 | 再起動読み込み等の仕様踏襲 | `README.md`の配置仕様をSwiftUI版でも維持する |

## 7. フェーズ2 UIレビュー反映（第1回）

フェーズ2のUI試作に対するレビュー指摘と反映内容を記録する。
機能仕様自体の変更ではなく、SwiftUI版の行レイアウト定義である。

### 一括画像変換画面

- 入力：`対象フォルダ`＋`フォルダ`ボタン＋テキスト＋ℹ️を1行に配置する
- 入力：`対象ファイル`の左ラベルは廃止し、プルダウン＋ℹ️を1行に配置する
- アップスケール：`拡大率`＋ℹ️＋スライダーを1行に配置する
- アップスケール：`モデル`の左ラベルは廃止し、プルダウン＋ℹ️を1行に配置する
- 圧縮：`フォーマット`の左ラベルは廃止し、プルダウン＋ℹ️を1行に配置する
- 圧縮：`最適化種別`の左ラベルは廃止し、プルダウン＋ℹ️を1行に配置する
- 圧縮：`品質`＋ℹ️＋スライダーを1行に配置する
- 処理：`並列数`＋ℹ️＋スライダーを1行に配置する
- 出力：`出力フォルダ`＋`フォルダ`ボタン＋テキスト＋ℹ️を1行に配置する
- 変換実行ボタンは横幅100%にする

### 設定画面

- カードは横幅100%にする
- 各行は説明ラベルを左端・ℹ️を右端に置き、その間にプルダウンを100%幅で配置する

### About画面

- バージョン情報は`Table`ではなく`Grid`で全行表示し、スクロールバーが発生しないようにする

### フェーズ2 UIレビュー反映（第2回）

- 一括画像変換画面の入力：`対象ファイル`の行は左寄せにする（プルダウンを100%幅に広げず、先頭に配置する）
- 一括画像変換画面のアップスケール：`モデル`の行は左寄せにする
- 一括画像変換画面の圧縮：`フォーマット`の行は左寄せにする
- 一括画像変換画面の圧縮：`最適化種別`の行は左寄せにする

### フェーズ2 UIレビュー反映（第3回）

- 一括画像変換画面の2項目行（例：`対象フォルダ`・`拡大率`）：ラベルは左端固定・ℹ️は右端固定とし、ラベルとℹ️の間を横幅一杯で表示する
- 設定画面の変換終了時のアクション：`成功時のサウンド`・`失敗時のサウンド`の左ラベルを廃止する
- 設定画面の基本設定：`言語`・`背景画像`・`背景色`の左ラベルを廃止する

## 8. フェーズ3実装状況

テストファーストで実装し、`xcodebuild test` で全31テストが通過している。
テストターゲット `TreeImageOptimizerTests`（Swift Testing）を追加し、
アプリ本体のビルド（Debug/Release）も確認済み。

| # | 項目 | 状態 | 対応 |
|---|---|---|---|
| 1 | `AppPaths` / `SettingsStore` | 実装＋テスト済み | `settings.json` のキー互換・補正仕様をFlutter版と一致させた |
| 2 | `ProcessRunner` | 実装＋テスト済み | 終了コード・stdout/stderr・作業ディレクトリ・異常系 |
| 3 | `ToolInstaller`相当 | 実装＋テスト済み | 存在チェック・ローカルコピー・権限・libwebp取得・SHA-256。単一ZIP配布基盤は未実装 |
| 4 | 対象ファイル選定・モデル一覧 | 実装＋テスト済み | 拡張子・更新日絞り込み・ソート・`.bin`走査 |
| 5 | アップスケール実行 | 実装（引数テスト済み） | `upscayl-bin` 呼び出し。実バイナリでのE2Eは未実施 |
| 6 | 圧縮実行（5形式） | 実装（引数テスト済み） | `compression.md` 通りのパラメータ。中間JPEG/PNG生成はImageIOで代替 |
| 7 | 出力・並列実行・進捗集計 | 実装（ファイル名テスト済み） | バッチ並列＋進捗コールバック。`ConvertViewModel` に配線済み |
| 8 | 通知・サウンド・壁紙・言語・バージョン | 実装＋テスト済み | `UNUserNotificationCenter` / `AVAudioPlayer` / 壁紙解決 / ロケール適用 |
| 9 | アップデート機構 | 確認・検証まで実装 | `check/download/verify` のみ。適用（差し替え・再起動）は配布方式未確定のため見送り |
| 10 | CI | 追加済み | `.github/workflows/swiftui.yml`（build＋test）。Flutter用CIは残置 |

## 9. SwiftUIでは実現できない／見送る項目

Flutterでは実装できたがSwiftUI版で対応しない項目を記録する。

| # | 項目 | 区分 | 内容 |
|---|---|---|---|
| 1 | Windows/Linux版の提供 | 対象外（意思決定） | 技術的不可ではなくADR 0019の目的。`_osName()` 分岐・`.exe` 対応は廃止し、macOS専用（`bin/macos` 固定）とした |
| 2 | App Store配布と外部CLI同梱の両立 | 見送り（確定） | App Store配布の予定なし。サンドボックス制約上、署名なし外部バイナリの実行と両立困難なため、現行の自前アップデート＋公証配布を踏襲する |
| 3 | アップデートの適用（差し替え・再起動） | 未実装 | 確認・ダウンロード・SHA-256検証・展開・`.app` 検出まで実装。ヘルパーによる置換・再起動は配布方式確定後に実装する |
| 4 | 単一ZIP（`tools-vVERSION.zip`）配布基盤 | 未実装 | 不足時はローカル`tools/`コピーとlibwebp取得で対応。GitHub Releasesからの単一ZIP取得は配布開始時に実装する |
| 5 | Syncfusionスライダーの色分けメモリ完全再現 | 簡略化 | 標準`Slider`に置換。リスク#8の確定事項としてユーザーレビューで合意済み扱いとする |
| 6 | material_uiのhover popover | 置換 | SwiftUIの`.help()` に置換。同等機能のため問題なし |
| 7 | just_audioの高度な再生機能 | 不要 | ローカルファイル再生のみ必要なため`AVAudioPlayer`で充足 |

なお以下は代替手段で実現済みであり、不可項目ではない。

- Dart `package:image` の中間JPEG/PNG生成・フォールバック再エンコード → ImageIO/CoreGraphicsで代替
- `flutter_desktop_notifications` → `UserNotifications`、`url_launcher` → `NSWorkspace`、`package_info_plus` → `Bundle`、`archive`/`crypto`/`http` → Foundation＋CryptoKit＋URLSession、`flutter_color_picker_plus` → SwiftUI標準`ColorPicker`

## 10. 実装上の落とし穴と対策

### `.preferredColorScheme` の付け外しはしない

- 事象：外観モード「自動」の実装として、自動時は`.preferredColorScheme`モディファイア自体を付けず、明示モード時のみ付与していた。ライト→自動の遷移で配色がライトに張り付いたまま残り、ライトUI＋ダーク背景＋黒文字という壊れた表示になった（ダーク→自動では張り付き先がダークのため正常に見える）。
- 原因：モディファイアの付け外しによる配色切替えはSwiftUIが確実に反映しない。
- 対策：モディファイアは常に付けたまま、自動時はシステム設定（`AppleInterfaceStyle`）を読み取って`.light`／`.dark`の明示値に解決して渡す。値の変更による切替えは確実に反映される。実装は`RootView.appearanceScheme`を参照。
- 関連：`NSApp.effectiveAppearance`はアプリ側の上書きを反映してしまうため、システム設定の判定には使わないこと（`SettingsViewModel.systemWallpaperBackgroundColorHex`のコメントも参照）。

## 11. 参照

- ADR 0019：`docs/adr/0019-migrate-from-flutter-to-swiftui/0019-migrate-from-flutter-to-swiftui.md`
- 画面仕様：`docs/design/feature/convert.md`、`settings.md`、`about.md`、`ui.md`
- 変換フロー：`docs/design/feature/convert-flow/`
- システム：`docs/design/system.md`
- 設定ファイル：`docs/design/feature/application-settings.md`
- 画面画像：`docs/design/feature/images/`
- 現行実装（正本）：`lib/`、`pubspec.yaml`、`l10n.yaml`、`analysis_options.yaml`
- CI/Release：`.github/workflows/ci.yml`、`release.yml`
