---
name: update-image-tools
description: tools/ に同梱するアップスケーラー（upscayl-bin, Real-CUGAN）と圧縮ライブラリ（jpegoptim, pngoptim, libjxl, libavif, libwebp）の更新有無を上流に問い合わせ、差分を示してユーザーの承認を得てから取得・差し替え・バージョン定数更新・検証まで行う。ツールの更新確認、最新版への追従、依存バイナリのバージョン更新を頼まれたときに使う。
whenToUse: アップスケーラーや圧縮ライブラリを最新版にしたい、tools/ の同梱バイナリを更新したい、ツールのバージョン差分を確認したいと言われたとき。
---

# update-image-tools

`tools/` 配下の外部バイナリは、アプリのコードとは別に上流が動く。このスキルは7ツールの現行版と上流の最新版を突き合わせ、**ユーザーが承認したものだけ**を差し替える。承認なしにバイナリを1つも置き換えない。

進め方は「現行版を集める → 最新版を調べる → 差分を提示して承認を取る → 取得して差し替える → 検証する → 報告する」の6段階。途中で失敗したら、置き換え前の状態へ戻してから報告する。

## 対象とバージョンの持ち場

同じバージョンが複数箇所に書かれている。更新時はこの表の「アプリ側」と「ツール側」を必ず両方そろえる。

| ツール | 分類 | 本体の場所 | アプリ側の定義 | ツール側 | 上流 |
|---|---|---|---|---|---|
| upscayl-bin | アップスケーラー | `tools/upscal/bin/upscayl-bin`（モデルは `tools/upscal/models/`） | `Core/AppInfo.swift` の `upscalBinVersion` | `tools/upscal/.version` | `upscayl/upscayl-ncnn` |
| Real-CUGAN | アップスケーラー | `tools/realcugan/bin/macos/realcugan-ncnn-vulkan` | `AppInfo.realcuganVersion`、`ToolInstaller.realcuganVersion`、`ToolInstaller.realcuganFullVersion` | `tools/realcugan/.version` | `nihui/realcugan-ncnn-vulkan` |
| jpegoptim | 圧縮（JPEG） | `tools/jpegoptim/bin/macos/jpegoptim` | `AppInfo.jpegVersion` | なし | `tjko/jpegoptim` |
| pngoptim | 圧縮（PNG） | `tools/pngoptim/bin/macos/pngoptim` | `AppInfo.pngVersion` | なし | `okooo5km/pngoptim` |
| libjxl（cjxl） | 圧縮（JPEG XL） | `tools/libjxl/bin/macos/cjxl` と同ディレクトリの dylib | `AppInfo.jpegXlVersion` | `tools/libjxl/.version` | `libjxl/libjxl` |
| libavif（avifenc） | 圧縮（AV1） | `tools/libavif/bin/macos/avifenc` | `AppInfo.av1Version` | `tools/libavif/.version` | `AOMediaCodec/libavif` |
| libwebp（cwebp） | 圧縮（WebP） | `tools/libwebp/bin/macos/cwebp` | `AppInfo.webpVersion` と `ToolInstaller.webpVersion` | なし（`.version` を作らない） | `webmproject/libwebp` |

`ToolInstaller` の定数はアプリ内ダウンロードのURLを組み立てる。片方だけ直すと取得先が壊れるので、`webpVersion` は2箇所、Real-CUGAN は3箇所を同時に更新する。

2026-11-19 に更新を適用した時点の現行版と最新版は次のとおり。実行時は必ず再確認し、この表は目安として扱う。

| ツール | 現行版 | 最新版 | 更新 |
|---|---|---|---|
| upscayl-bin | `upscayl-bin-20251207-174704` | 同じ | なし |
| Real-CUGAN | `realcugan-ncnn-vulkan-20220728` | 同じ | なし |
| jpegoptim | `v1.5.6` | `v1.5.6` | なし |
| pngoptim | `v0.6.3` | `v0.6.3` | なし |
| libjxl | `v0.13.0` | `v0.13.0` | なし（macOSアセット無し） |
| libavif | `v1.4.2` | `v1.4.2` | なし |
| libwebp | `1.6.0` | `1.6.0` | なし |

