# Real-CUGANエンジン追加の実現性調査

## 結論

Real-CUGANは現行アーキテクチャに追加できる。`upscayl-bin` と同じく、外部バイナリを `Process` で実行する方式が最も現実的だ。Real-CUGAN公式のSwift SDKやCore MLモデルは存在せず、ネイティブ実装に切り替えるとモデル変換・タイル処理・検証を新規に作ることになる。v1は `realcugan-ncnn-vulkan` を同梱する案を推奨する。

macOS 27.2・Apple M4 Maxで実機検証した。753×594の画像を2倍にする処理は約0.4秒、4倍は約0.7秒で完了した。7プロセス並列でも全件成功し、日本語や空白を含むパス、アルファ付きPNGも扱えた。追加サイズはバイナリ24.5MBと `models-se` 28MBの合計約53MBである。

## 調査の前提

対象は `docs/design/feature/batch-convert.md` と `docs/design/feature/easy-convert.md` のアップスケール機能とする。どちらの仕様にもエンジンプルダウンとReal-CUGANの選択肢はすでに書かれているが、実装にはエンジンの概念自体がまだない。

現行実装は次の通り。

- `UpscaleService` は `paths.upscalBinURL` を固定で実行し、引数も `upscayl-bin` 専用になっている。
- `ConvertConfig` は `scale` と `model` だけを持ち、エンジンを区別しない。
- `AppPaths` は `upscal/bin/upscayl-bin` と `upscal/models` だけを解決する。
- `TargetFiles.listModels` は `upscal/models` の `.bin` を列挙する。
- 設定JSON（`BatchSettings` / `EasyConvertSettings`）にエンジンの項目がない。
- 一括変換画面とかんたん変換画面のどちらにもエンジンプルダウンがない。

検証環境は次の通り。

| 項目 | 内容 |
|---|---|
| OS | macOS 27.2（Build 26B123） |
| CPU/GPU | Apple M4 Max |
| 検証バイナリ | `nihui/realcugan-ncnn-vulkan` 20220728 |
| 検証モデル | 同リリースの `models-se` / `models-pro` / `models-nose` |

## Real-CUGANの配布形態

Real-CUGAN本体（bilibili/ailab）はPyTorchのモデルと推論コードであり、macOS向けのアプリやSDKではない。実用的な配布物は、nihui氏がncnnへ移植した `realcugan-ncnn-vulkan` である。

このバイナリはMITライセンスで、x86_64とarm64のユニバーサルバイナリとして配布されている。MoltenVKを静的リンクしており、Homebrewや外部dylibを必要としない。`otool -L` で確認できる依存はシステムフレームワークと `libc++` だけだった。最小OSはmacOS 11.0で、macOS 27.2上でも動作した。

### 実行コマンド

```shell
realcugan-ncnn-vulkan \
  -i "${INPUT}" \
  -o "${OUTPUT}" \
  -s "${SCALE}" \
  -n "${NOISE_LEVEL}" \
  -m "${MODELS_DIR}"
```

`-s` は2〜4を指定する。`-m` にはモデルフォルダを渡す。`-n` の値とモデルファイルの対応は分かりにくく、次のようになっている。

| `-n` | 選ばれるモデルファイル |
|---|---|
| `-1` | `up{scale}x-conservative` |
| `0` | `up{scale}x-no-denoise` |
| `1` | `up{scale}x-denoise1x` |
| `2` | `up{scale}x-denoise2x` |
| `3` | `up{scale}x-denoise3x` |

`-1` が「ノイズ除去なし」ではなく「conservative」、`0` が「no-denoise」である点に注意する。UIでは `-n` の数値をそのまま見せず、モデルファイル名か利用者向けのラベルに変換したほうがよい。

公式の説明（bilibili/ailab Real-CUGAN の Changelog_CN）では、保守版・非降噪版は「ノイズ除去を行わない」（そのうえで不自然なノイズ＝アーティファクトだけを最低限抑える）とされており、実際にノイズを除去するのは denoise1x〜3x である。つまりノイズ除去の強さは `no-denoise < conservative < denoise1x < denoise2x < denoise3x` となり、`-n` の数値（-1、0、1〜3）の大小とは一致しない。nihui版READMEも「-1 = no effect（除去効果なし）、値が大きいほど強い除去」と説明し、既定値を -1（conservative）にしている。

### モデルの組み合わせ

モデルはフォルダとファイル名の両方で意味が決まる。

| フォルダ | 2x | 3x | 4x |
|---|---|---|---|
| `models-se` | conservative, no-denoise, denoise1x, denoise2x, denoise3x | conservative, no-denoise, denoise3x | conservative, no-denoise, denoise3x |
| `models-pro` | conservative, no-denoise, denoise3x | conservative, no-denoise, denoise3x | なし |
| `models-nose` | no-denoise | なし | なし |

