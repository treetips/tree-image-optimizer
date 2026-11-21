# CONTEXT

このドキュメントは `tree-image-optimizer` の**現在のアーキテクチャ俯瞰**です。
新規参加者が全体像を掴むための入口として、実装に基づく事実のみを記述しています。
個別の技術的決定の理由は [ADR INDEX](./adr/INDEX.md) を参照してください。

## プロジェクトの目的

macOS 向けデスクトップアプリ（SwiftUI）です。フォルダ内の画像を**一括で並列に最適化**します。

最適化は次の2段階です。

1. **アップスケール**: 超解像技術で1〜4倍に拡大する
2. **圧縮**: JPEG / PNG / JPEG XL / AV1 / WebP で圧縮する

ユーザーは「フォルダを選択 → アップスケール種別を選択 → エンコード種別を選択」して一括変換を実行します。
1ファイルだけを手軽に変換する「かんたん変換」もあります。

画面仕様は [docs/design/feature/](./design/feature/) に、システム全体の設計は [docs/design/system.md](./design/system.md) にあります。

## 全体アーキテクチャ

レイヤは `View` → `Model` → `Service` の**一方向**で、Apple 推奨の Observation ベースです。
`UseCase` / `Repository` 層は設けず、オーケストレーションは Service に集約して層を薄く保ちます。
いずれのパスも `TreeImageOptimizer/TreeImageOptimizer/` 配下です。

| 層      | 責務                                                                                              | 配置例                                                                                                               |
| :------ | :------------------------------------------------------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------- |
| App     | アプリのエントリポイントと画面の骨格                                                              | `App/TreeImageOptimizerApp.swift`、`App/RootView.swift`                                                              |
| View    | SwiftUI の宣言的UI。業務状態は持たず Model を表示・操作に結びつける                               | `Features/Convert/ConvertView.swift`                                                                                 |
| Model   | `@Observable` + `@MainActor`。画面状態と実行指示を持ち Service を呼ぶ                             | `Features/Convert/ConvertViewModel.swift`、`Features/Convert/ConvertJobStore.swift`、`Core/ConversionSettings.swift` |
| Service | 永続化・外部プロセス・Apple フレームワークの薄いラッパー。`Sendable` で UI 判断ロジックを持たない | `Services/`                                                                                                          |
| Core    | 機能横断の共有物（データ定義・エラー型・テーマ・文言解決）                                        | `Core/Models.swift`、`Core/AppError.swift`、`Core/L10n.swift`                                                        |

### 状態管理の要点