## 1. 現行版を集める

`AppInfo.swift` と `.version`、実バイナリの3系統を読み、食い違っていればそれ自体を報告する。表示用の定数だけが古いまま、という事故が起きやすい。

```sh
sed -n '1,20p' TreeImageOptimizer/TreeImageOptimizer/Core/AppInfo.swift
for f in tools/*/.version; do printf '%s: %s\n' "$f" "$(cat "$f")"; done
tools/jpegoptim/bin/macos/jpegoptim --version | head -1
tools/pngoptim/bin/macos/pngoptim --version
tools/libjxl/bin/macos/cjxl --version | head -1
tools/libavif/bin/macos/avifenc --version | head -1
tools/libwebp/bin/macos/cwebp -version
```

`upscayl-bin` と `realcugan-ncnn-vulkan` はバージョン表示を持たない。`.version` と `AppInfo` を正とする。

## 2. 上流の最新版を調べる

GitHub Releases は `releases/latest` を使う。未認証だと1時間60回までなので、7ツールの確認は余裕で収まる。`GITHUB_TOKEN` があれば付けるが、値は画面に出さない。

```sh
gh_latest() {
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL "${auth[@]}" "https://api.github.com/repos/$1/releases/latest"
}

for repo in upscayl/upscayl-ncnn nihui/realcugan-ncnn-vulkan tjko/jpegoptim \
            okooo5km/pngoptim libjxl/libjxl AOMediaCodec/libavif; do
  printf '\n== %s\n' "$repo"
  gh_latest "$repo" | jq -r '.tag_name, .name, (.assets[] | .name)'
done
```

`.message` が返ったらレート制限かリポジトリ名の誤りを疑う。シェル関数は同じシェルでしか使えないので、ブロックを分けて実行する環境では都度定義するか `curl` を直接書く。`libwebp` は GitHub Releases を出していないため、Google Storage の配布一覧を使う。

```sh
curl -fsSL "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/index.html" \
  | grep -oE 'libwebp-[0-9]+\.[0-9]+\.[0-9]+-mac-arm64\.tar\.gz' | sort -uV | tail -1
```

取得先のアセットが存在するかは、ダウンロード前に `curl -fsSIL -o /dev/null -w '%{http_code}\n' <URL>` で確かめる。GitHub のリリース資産は `objects.githubusercontent.com` へリダイレクトされるため、`-L` を付けないと `302` が返る。

## 3. 差分を提示して承認を取る

ツールごとに「分類 / 現行版 / 最新版 / macOS用の取得物 / 自動で差し替えられるか」を1行で出し、更新するものを番号で選ばせる。対話ツール（`ask_user_question` など）が使えるならそれを使い、無ければチャットで番号付きの選択肢を出す。

- 「更新して」とだけ言われた場合も、この一覧を出して対象を確定してから着手する。全件か一部かで作業量が大きく変わる。
- `libjxl` と `libavif` は自前ビルドが要る。取得とビルドは別枠の承認とし、既定では**手順を提示して止める**。
- 承認が得られなかったツールは、確認結果だけを報告して触らない。

## 4. 取得して差し替える

作業用とバックアップ用のディレクトリはリポジトリの外に作る。

```sh
tmp=$(mktemp -d)
backup=$(mktemp -d)
cp -a tools/<tool> "$backup/"
```

### アセットと配置

