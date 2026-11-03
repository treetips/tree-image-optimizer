# 実行結果の絞り込み選択を保存して復元する

## ステータス

- 承認済み (Accepted)

## 背景・課題

実行結果の表の絞り込み（`待機中` `実行中` `成功` `失敗`）は `ConvertViewModel` の
メモリ上の値だけを持っていた。ViewModelは `ConvertView` の `@State` として生成されるため、
サイドナビで別画面へ移動して戻る、あるいはアプリを再起動すると、
毎回「全チェック」の既定状態に戻って選択が失われていた。

## 決定

- `BatchSettings`（`settings.json` の `batchConvert`）に次の4項目を追加する。既定は `true`。
  - `showWaiting`（待機中）
  - `showRunning`（実行中）
  - `showSuccess`（成功）
  - `showFailure`（失敗）
- `ConvertViewModel` の各プロパティに `didSet` で保存を組み込み、
  `loadPersisted()` で復元する。他のフォーム項目（拡大率・品質など）と同じ配線にする。
- 既存設定にキーが無い場合は `boolValue` が既定値（全チェック）で補い、
  再書き込みフラグを立ててファイルへ追記する。読み込みは一度だけ書き換わる。

## 代替案

- `ScreenSettings` に置く
  - 却下: `ScreenSettings` は設定画面（`settings` セクション）の設定で、
    一括変換画面固有の表示形式の選好ではない。かんたん変換画面には表も絞り込みも無い。
- 実行状態と合わせて `ConvertJobStore` が持つ
  - 却下: 進捗・結果はサイドナビ切替をまたいで維持する共有状態だが、
    絞り込みは表示の選好であり、次回起動までは維持しない方針の実行状態とは役割が違う。
    保存したければ結局 `settings.json` に書くことになる。
- `@AppStorage` を使う
  - 却下: 設定の読み書きを `SettingsStore` に一本化する既存方針（ADR 0010）から外れ、
    保存先が二重になる。
- 絞り込みを行ごとではなく列ごとに固定するなど、UIの作り自体を見直す
  - 却下: 本件は選択状態の保持に限定する。UI変更は要求されていない。

## 結果

- 次回起動時だけでなく、サイドナビの切替で画面を再生成したときも選択状態が維持される。
- 初期値は従来どおり4項目ともチェック済み。既存の設定ファイルは読み込み時に一度だけ
  書き換えられ、以降はユーザーの選択状態が保持される。
- かんたん変換画面には絞り込みが無いため、影響しない。
- 単体テスト:
  - `SettingsStoreTests.roundTripsResultFilter`
  - `SettingsStoreTests.resolvesMissingResultFilter`
  - `ConvertViewModelResultFilterTests.resultFilterIsPersisted`
- 実装箇所:
  - `TreeImageOptimizer/TreeImageOptimizer/Services/SettingsStore.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Features/Convert/ConvertViewModel.swift`
