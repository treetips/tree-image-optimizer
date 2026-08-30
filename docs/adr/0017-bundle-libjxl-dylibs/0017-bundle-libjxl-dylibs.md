# libjxl(cjxl) の依存 dylib バンドルと実行時ツールのバージョン不整合検知

## ステータス

- 承認済み (Accepted)

## 背景・課題

macOS 版の JPEG XL エンコーダ `cjxl`（libjxl v0.12.0）は、ビルド元の
Homebrew の動的ライブラリ（`/opt/homebrew/opt/...` 配下の
`libjxl`/`libjxl_cms`/`libjxl_threads`/`libgif`/`libjpeg`/`libpng`/
`openexr`/`imath`/`brotli`/`lcms2`/`openjph`/`hwy`/`deflate` 等）に
`@rpath` および絶対パスでリンクされている。
配布先の環境（Homebrew 未導入、あるいはバージョン・パスが異なる）では
`dyld` が `libjxl_threads.0.12.dylib` 等をロードできず、
`Library not loaded: @rpath/libjxl_threads.0.12.dylib` で異常終了していた。

また、実行時に `tools-vX.zip` をダウンロードする設計上、アプリのバージョンに
対応する ZIP を取得する。壊れた `cjxl` がすでにインストール済みの場合、
`repairMissingTools` は「バイナリが存在する」と判断して再取得せず、
不具合が残り続ける。

## 決定

1. `tools/libjxl/bin/macos/` に `cjxl` の依存 dylib をすべてバンドルし、
   `install_name_tool` で参照を `@loader_path/<base>` へ書き換える。
   - dylib 自身の install name も `@loader_path/<base>` に変更。
   - 書き換え後に `codesign --force --sign -` で ad-hoc 再署名する
     （署名を壊すと macOS が実行を拒否するため）。
2. バンドルした dylib は `.gitattributes` で Git LFS 管理とする。
3. `ToolInstaller` にバージョン不整合検知を追加する。
   - `tools/.installed_version` にインストール時のアプリバージョンを記録。
   - 起動時に記録値と `PackageInfo.version` が異なる場合、tools を削除して
     `tools-vX.zip` を強制再取得する。
   - ローカル開発環境（`Directory.current/tools` が存在）ではスキップ。

## 代替案

- `DYLD_LIBRARY_PATH` をアプリ側で設定
  - 却下: ハードニングランタイムでは `DYLD_*` 環境変数が無視される場合がある。
- Homebrew の `cjxl` をそのまま利用
  - 却下: 配布先への Homebrew 導入を前提にできない。

## 結果

- macOS 以外の依存なしで `cjxl` が自己完結して動作することを
  PPM→JXL エンコードで確認（`/opt/homebrew` からのロード 0 件）。
- アプリ更新時に壊れたツールが自動的に入れ替わる。
- 実装箇所: `lib/data/services/tool_installer.dart`、
  `tools/libjxl/bin/macos/`、`pubspec.yaml`/`.gitattributes`
