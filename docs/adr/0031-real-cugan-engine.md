# Real-CUGANをncnnバイナリで追加する

## ステータス

- 承認済み (Accepted)

## 背景・課題

アップスケーラーは `upscayl-bin` の1エンジンだけを前提に実装されている。`UpscaleService` はバイナリパスと引数を固定で持ち、`ConvertConfig` と設定JSONにエンジンの概念がない。一方、画面仕様にはエンジンプルダウンとReal-CUGANの選択肢がすでに書かれている。

Real-CUGAN本体はPyTorchのモデルであり、公式のSwift SDKやCore MLモデルはない。macOSで実用的に使える配布物は、ncnnへ移植された `realcugan-ncnn-vulkan` である。MITライセンスのユニバーサルバイナリで、MoltenVKを静的リンクしており、外部dylibを必要としない。macOS 27.2・Apple M4 Maxで2x/3x/4xの変換、7並列、日本語・空白入りパス、アルファ付きPNGを確認済みである。

## 決定

- アップスケーラーを `UpscaleEngine`（`upscayl` / `realCUGAN`）で抽象化し、`ConvertConfig` と設定JSONにエンジンを持たせる。
- Real-CUGANは `realcugan-ncnn-vulkan` 20220728を `tools/realcugan/` に同梱し、`Process` で実行する。Core MLへの変換やncnnのライブラリリンクはv1では行わない。
- 同梱するモデルは `models-se` を基本とする。フォルダ名はバイナリが前処理量の判定に使うため変更しない。
- Real-CUGANのモデルは「フォルダ・拡大率・ノイズ除去レベル」の組み合わせとして扱い、`.param` と `.bin` のペアを走査して一覧を作る。UIでは選択中の拡大率に合うモデルだけを表示する。
- モデルプルダウンの並び順はノイズ除去が弱い順（no-denoise → conservative → denoise1x〜3x）にする。`-n` の値（-1=conservative、0=no-denoise）やファイル名の辞書順では強弱と対応しないため、専用の順位（`denoiseRank`）で並べる。公式説明・同梱バイナリの実測とも、no-denoise と conservative が実質的なノイズ除去を行わないことと整合する。拡大率を変えると保存選択が新しい拡大率に合わない場合、conservative（無ければ先頭）へ切り替える。ツール未配置で一覧が空の間は、保存された選択を既定値で上書きしない。
- Real-CUGAN選択時の拡大率は2〜4に制限する。1xモデルは存在しない。
- Real-CUGANは必須ツールとして扱う。`ToolInstaller.requiredRelativePaths` に追加し、起動時のブートストラップで欠損を検出したら修復する。修復は開発用toolsのコピーを優先し、無ければGitHub Releases（`realcugan-ncnn-vulkan-20220728-macos.zip`）からダウンロードして `unzip` 展開し、フォルダごと `tools/realcugan` に配置する。手動配置はユーザーにとって難易度が高いため必須化する。配布はlibwebpと同じ「開発用toolsコピーを優先し、無ければGitHub Releasesからダウンロード」の経路で、新基盤の実装は不要である。UIの未配置注意文言はダウンロード失敗・中途半端な配置への安全網として保持する。
- 必須化した理由: 手動配置はユーザーにとって難易度が高いため。UIの未配置注意文言は、ダウンロード失敗や中途半端な配置への安全網として保持する。
- 実行前に対象モデルの `.param` と `.bin` の存在を確認し、実行後に出力ファイルの寸法を検証する。モデル不在時に終了コード0で黒画像を出力する挙動を成功扱いにしないためである。
- Real-CUGANのバイナリ・モデル・ライセンスはリポジトリにも開発用コピーとしてGit LFSで管理する。配布時の一次取得は起動時ダウンロードが担う。

## 代替案

- Core MLへ変換してSwiftから直接推論する
  - 却下: 公式モデルがなく、2x/3x/4xとノイズ除去レベルの組み合わせごとに変換・検証が必要になる。タイル処理も自前で実装することになり、v1の範囲を超える。
- ncnnをXCFrameworkとしてリンクする
  - 却下: CLIと同じ推論を呼ぶために前処理・タイル処理・同期処理を再実装する必要があり、既存バイナリを使うより変更量が大きい。
- ONNX RuntimeやMLXを使う
  - 却下: 公式のReal-CUGANモデルがなく、依存サイズも大きい。
- 既存の `upscayl-bin` でReal-CUGANモデルを読む
  - 却下: ネットワーク構造が異なり、モデルをロードできない。
- Real-CUGANをリポジトリ同梱のみとし、起動時ダウンロードを行わない
  - 却下: 手動配置はユーザーにとって難易度が高すぎる。

## 結果

- エンジンを切り替えられるようになり、Real-CUGANの2x/3x/4xとノイズ除去の強さを選べる。
- 追加サイズはバイナリ24.5MBと `models-se` 28MBの合計約53MBになる。全モデルを同梱する場合は約70MBになる。
- 初回起動時にReal-CUGANをダウンロードする（未配置の場合）。ダウンロードに失敗した場合は既存のブートストラップ再試行UIで案内する。
- 上流の `realcugan-ncnn-vulkan` は2022年7月のリリース以降更新されていない。将来のmacOSでMoltenVKの互換性が問題になった場合は、エンジン抽象化を活かしてCore ML版を追加する。
- 実装箇所: `Services/UpscaleService.swift`、`Services/AppPaths.swift`、`Services/ToolInstaller.swift`、`Services/SettingsStore.swift`、`Features/Convert/`、`Features/EasyConvert/`
- 調査の詳細: `docs/design/feature/upscale-engine.md`