`models-se` だけで11モデル、`models-pro` が6モデル、`models-nose` が1モデルの合計18モデルになる。1xモデルは含まれていない。Real-CUGANのREADMEにも、1xモデルはトレーニング中と書かれている。

バイナリは `-m` のパスに `models-se`、`models-pro`、`models-nose` の文字列が含まれるかで前処理のパディング量を変えている。フォルダ名を `se` や `models` に変えると `unknown model dir type` で起動しない。配置時は元のフォルダ名を保つ必要がある。

### 実機で確認したこと

| 確認項目 | 結果 |
|---|---|
| アーキテクチャ | x86_64 / arm64のユニバーサルバイナリ |
| 外部dylib | なし（システムフレームワークのみ） |
| 2倍変換（753×594 → 1506×1188） | 約0.4秒 |
| 4倍変換（753×594 → 3012×2376） | 約0.7秒 |
| 2倍変換（1533×755 → 3066×1510） | 約0.5秒 |
| 7プロセス並列（2倍） | 全件成功、合計約2.1秒 |
| 最大RSS | 1プロセスあたり約150MB |
| 日本語・空白入りパス | 入出力とも成功 |
| アルファ付きPNG | アルファを保持 |
| ライセンス | MIT（nihui）、Real-CUGAN本体もMIT（bilibili） |

処理時間はモデルやGPUキャッシュの状態で変わるため、目安として扱う。

### 実装上の落とし穴

モデルファイルが欠けていても、バイナリが終了コード0で黒画像を出力する組み合わせがあった。`models-nose` に存在しない3xモデルを指定したところ、エラーにならず真っ黒なPNGが生成された。Real-CUGANを追加するときは、実行前に対象の `.param` と `.bin` の存在を確認し、実行後に出力ファイルの存在・サイズ・寸法を検証する必要がある。

`-s 1` も実質的に使えない。1xモデルが存在しないため、拡大されない画像が出力されるか、モデル不在で失敗する。UIではReal-CUGAN選択時の拡大率を2〜4に制限するのがよい。

## 実装方式の比較

| 方式 | 実装コスト | 配布サイズ | 品質・速度 | 判断 |
|---|---|---|---|---|
| ncnnバイナリ（`realcugan-ncnn-vulkan`） | 小 | 約53MB（`models-se`のみ） | 実機で確認済み。既存の `upscayl-bin` と同じ実行方式 | 推奨 |
| Core MLへ変換 | 大 | モデル次第で約50〜100MB | ANE/GPUを使える可能性はあるが、変換とタイル処理の検証が必要 | v1では見送り |
| ncnnをXCFrameworkとしてリンク | 中〜大 | バイナリ相当 | CLIと同じ推論を自前で呼ぶ必要がある | 利点が少ない |
| ONNX Runtime / MLX | 大 | 100MB超の依存になり得る | 公式のReal-CUGANモデルがない | 見送り |

Core MLは「Swift SDKに近い形」ではあるが、Real-CUGANの公式Core MLモデルはない。PyTorchの重みから変換する場合、2x/3x/4xとノイズ除去レベルの組み合わせごとにモデルを作り、入力サイズの可変化かタイル分割を自前で設計することになる。変換ツール（Python、PyTorch、coremltools）をCIに持ち込む必要もあり、v1の範囲を超える。

ncnnをライブラリとしてリンクする案も、結局は `realcugan.cpp` 相当の前処理・タイル処理・同期処理をSwift/C++で再実装することになる。既存のCLIをそのまま使うほうが変更量も検証コストも小さい。

## 推奨する実装設計

### エンジンの抽象化

`UpscaleEngine` を追加し、`ConvertConfig` に持たせる。

```swift
enum UpscaleEngine: String, CaseIterable, Identifiable, Sendable {
    case upscayl
    case realCUGAN
}
```

`UpscaleService` はエンジンごとに引数を組み立て、実行先を切り替える。`upscayl-bin` の既存引数はそのまま残し、Real-CUGAN用に次のような引数生成を追加する。

```swift
static func realCuganArguments(
    input: String, output: String, scale: Int, noise: Int, modelsDir: String
) -> [String] {
    ["-i", input, "-o", output, "-s", "\(scale)", "-n", "\(noise)", "-m", modelsDir]
}
```

Real-CUGANのモデルIDは `models-se/up2x-conservative` のようにフォルダ名とファイル名を結合した文字列にする。設定JSONにはこのIDを保存し、実行時にフォルダ・スケール・ノイズレベルへ分解する。`scale` はモデルから導出できるため、UIの拡大率とモデルが食い違わないように検証する。