| ツール | macOS用アセット | 取り出すもの | 置き場所 |
|---|---|---|---|
| upscayl-bin | `upscayl-bin-<tag>-macos.zip`（ZIP内は `upscayl-bin-<tag>-macos/`） | `upscayl-bin`、`LICENSE`、`README.md` | バイナリは `tools/upscal/bin/`、文書は `tools/upscal/` |
| Real-CUGAN | `realcugan-ncnn-vulkan-<tag>-macos.zip`（ZIP内は `realcugan-ncnn-vulkan-<tag>-macos/`） | バイナリ、`models-se` / `models-pro` / `models-nose`、`LICENSE` | バイナリは `tools/realcugan/bin/macos/`、モデルと `LICENSE` は `tools/realcugan/` 直下 |
| jpegoptim | `jpegoptim-<ver>-x64-osx.zip`（ZIP直下に `jpegoptim`、`LICENSE`、`COPYRIGHT`、`README`） | `jpegoptim` | `tools/jpegoptim/bin/macos/` |
| pngoptim | `pngoptim_<ver>_darwin_universal.tar.gz`（`.sha256` を併用、tar直下は `pngoptim` のみ） | `pngoptim` | `tools/pngoptim/bin/macos/` |
| libwebp | `libwebp-<ver>-mac-arm64.tar.gz`（Google Storage） | `bin/cwebp` のみ | `tools/libwebp/bin/macos/` |
| libjxl | macOS用アセットが無い | — | 5章のビルド手順 |
| libavif | `macOS-artifacts.zip` は SVT-AV1 非同梱で使えない | — | 5章のビルド手順 |

`LICENSE` を同梱しているツール（upscal / realcugan / libjxl / libavif）は、バイナリと一緒に差し替える。同梱していないツール（jpegoptim / pngoptim / libwebp）は、アーカイブに `LICENSE` が入っていても勝手に増やさず、追加するかをユーザーに確認する。

配置先の階層はツールで違う。upscal だけ `bin/` 直下、ほかは `bin/macos/` の下に置く。

| ツール | 配置先ディレクトリ |
|---|---|
| upscayl-bin | `tools/upscal/bin` |
| Real-CUGAN | `tools/realcugan/bin/macos`（モデルは `tools/realcugan/` 直下） |
| jpegoptim | `tools/jpegoptim/bin/macos` |
| pngoptim | `tools/pngoptim/bin/macos` |
| libwebp | `tools/libwebp/bin/macos` |
| libjxl | `tools/libjxl/bin/macos` |
| libavif | `tools/libavif/bin/macos` |

`<tag>` は `20251207-174704` のような日付形式、`<ver>` は `v` を除いた数字。`upscayl-bin` のモデル（`tools/upscal/models/`）は別リポジトリ `upscayl/custom-models` 由来なので、バイナリ更新では触らない。モデルを更新したいと言われたときは、`upscayl/custom-models` の zip と現在のファイル一覧を突き合わせ、差分（追加・削除された `.bin` / `.param`）を示してから承認を取る。

### 検証と配置の手順

ダウンロードしたら、置き換える前にチェックサムとアーキテクチャを確かめる。GitHub API の `digest` は `sha256:<hex>` 形式で返る。

```sh
asset=<asset-name>
expected=$(gh_latest <owner/repo> | jq -r --arg n "$asset" \
  '.assets[] | select(.name==$n) | .digest // ""' | sed 's/^sha256://')
shasum -a 256 "$tmp/$asset"
```

`digest` が空（Real-CUGAN の旧リリースなど）なら `.sha256` アセットを探す。どちらも無い場合は、チェックサム無しで進めてよいかをユーザーに確認する。

```sh
file "$tmp/<binary>"           # Mach-O であること
lipo -archs "$tmp/<binary>"    # ホストが arm64 なら arm64 を含むこと
```

置き換えは「元のファイルを全削除してから置く」。`docs/design/feature/initial-data.md` がこの運用を定めている。残骸が混ざると、古い dylib や古いモデルを読む事故になる。

```sh
dest=tools/pngoptim/bin/macos     # 上の表のディレクトリ。upscal は tools/upscal/bin
rm -rf "$dest"
mkdir -p "$dest"
cp "$tmp/pngoptim" "$dest/pngoptim"
chmod +x "$dest/pngoptim"
```

Real-CUGAN を差し替えるときは、`tools/realcugan` を丸ごと消さずに `bin/macos` と `models-*`、`LICENSE` を個別に入れ替える。`tools/realcugan/models-pro` のように現在同梱していないモデルを勝手に増やさない。

`tools/libjxl/bin/macos/` を消す場合は、dylib も含めて丸ごと入れ替える。新しい `cjxl` は `libjxl.0.13.dylib` のような新しい soname を要求するため、古い dylib を残しても動かない。

`.version` を持つツール（upscal / realcugan / libjxl / libavif）だけ、新しい値を書き込む。持たないツール（jpegoptim / pngoptim / libwebp）では新規作成しない。

