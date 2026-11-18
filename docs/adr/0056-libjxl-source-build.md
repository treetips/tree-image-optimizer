# libjxl v0.13.0 をソースビルドして dylib ごと同梱する

## ステータス

- 承認済み (Accepted)

## 背景・課題

同梱している `cjxl` は libjxl v0.12.0 で、上流は v0.13.0 を公開している。v0.13.0 は依存の脆弱性修正を含むセキュリティリリースであり、追従する理由がある。

しかし v0.13.0 のリリースには macOS 用のビルド済みアセットが無い（linux と windows のみ）。Homebrew にも `libjxl` の formula が無く、`brew info libjxl` は "No available formula" を返す（2026-11-19 時点）。ADR 0017 のとおり配布先に Homebrew を前提にできないため、依存 dylib は `@loader_path` に固めて同梱する必要がある。

## 決定

- libjxl v0.13.0 をソースからビルドし、`cjxl` と依存 dylib を `tools/libjxl/bin/macos/` に同梱する。ADR 0017 の「dylib をバンドルして `@loader_path` で解決する」方針は維持する。
- `BUILD_SHARED_LIBS=ON` でビルドし、Homebrew の依存へ動的リンクしたうえで、成果物側で依存を固める。
- `JPEGXL_ENABLE_SKCMS=OFF` にして lcms2 を使う。skcms はソース tarball に含まれず `deps.sh` での取得が必要になる。Homebrew の lcms2 で足りるため、外部取得を増やさない。
- `JPEGXL_FORCE_SYSTEM_HWY=ON` と `JPEGXL_FORCE_SYSTEM_BROTLI=ON` を指定し、Homebrew の highway と brotli を使う。
- 依存 dylib は再帰的に集め、`install_name_tool -change` で参照を、`-id` で自身の識別子を `@loader_path/<basename>` に書き換える。ビルドディレクトリを指す `LC_RPATH` は削除し、`codesign --force --sign -` で ad-hoc 署名する。

### ビルド手順

```shell
curl -fsSL "https://github.com/libjxl/libjxl/archive/refs/tags/v0.13.0.tar.gz" | tar xz
cmake -S libjxl-0.13.0 -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/opt/homebrew \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_TESTING=OFF \
  -DJPEGXL_ENABLE_MANPAGES=OFF \
  -DJPEGXL_ENABLE_BENCHMARK=OFF \
  -DJPEGXL_ENABLE_EXAMPLES=OFF \
  -DJPEGXL_ENABLE_SJPEG=OFF \
  -DJPEGXL_ENABLE_VIEWERS=OFF \
  -DJPEGXL_ENABLE_JNI=OFF \
  -DJPEGXL_ENABLE_SKCMS=OFF \
  -DJPEGXL_FORCE_SYSTEM_HWY=ON \
  -DJPEGXL_FORCE_SYSTEM_BROTLI=ON
cmake --build build --target cjxl -j 8
```

`cjxl` を起点に `otool -L` を再帰的にたどり、システムライブラリ（`/usr/lib`、`/System`）以外を `tools/libjxl/bin/macos/` へコピーする。コピー先のファイル名は元の basename とし、参照と `-id` を `@loader_path/<basename>` にそろえる。

### 検証

- `cjxl --version` が `v0.13.0` を表示する。
- `otool -L` の全ファイルに `/opt/homebrew` とビルドディレクトリが残らない。
- `env -i` の最小環境でもエンコードできる（Homebrew 非導入の配布先を模す）。
- アプリと同じ引数（`--distance`、`-e`、`--num_threads`）でエンコードでき、出力サイズと寸法が妥当である。

## 代替案

- Homebrew の `cjxl` をそのまま同梱する: formula が存在せず、将来復活しても Homebrew 前提のパス解決を配布物へ持ち込むことになる。
- 静的リンクにする: Homebrew の依存には静的版が無いものがあり、ビルド構成が複雑になる。ADR 0017 と同じ動的バンドルを維持する。
- `deps.sh` で skcms を取得する: ビルドのたびに外部リポジトリへの取得が増える。lcms2 で代替できるため見送る。

## 結果

- `tools/libjxl/bin/macos/` は `cjxl` と dylib 20 個の計 21 ファイル、約 8.3MB になった。
- v0.13.0 のセキュリティ修正を配布物へ取り込めた。`docs/design/feature/convert-flow/compression.md` の `cjxl --help` も 0.13.0 の出力へ更新した。
- 上流が将来 macOS アセットを公開した場合は、取得元を切り替えられる。その時点で本 ADR を見直す。
