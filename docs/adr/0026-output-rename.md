# 一括変換の出力確定を copy ではなく rename にする

## ステータス

- 承認済み (Accepted)

## 背景・課題

`ConvertOrchestrator.processFile` はアップスケールと圧縮を
`fm.temporaryDirectory` 配下の1時ディレクトリで行い、圧縮結果を出力先に
`copyItem` で複製していた。コピー元の中間ファイルは完了後に削除されるため、
実態としては管理が移るだけなのに全データの読み書きが発生し、大きな画像ほど
出力段階の壁時間が伸びていた。

## 決定

- `ConvertOrchestrator.installOutput(from:to:)` を新設し、確定方法を1箇所に集約する。
    - 出力先フォルダが無ければ作成する。
    - 同名出力が既にあれば削除する（既存の上書き仕様を維持）。
    - `FileManager.moveItem` で移動する。同一ボリュームなら rename(2) で O(1) で完了する。
- `processFile` の出力段階は `installOutput` を呼び出すのみにし、
  copy + remove の手順書きを廃止する。

## 代替案

- `posix_spawn` の `rename(2)` を直接呼ぶ
    - 却下: `FileManager.moveItem` が rename を internal に使用するため不要。
      Foundation の皮に済ませたほうがエラー処理が ResourceKit 的にも素直。
- 別ボリューム出力のために `copyItem` への明示フォールバックを残す
    - 却下: 実機 (APFS dmg + 別ボリューム) で検証した範囲では、
      `FileManager.moveItem` は別ボリューム間でもコピー相当で完了し、
      移動元を残さないことを確認済み。明示フォールバックは無用な分岐になる。
- 既存同名出力を残して名前にサ番号を付けた別ファイルで書き出す（重複回避）
    - 却下: 既存 Flutter 版からの上書き仕様を変える要件変更。

## 結果

- 同一ボリューム出力では large な画像でも出力段階が瞬時に終わる。
- 別ボリューム（外付け等）へは Foundation 準拠のコピー動作で確定する（移動元は残らない）。
- 既存の「同名入力上書き」「出力先フォルダ自動作成」の仕様は維持される。
- 単体テスト: `ConvertPipelineTests.installOutput`（上書き・移動・元ファイル消失）を追加。
- 実装箇所: `TreeImageOptimizer/TreeImageOptimizer/Services/ConvertOrchestrator.swift`