## 5. ビルドが要る2つは、承認後に手順を示して止める

`libjxl` の macOS 版は上流が配布していない。現行の `cjxl` は Homebrew の dylib を `@loader_path` に固めたもので、依存の解決方法は ADR 0017 が定めている。`libavif` は公開アセットに SVT-AV1 が入らないため、ADR 0037 のとおり自前でビルドする。

### libjxl

```sh
brew upgrade libjxl        # もしくはソースからビルド
cp /opt/homebrew/opt/libjxl/bin/cjxl tools/libjxl/bin/macos/
# 依存 dylib を tools/libjxl/bin/macos/ へコピーしたうえで、
# install_name_tool -change /opt/homebrew/... @loader_path/<base> と -id を全 dylib に適用
codesign --force --sign - tools/libjxl/bin/macos/*
```

検証は3点。`otool -L tools/libjxl/bin/macos/cjxl | grep -c /opt/homebrew` が `0` であること、`cjxl --version` が新しい版を出すこと、下の実エンコードが通ること。dylib は `.gitattributes` の `tools/libjxl/bin/macos/*.dylib` で LFS 管理されるので、追加の登録は要らない。

### libavif

```sh
ver=1.4.2   # 新タグに置き換える
curl -fsSL "https://github.com/AOMediaCodec/libavif/archive/refs/tags/v${ver}.tar.gz" | tar xz
cmake -S "libavif-${ver}" -B build \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DAVIF_BUILD_APPS=ON -DAVIF_BUILD_EXAMPLES=OFF -DAVIF_BUILD_TESTS=OFF \
  -DAVIF_CODEC_AOM=LOCAL -DAVIF_CODEC_SVT=LOCAL -DAVIF_CODEC_DAV1D=OFF \
  -DAVIF_ZLIBPNG=LOCAL -DAVIF_JPEG=LOCAL -DAVIF_LIBYUV=LOCAL
cmake --build build --target avifenc -j 8
cp build/avifenc tools/libavif/bin/macos/avifenc
```

`avifenc --version` に `aom` と `svt` の両方が出ること、`-c aom` と `-c svt` の両方でエンコードできること、`otool -L` がシステムライブラリだけを指すこと（静的リンク）を確認する。

ビルドは10分以上かかるうえ失敗もしやすい。承認が無いまま着手しない。ビルド方式や入手元を変える場合は、`docs/adr/INDEX.md` を確認したうえで ADR を追加する。単なるバージョン更新なら ADR は要らない。ビルドで差し替えた場合も、`.version` と `AppInfo` の更新、6章の検証まで同じように行う。

## 6. 検証する

### バイナリ単体

`--version` が期待値を出すことを最初に確かめる。表記は上流とアプリで揺れる（`v0.6.3` と `0.6.3`）ので、`sed -E 's/^v//'` で正規化して比較する。

次に、アプリが実際に使う引数でサンプル画像を1枚処理する。`docs/images/app-batch-convert01.png` を入力に使えばよい。出力は使い捨てのディレクトリに置き、`jpegoptim` は入力と同じ場所へ書き戻さないよう、アプリと同じく別の出力先ディレクトリを渡す。

```sh
sample=docs/images/app-batch-convert01.png
out=$(mktemp -d)
mkdir -p "$out/jpeg"
sips -s format jpeg "$sample" --out "$out/sample.jpg" >/dev/null

tools/jpegoptim/bin/macos/jpegoptim -m80 -o -d "$out/jpeg" "$out/sample.jpg"
tools/pngoptim/bin/macos/pngoptim "$sample" -o "$out/out.png" --quality 80
tools/libjxl/bin/macos/cjxl "$sample" "$out/out.jxl" --distance=1.0 -e 7 --num_threads=4
tools/libavif/bin/macos/avifenc -c aom --speed 6 -q 60 -y 420 -j 4 "$sample" "$out/out.avif"
tools/libavif/bin/macos/avifenc -c svt --speed 6 -q 60 -y 420 -j 4 "$sample" "$out/out-svt.avif"
tools/libwebp/bin/macos/cwebp -preset photo -q 80 -m 6 -mt "$sample" -o "$out/out.webp"
```