- [Observation フレームワーク](https://developer.apple.com/documentation/observation)（`@Observable` / `@State` / `@Environment`）を使います。
- Swift 6 言語モードです。UI 状態は `@MainActor` で隔離し、Service は `Sendable`、非同期は `async/await` と構造化並行処理です。
- **共有状態**（設定・アップデート確認・一括変換ジョブ・かんたん変換ジョブ）は `TreeImageOptimizerApp` が生成し、`RootView` 経由で各画面とサイドナビへ**同一インスタンス**を渡します。これにより画面遷移で View が再生成されても実行状態が維持され、孤児タスクになりません。
- **実行状態**は画面ごとの `@State` ではなく共有ジョブ層（`ConvertJobStore` / `EasyConvertJobStore`）が持ちます。

## 変換パイプラインの流れ

処理は `フォルダ選択 → アップスケール → 圧縮 → 出力` の順です。フロー図は
[docs/design/feature/convert-flow/](./design/feature/convert-flow/) にあります。

1. **対象ファイル選定**: `TargetFiles.list(in:modifiedWithinDays:)` が入力フォルダを走査します。拡張子は `jpg` / `jpeg` / `png` / `webp` の**静止画のみ**で、更新日数による絞り込みもここで行います。
2. **変換計画**: `ConversionPlanner` が各ファイルの寸法とサイズから倍率・縮小先・品質を決めます（固定モードは全ファイル共通、自動モードはファイルごとに最適化。ADR 0049）。
3. **アップスケール**: `UpscaleService` が外部バイナリを呼びます。GPU バウンド。
4. **圧縮**: `CompressionService` が各エンコーダを呼びます。CPU バウンド。
5. **出力**: `ConvertOrchestrator.installOutput(from:to:)` が中間ファイルを出力先へ確定します。

### ステージ別ワーカーと並列数

アップスケールと圧縮は**別々のワーカー群**として動き、間をキュー（`UpscaledQueue`）でつなぎます。
片方の完了を待たずにもう片方が次々と処理できるため、GPU と CPU が同時に使われます（ADR 0034）。

- 並列数（スライダー値）を GPU と CPU に配分します。`stageWorkerCounts` はアップスケールを最大3に抑え、残りを圧縮へ回し、小さな並列数でも最低1ずつ確保します。
- アップスケールは**最大4ファイルを1プロセス**にまとめ、ディレクトリ一括実行でプロセス起動の固定費を削ります（ADR 0035）。バッチは同じ倍率・縮小先のファイルだけで組み、自動モードでも一覧表の上から順に最大8件を先読みしてまとめます（ADR 0053）。
- **処理枠**は並列数ぶんです。枠はアップスケール完了では空かず、**出力が完了したときだけ**空きます（ADR 0038）。
- エンコーダに渡す総スレッド数は並列数ぶんで、それを圧縮ワーカー数で割って各プロセスへ配ります。そのためスライダーの位置がそのまま CPU 負荷の目安になります（ADR 0039）。既定値は Pコア数の半分です（ADR 0036）。
- 実行中は**一時停止とキャンセル**ができます（ADR 0054）。キャンセルは実行中の外部プロセスを終了し、出力済みファイルは残します。

## 主要コンポーネントの対応関係

| コンポーネント        | 配置                                             | 役割                                                                                                                                      |
| :-------------------- | :----------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------- |
| `ConvertOrchestrator` | `Services/ConvertOrchestrator.swift`             | 変換全体のオーケストレーション。ワーカー群・スケジューラ・キューの生成と集計。ステージ別ワーカー実体は `ConvertOrchestratorWorkers.swift` |
| `UpscaleService`      | `Services/UpscaleService.swift`                  | アップスケール実行。`upscayl-bin` / `realcugan-ncnn-vulkan` へ振り分け、実行前後の検証も行う                                              |
| `CompressionService`  | `Services/CompressionService.swift`              | 画像圧縮実行。フォーマット別に各エンコーダの引数を組み立てる                                                                              |
| `ConvertJobStore`     | `Features/Convert/ConvertJobStore.swift`         | 一括変換の実行状態（進捗・結果表）を保持する共有ジョブ層。実処理は `ConvertOrchestrator` に委譲                                           |
| `EasyConvertJobStore` | `Features/EasyConvert/EasyConvertJobStore.swift` | かんたん変換の共有ジョブ層                                                                                                                |
| `ConversionSettings`  | `Core/ConversionSettings.swift`                  | 両画面で共有する変換設定。保存と `ConvertConfig` スナップショット生成を担う                                                               |
| `TargetFiles`         | `Services/TargetFiles.swift`                     | 対象ファイル選定（拡張子と更新日数の絞り込み）                                                                                            |
| `ConversionPlanner`   | `Services/ConversionPlanner.swift`               | ファイルごとの倍率・縮小先・品質の計画                                                                                                    |
| `AppPaths`            | `Services/AppPaths.swift`                        | 各種パスの解決（`tools/` 配下のバイナリや設定ファイル）                                                                                   |
| `SettingsStore`       | `Services/SettingsStore.swift`                   | `settings.json` の読み書き                                                                                                                |
| `ToolInstaller`       | `Services/ToolInstaller.swift`                   | 外部ツールの初回展開と修復                                                                                                                |
| `AppError`            | `Core/AppError.swift`                            | アプリ共通のエラー型                                                                                                                      |

`ConvertConfig` は `ConversionSettings.makeConfig()` が作る**実行用スナップショット**です。
実行中に UI の設定が変わっても処理がぶれないようにするためです。

## 外部ツールの同梱とインストール

変換処理はすべて**外部バイナリのサブプロセス**として実行します（`ProcessRunner` 経由）。

同梱ツールは `tools/` 配下に配置し、実行時は `~/Library/Application Support/tree-image-optimizer/tools/` に展開されます。

| 用途                   | バイナリ                | 配置                                                   |
| :--------------------- | :---------------------- | :----------------------------------------------------- |
| アップスケール         | `upscayl-bin`           | `tools/upscal/bin/`（モデルは `tools/upscal/models/`） |
| アップスケール（任意） | `realcugan-ncnn-vulkan` | `tools/realcugan/bin/macos/`                           |
| JPEG 圧縮              | `jpegoptim`             | `tools/jpegoptim/bin/macos/`                           |
| PNG 圧縮               | `pngoptim`              | `tools/pngoptim/bin/macos/`                            |
| JPEG XL 圧縮           | `cjxl`                  | `tools/libjxl/bin/macos/`                              |
| AV1 圧縮               | `avifenc`               | `tools/libavif/bin/macos/`                             |
| WebP 圧縮              | `cwebp`                 | `tools/libwebp/bin/macos/`                             |

- 起動時に `ToolBootstrapModel` が `ToolInstaller.ensureInstalled(progress:)` を呼び、揃っていなければ修復します。完了まで操作はブロックされます。
- 修復は**開発用ローカルの `tools/` コピーを優先**し、無ければネットワーク取得します。取得元があるのは `libwebp`（Google Storage）と `Real-CUGAN`（GitHub Releases）のみで、それ以外はローカルに無ければエラーです。
- 配布ビルドにはツール一式を同梱します（ADR 0048）。libjxl は依存 dylib ごと `@loader_path` で解決する形で同梱します（ADR 0017、ADR 0056）。
- Real-CUGAN は任意ツールです。未配置の場合は選択肢を無効化します。実行前に `.param` と `.bin` のペアを確認するのは、欠けていてもバイナリが終了コード0で黒画像を出すためです。

## 設定の保存

設定は `~/.config/tree-image-optimizer/settings.json` に保存され、次回起動時に復元されます（`SettingsStore`）。

- トップレベルは `settings` / `batchConvert` / `easyConvert` の3セクションです。
- `batchConvert` は一括変換画面、`easyConvert` はかんたん変換画面の設定で、**独立に保存**されます。
- ファイルが無い・壊れている場合は初期値を保存して返します。不正値は補正し、旧形式のキー（`convert` / `batch` / `easy`）は新形式へ移行します。

ユーザーが任意に配置する資産も同じディレクトリ配下です。

- `~/.config/tree-image-optimizer/sounds/success` : 成功時のサウンド
- `~/.config/tree-image-optimizer/sounds/error` : 失敗時のサウンド
- `~/.config/tree-image-optimizer/wallpaper` : 背景画像

いずれもアプリの再起動で読み込まれます。ログは `~/Library/Application Support/tree-image-optimizer/logs/` に出力されます（ADR 0047）。

## 対応フォーマット

### 入力

`TargetFiles.supportedExtensions` が受け付ける**静止画のみ**です。

- `jpg` / `jpeg`
- `png`
- `webp`
- `heic` / `heif` / `avif`

`gif` とアニメーション形式（APNG 等）は対象外です。外部アップスケーラがアニメーションを
マルチフレームとして扱わず先頭フレームだけを読み出すためで、入力フィルタで対象外にして
静止画前提を保っています。詳細は [ADR 0063](./adr/0063-post-verify-still-image-only.md) を
参照してください。`heic` / `heif` / `avif` は静止画として受け付け、アップスケールの直前に
中間 PNG へデコードして処理します（ADR 0069）。

### 出力

`OutputFormat`（`Core/Models.swift`）の5種類です。既定は JPEG XL です。

| フォーマット | 拡張子  | エンコーダ                     |
| :----------- | :------ | :----------------------------- |
| JPEG         | `.jpg`  | ImageIO で生成後に `jpegoptim` |
| PNG          | `.png`  | ImageIO で生成後に `pngoptim`  |
| JPEG XL      | `.jxl`  | `cjxl`                         |
| AV1          | `.avif` | `avifenc`                      |
| WebP         | `.webp` | `cwebp`                        |

出力ファイル名は入力名の**最初の `.`** より前をベースにし、出力フォーマットの拡張子を付けます。
同名ファイルが既に存在する場合は置き換えます。最適化種別ごとのパラメータは
[docs/design/feature/convert-flow/compression.md](./design/feature/convert-flow/compression.md) にあります。

## 開発フロー

### 環境構築

`./setup.sh` で Homebrew 依存（Brewfile）、git hooks（prek）、VSCode 拡張を導入します。

### 変更後の検証手順

AGENTS.md の順序に従い、次の順で実行します。

```shell
swiftlint                                       # 規約違反の検出（自動修正は --fix）
swift format format -i -r TreeImageOptimizer    # フォーマット
xcodebuild ... build                            # コンパイルエラーの確認
```

設定はリポジトリ直下の `.swiftlint.yml` と `.swift-format` で管理します。
`swift-format` は Xcode ツールチェーン同梱のため追加インストールは不要です。

Markdown を修正した場合は `rumdl` を使います（`./tools/rumdl.sh` 経由でも可）。

```shell
rumdl fmt      # フォーマット
rumdl check    # lint
```

### git hooks

`prek` で commit 時に次が走ります（ADR 0044）。

- `rumdl fmt` : Markdown の整形。差分が出たら commit が中断されます。
- Betterleaks : ステージ済み差分の機密情報チェック。

hooks は GUI から commit しても動くよう、`tools/` 配下のラッパースクリプトを経由します。

### ADR の運用

技術的な決定・変更は **`docs/adr/` に ADR として記録**し、[INDEX.md](./adr/INDEX.md) に追加します。
判断の理由を残すことが目的のため、「何を決めたか」だけでなく「なぜ他の案を採らなかったか」も書きます。

### ブランチとコミット

- コミットメッセージは [Conventional Commits](https://www.conventionalcommits.org/ja/) に準拠し、**日本語**で記述します。Why を書きます。
- コードには How、テストコードには What、**コードコメントには Why not** を書きます。
- main ブランチへの直接 push は禁止で、feature ブランチから PR を作成します。
- PR 作成前に [コードレビュー](./design/code-review.md) します（対象は Swift 関連のみ）。
- Xcode のバージョンは `.xcode-version` で管理します。

## 関連ドキュメント

- [ADR INDEX](./adr/INDEX.md) : 全 ADR の一覧
- [docs/design/system.md](./design/system.md) : システム全体の設計
- [docs/design/feature/](./design/feature/) : 画面ごとの仕様
- [docs/design/feature/convert-flow/](./design/feature/convert-flow/) : 変換パイプラインのフロー
- [docs/design/release-flow.md](./design/release-flow.md) : リリース手順
- [docs/design/git.md](./design/git.md) : Git 運用ルール
- [docs/design/github.md](./design/github.md) : GitHub 運用ルール
- [README.md](../README.md) : ユーザー向けの概要