### モデルカタログ

Real-CUGANのモデルは「フォルダ・拡大率・ノイズ除去レベル」の組み合わせで決まる。モデル一覧を固定配列で持つのではなく、`.param` と `.bin` のペアを走査して作る。ファイルが片方だけの場合は一覧から除外する。これにより、`models-se` だけを同梱しても、後から `models-pro` を追加しても同じコードで動く。

表示名は既存のアップスケールモデルと揃えて、元のファイル名を基本にする。たとえば `SE / up2x-conservative`、`Pro / up3x-no-denoise` のようにフォルダの役割を添える。`conservative` を「弱いノイズ除去」と訳すと、実際の `-n` の意味とずれるため、無理に日本語化しないほうが安全だ。

### UI

アップスケールカードの先頭にエンジンプルダウンを追加する。既存の拡大率スライダーとモデルプルダウンは残し、エンジンによって選択肢を切り替える。

- `upscayl-bin`：拡大率1〜4、モデルは `upscal/models` の `.bin` 一覧。
- `Real-CUGAN`：拡大率2〜4、モデルは選択中の拡大率に合うものだけを表示する。

Real-CUGANで拡大率を変えたとき、現在のモデルが新しい拡大率に存在しなければ、conservative（無ければ先頭）のモデルへ自動で切り替える。フォールバックを conservative にするのは、ncnn版バイナリの既定値（-n -1）でもあり、初回選択の既定として扱いやすいため。

モデル一覧はノイズ除去が弱い順（no-denoise → conservative → denoise1x → denoise2x → denoise3x）に並べる。ファイル名の辞書順では `no-denoise` が末尾に落ち、`-n` の値順では conservative（-1）が先頭に来て強弱と対応しないため、専用の順位（`denoiseRank`：no-denoise=0、conservative=1、denoiseNx=N+1）で並べ替える。

並び順の根拠は同梱バイナリ（`models-se`）での実測でも確認した。平滑グラデーションにホワイトノイズ（±30）を加えた256×256画像を2倍化し、出力に残る高域成分（5×5平均との差分の絶対値の平均）を測定したところ、ノイズ無し基準0.24に対し denoise2x=0.25、denoise3x=0.26 と基準まで除去したのに対し、no-denoise=3.65、conservative=4.32、denoise1x=4.07 はノイズを半分程度透過させた（入力画像は8.08）。no-denoise・conservative が実質的なノイズ除去を行わない公式の説明と整合する。なお、この3つの間の残存値の大小はノイズの増幅傾向の違いを含み、除去強度の順位として解釈しない。

保存済みモデルIDを復元するときは、選択中の拡大率に合うモデルだけを候補として照合する。拡大率が合わない保存IDをそのまま採ると、プルダウンに対応する選択肢がなくなり（選択表示が空になる）、拡大率とモデルの不一致で実行も失敗するためである。ツール未配置でモデル一覧が空の間は、保存IDを既定値へ書き換えない。起動時ダウンロードの完了後にユーザーの選択が失われるのを防ぐ。エンジンを切り替えたときは、エンジンごとに前回のモデルを復元する。片方のエンジンの選択がもう片方に引きずられないようにする。

Real-CUGANのバイナリやモデルが未配置の場合は、エンジンを選択できないようにするか、選択後に「Real-CUGANのツールが配置されていません」と表示して実行ボタンを無効にする。起動時のツールチェックをブロックしないため、後者のほうが既存ユーザーへの影響が小さい。

### 設定

`BatchSettings` と `EasyConvertSettings` に次の項目を追加する。

- `engine`：`upscayl` または `realCUGAN`。既定値は `upscayl`。
- `realCuganModel`：Real-CUGANのモデルID。既定値は `models-se/up2x-conservative`。

既存の `model` は `upscayl` 用として残す。既存の設定JSONにキーがない場合は既定値で補完する。不正なエンジン名や存在しないモデルIDは、読み込み時に既定値へ戻す。

### ツール配置とインストーラ

配置先は次のようにする。

```text
tools/realcugan/
├── bin/macos/realcugan-ncnn-vulkan
├── models-se/
│   ├── up2x-conservative.param
│   ├── up2x-conservative.bin
│   └── ...
├── LICENSE
└── .version
```

`models-se` のフォルダ名は変えない。`LICENSE` にはnihui版のMITライセンスを置き、Real-CUGAN本体とncnn/MoltenVKのライセンス表記も別ファイルで同梱する。`.version` には `realcugan-ncnn-vulkan-20220728` を書く。