アップスケーラーは出力の寸法まで見る。Real-CUGAN はモデル不在でも終了コード0で黒画像を返すことがあるため、寸法の確認を省かない。

```sh
tools/upscal/bin/upscayl-bin -i "$sample" -o "$out/up2x.png" -s 2 \
  -m tools/upscal/models -n realesr-animevideov3-x2
tools/realcugan/bin/macos/realcugan-ncnn-vulkan -i "$sample" -o "$out/cugan2x.png" \
  -s 2 -n 0 -m tools/realcugan/models-se
sips -g pixelWidth -g pixelHeight "$out/up2x.png" "$out/cugan2x.png"
```

### アプリ

バイナリと定数を直したら、AGENTS.md の順序どおり lint → フォーマット → ビルド → テストを回す。

```sh
swiftlint
swift format format -i -r TreeImageOptimizer
xcodebuild -project TreeImageOptimizer/TreeImageOptimizer.xcodeproj \
  -scheme TreeImageOptimizer -configuration Debug build
xcodebuild -project TreeImageOptimizer/TreeImageOptimizer.xcodeproj \
  -scheme TreeImageOptimizer -configuration Debug test
```

Markdown を直した場合は `rumdl fmt` のあと `rumdl check` を通す。CI が同じ検査をしている。

### 失敗したら戻す

検証が1つでも落ちたら、`$backup` から `cp -a` で戻し、`AppInfo` と `ToolInstaller` の変更も元へ戻す。中途半端に新しいバイナリだけ残すと、次回の起動で原因の分からない失敗になる。

## 更新後の報告に含めるもの

- ツールごとの 旧版 → 新版、および更新しなかったものとその理由
- 変更したファイルの一覧（バイナリ、`.version`、`AppInfo.swift`、`ToolInstaller.swift`、ドキュメント）
- 実行した検証と結果（`--version`、実エンコード、ビルド、テスト）
- 未対応として残したもの（ビルド承認待ちの libjxl / libavif など）

git の操作（ブランチ作成、commit、push）は、指示があるまで行わない。`.gitattributes` も勝手に変えない。

## 落とし穴

- **pngoptim は 0.6 系で CLI が変わりうる。** 現行コードは `pngoptim <input> -o <output> --quality <n>` の3引数だけを使う（`CompressionService.pngoptimArguments`）。0.6.3 では `-o` / `--quality` / `--speed` が残っていることを確認済み（2026-11-18）だが、実エンコードで必ず確かめる。通らない、または `--help` から `--quality` が消えていたら差し替えを止め、`CompressionService` とテストの変更案を提示する。勝手にコードを書き換えない。
- **jpegoptim のアセット名は当てにならない。** `jpegoptim-<ver>-x64-osx.zip` という名前だが、v1.5.6 の中身は arm64 だった（2026-11-18 に確認）。名前で判断せず `lipo -archs` で確認する。arm64 を含まない場合は Rosetta 実行になるので、ソース tarball（`jpegoptim-<ver>.tar.gz`）から `./configure && make` して arm64 をビルドする案を併せて出す。
- **libwebp は `.version` を持たない。** `AppInfo.webpVersion` と `ToolInstaller.webpVersion` の2箇所を同時に直す。`cwebp -version` の出力は `1.6.0` のように `v` 無し。
- **Real-CUGAN のモデルフォルダ名は変えない。** `models-se` / `models-pro` / `models-nose` はバイナリが前処理のパディング量の判定に使う。名前を変えると `unknown model dir type` で起動しない。
- **バージョン表記が混在している。** `AppInfo` は `v1.5.6`、`ToolInstaller` は `1.6.0`、`.version` は `upscayl-bin-20251207-174704`。比較は正規化してから、書き込みは既存の書式に合わせる。
- **GitHub API は未認証で1時間60回。** 429 が返ったら、時間を置くか `GITHUB_TOKEN` の利用をユーザーに確認する。トークンの値は出力しない。
- **アプリを起動して確認した場合は、必ず終了する。** 実機の変換確認はユーザーに委ねてよい。
