# 一括変換の実行状態を共有ジョブ層に分離する

- ステータス: Accepted
- 影響範囲: 一括変換画面・サイドナビ・全体構造（`docs/design/system.md`）
- 関連: ADR 0002（アプリケーションアーキテクチャ）、ADR 0019（FlutterからSwiftUIに移行する）

## 背景

`RootView` は `navigation.selection` の切替でdetailの `ConvertView` を再生成する。
`ConvertView` が `@State` で `ConvertViewModel` を新規生成していたため、遷移で表示は
`isRunning=false`・進捗0・結果表空にリセットされるのに、`Task { await execute() }` だけが
裏で継続する孤児タスクになっていた。二重起動も可能な状態だった。

サイドナビをdisableにする案は、メニュー以外の経路（メニューコマンド・将来のショートカット等）
からの画面移動を防げず、ガード箇所を気にし続ける必要があるため採用しない。

## 決定

一括変換の実行状態を `Features/Convert/ConvertJobStore.swift`（`@Observable` + `@MainActor`）に
分離し、画面ではなくアプリ層で所有する。

- 所有: `TreeImageOptimizerApp` で生成し、`RootView` 経由でサイドナビと `ConvertView` に同一インスタンスを渡す。
- `ConvertJobStore` の責務: `isRunning`・`rows`・進捗・件数・経過時間・`resultMessage` の保持と、
  `ConvertOrchestrator` への委譲・進捗反映・完了通知（通知・サウンド）。
- `ConvertViewModel` の責務: フォーム入力・バリデーション・設定永続化・対象列挙・設定スナップショット作成。
  実行状態は持たず、共有の `jobStore` を参照して `canRun` 判定と開始指示のみ行う。
- `UseCase` / `Repository` 層は設けない方針を維持する。オーケストレーションは従来通り
  `ConvertOrchestrator`（Service）に集約する。
- 対象外: `EasyConvert` は同型の問題を持つが、今回の変更範囲には含めない。

## 結果

- 画面遷移経路によらず実行状態が維持される。戻ってきた `ConvertView` は実行中のまま
  （実行ボタンは `変換中...` のまま非活性）表示される。
- サイドナビは `jobStore.isRunning` を購読し、一括変換メニューに実行中表示を行う。
- `ConvertViewModel` から実行状態がなくなるため、単体テストしやすい境界になる。

## 適合確認

- `docs/design/system.md` の View -> Model -> Service の一方向を保つ。
  `ConvertJobStore` はModel層の共有状態として位置づけ、Service（`ConvertOrchestrator`）に依存する。
- 状態管理の「共有状態は `TreeImageOptimizerApp` で生成し、下位Viewへ渡す」に適合する。
