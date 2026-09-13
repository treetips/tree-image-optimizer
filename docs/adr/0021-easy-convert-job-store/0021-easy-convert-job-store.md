# かんたん変換の実行状態を共有ジョブ層に分離し入力エリアを無効化する

- ステータス: Accepted
- 影響範囲: かんたん変換画面・サイドナビ・全体構造（`docs/design/system.md`）
- 関連: ADR 0020（一括変換の実行状態を共有ジョブ層に分離する）

## 背景

かんたん変換画面も `EasyConvertView` が `@State` で `EasyConvertViewModel` を新規生成していたため、
一括変換と同型の問題（画面遷移で表示リセット＋裏で処理継続）があった。

また入力エリアは `.disabled(viewModel.isRunning || ...)` を付けていたが、ドロップ受け付けの実体は
AppKit の `FileDropNSView`（`registerForDraggedTypes`）であり、SwiftUI の `.disabled` では
ドラッグ受け付けまで止まらないため、変換中にドロップできてしまう状態だった。

## 決定

ADR 0020 と同じ構成をかんたん変換にも適用する。

- 所有: `Features/EasyConvert/EasyConvertJobStore.swift`（`@Observable` + `@MainActor`）を新設し、
  `TreeImageOptimizerApp` で生成して `RootView` 経由でサイドナビと `EasyConvertView` に渡す。
- `EasyConvertJobStore` の責務: `isRunning`・進捗・件数・結果メッセージ・直近結果の保持と、
  `ConvertOrchestrator` への委譲・進捗反映・完了サウンド。
- `EasyConvertViewModel` の責務: フォーム入力・バリデーション・設定永続化・ドロップ受付・
  設定スナップショット作成。実行状態は持たず共有の `jobStore` を参照する。
  既存テスト（`EasyConvertTests`）との互換性のため、実行状態の読み取り専用プロキシを公開する。
- 入力エリアの無効化は二層で行う。SwiftUI 側の `.disabled` とタップガードに加え、
  `FileDropView` / `FileDropNSView` に `isEnabled` を持たせ、`draggingEntered` では `.copy` を返さず、
  `performDragOperation` では受け付けない。`isRunning` が false に戻れば自動的に有効に戻る。
- サイドナビは各ジョブの `isRunning` を購読する。実行中はメニューのアイコンをローディング表示に切り替え、
  一括変換は右端に進捗%も表示する（かんたん変換は1ファイルのため%なし）。終了すれば元のアイコンに戻し、進捗%を非表示にする。

## 結果

- 画面遷移経路によらず実行状態が維持される。戻ってきた画面は実行中のまま表示される。
- 変換中のドロップ・クリック選択が受け付けられなくなり、二重起動を防げる。
- `EasyConvertTests` は変更なしで通る。

## 適合確認

- `docs/design/system.md` の View -> Model -> Service の一方向を保つ。
  `EasyConvertJobStore` はModel層の共有状態として位置づけ、Service（`ConvertOrchestrator`）に依存する。