`ToolInstaller` の `requiredRelativePaths` には追加しない。ここへ追加すると、Real-CUGANをまだ配置していない既存ユーザーが起動時に「ツール不足」と判定され、アプリが使えなくなる。Real-CUGANは任意ツールとして扱い、`isRealCuganInstalled()` のような個別の判定を追加する。開発用の `tools/realcugan` があれば `copyFromDevTools` で補完し、失敗しても起動は継続する。

`.gitattributes` にはバイナリとモデルをGit LFSの対象として追加する。

### 安全策

Real-CUGANの実行前に対象モデルの `.param` と `.bin` が存在することを確認する。実行後は出力ファイルが存在し、サイズが0より大きく、寸法が入力の `scale` 倍になっていることを確認する。寸法の検証には `CGImageSource` を使える。これで、モデル不在時に黒画像を成功扱いする事故を防げる。

並列数は既存の設定をそのまま使える。M4 Maxでは7プロセス並列でも問題なかったが、モデルとMoltenVKの初期化で1プロセスあたり約150MBを使う。コア数の多いMacや大きな画像ではGPUメモリを圧迫する可能性があるため、Real-CUGANだけ並列数の上限を設けるか、`-t` でタイルサイズを指定する余地を残す。v1では実測して問題が出た場合に上限を決める。

### テスト

単体テストでは、Real-CUGANの引数生成、モデルIDの分解、`.param`/`.bin` のペア走査、拡大率による絞り込み、設定の既定値と不正値補正、`AppPaths` の新しいパス、`ToolInstaller` の任意ツール判定を追加する。

実ツールを使う結合テストは、バイナリが存在する場合だけ実行する。小さなPNGを2倍に変換し、出力の寸法とアルファの有無を確認する。CIにはツールがないため、テストはスキップできる形にする。

## 変更対象ファイル

| ファイル | 変更内容 |
|---|---|
| `Core/Models.swift` | `UpscaleEngine`、Real-CUGANモデル型を追加 |
| `Services/UpscaleService.swift` | エンジン別の引数生成と実行分岐 |
| `Services/ConvertOrchestrator.swift` | `ConvertConfig.engine` を `UpscaleService` へ渡す |
| `Services/AppPaths.swift` | Real-CUGANのバイナリ・モデルパスを追加 |
| `Services/ToolInstaller.swift` | 任意ツールとしての配置・判定・実行権限 |
| `Services/SettingsStore.swift` | `engine` と `realCuganModel` の保存・補正 |
| `Core/AppInfo.swift` | Real-CUGANのバージョン表示 |
| `Features/Convert/ConvertViewModel.swift` | エンジン状態、モデル一覧の切り替え |
| `Features/Convert/ConvertView.swift` | エンジンプルダウン、拡大率の制限 |
| `Features/EasyConvert/EasyConvertViewModel.swift` | 同上 |
| `Features/EasyConvert/EasyConvertView.swift` | 同上 |
| `Resources/Localizable.xcstrings` | エンジン名・ヘルプ・エラー文言 |
| `docs/design/feature/initial-data.md` | Real-CUGANの配置手順 |
| `docs/design/feature/batch-convert.md` | `upscal-bin` の表記修正、Real-CUGANの制約 |
| `docs/design/feature/easy-convert.md` | 同上 |
| `.gitattributes` | Real-CUGANのLFS登録 |

## リスクと未決事項

上流の `realcugan-ncnn-vulkan` は2022年7月のリリース以降、更新されていない。アルゴリズムとモデルは安定しているが、将来のmacOSでMoltenVKの互換性が壊れる可能性は残る。その場合はCore ML版を別エンジンとして追加できるよう、エンジンの抽象化は最初から入れておく。

同梱するモデルを `models-se` だけにするか、`models-pro` と `models-nose` も含めるかは決めていない。`models-se` だけで2x/3x/4xの主要な選択肢をカバーでき、追加サイズは約53MBに収まる。全モデルを入れると約70MBになる。v1は `models-se` のみを推奨する。

Real-CUGANのモデル一覧を「拡大率で絞り込む」か「モデルを選ぶと拡大率が決まる」かも決めていない。既存の拡大率スライダーを活かせる前者を推奨する。

Real-CUGANを起動時の必須ツールにするか、任意ツールにするかは、配布方法に依存する。現状は単一のツールZIP配布が未実装なので、任意ツールとして扱い、未配置でも既存機能が動く形が安全だ。

## 次のアクション

方針を承認できたら、エンジンの抽象化、モデルカタログ、UI、設定、ツール配置、テストの順に実装する。最初のPRでは `models-se` のみを同梱し、Real-CUGAN未配置でも既存の `upscayl-bin` が動くことを確認する。モデルの追加や並列数の上限は、実機で大きな画像を処理した結果を見てから決める。
