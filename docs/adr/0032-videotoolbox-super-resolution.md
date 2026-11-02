# VideoToolbox Super Resolutionを速度重視エンジンとして追加する

## ステータス

- 棄却 (Rejected)

## 背景・課題

アップスケール機能の3エンジン目として、速度重視エンジンの候補としてmacOS標準の `Apple VideoToolbox Super Resolution`（`VTSuperResolutionScalerConfiguration`）を調査した。

`VTFrameProcessor` APIの一部で、Apple Silicon向けに最適化されたMLベースの超解像処理である。対応環境は macOS 26.0+（本アプリのデプロイメントターゲットと一致）。

モデルの概念について、ユーザーが選択するモデル一覧は存在しない。処理に必要なMLモデルはシステム側がダウンロードして使い、`configurationModelStatus` で有無を確認し、未ダウンロードなら `downloadConfigurationModel(withCompletionHandler:)` で取得する仕組みである。CLIバイナリの同梱が不要で、速度重視エンジンとして相性は良好に見えた。

## 決定

- VideoToolbox Super Resolutionの採用を見送る。

## 代替案

- 入力サイズ上限の超過画像をタイル分割して処理する
    - 却下: 継ぎ目が画質を毀損し、「速度重視エンジン」としての実用性に乏しい。
- upscaylの軽量モデルやReal-CUGANの軽量設定を速度寄りプリセットとして公開する
    - 未検討（今回の対象外）。

## 結果

- `VTSuperResolutionScalerConfiguration`（Image型）の入力上限は **1920 x 1920** である。本アプリの想定入力は4K以上がベースであり、ほぼ全画像が対象外になる。
- 対応拡大率は実行時確認（`supportedScaleFactors`）で固定値ではない点、モデルダウンロード確認フローが新たに必要になる点もあったが、入力サイズ上限により採用不可と判断した。
- 3エンジン目の速度重視エンジンは、上記「代替案」の未検討案を含め別途検討する。
