---
name: setup-webp
description: WebP (libwebp) ツールを Google Storage から取得して tools/libwebp に配置するスキル
---

# setup-webp

`libwebp` は GitHub Releases で配布されていないため、Google Storage (`https://storage.googleapis.com/downloads.webmproject.org/releases/webp/index.html`) から取得する。

## バージョン

- `lib/core/constants/app_constants.dart:webpVersion` で管理（現在 `1.6.0`）

## 配布アーカイブ

| OS | Arch | アーカイブ |
|---|---|---|
| macOS | arm64 | `libwebp-1.6.0-mac-arm64.tar.gz` |
| macOS | x86-64 | `libwebp-1.6.0-mac-x86-64.tar.gz` |
| Linux | x86-64 | `libwebp-1.6.0-linux-x86-64.tar.gz` |
| Linux | aarch64 | `libwebp-1.6.0-linux-aarch64.tar.gz` |
| Windows | x64 | `libwebp-1.6.0-windows-x64.zip` |

ベースURL: `https://storage.googleapis.com/downloads.webmproject.org/releases/webp/`

## 配置先

```
tools/libwebp/bin/macos/cwebp        # mac-arm64 または mac-x86-64 の bin/cwebp
tools/libwebp/bin/macos/cwebp (x86_64版は別途 tools/libwebp/bin/macos-x64 などを用意せず、現行 PathService は macos 単一を想定)
tools/libwebp/bin/linux/cwebp
tools/libwebp/bin/windows/cwebp.exe
```

> ローカル開発では実行ホストのアーキテクチャに合わせたアーカイブのみを `tools/libwebp/bin/<os>` に配置すれば動作する。リリース配布時は全OS分を格納する。

## Workflow

1. **バージョン確認**
   - `AppConstants.webpVersion` を読む

2. **ダウンロード**
   - `tool/setup_webp.dart` または `scripts/setup-webp.sh` を実行
   ```bash
   dart run tool/setup_webp.dart
   # または
   bash .opencode/skills/setup-webp/scripts/setup.sh
   ```

3. **展開**
   - `tar.gz` は `GZipDecoder` + `TarDecoder`（`package:archive`）で展開
   - `zip` は `ZipDecoder` で展開
   - アーカイブ内の `*/bin/cwebp`（または `cwebp.exe`）を `tools/libwebp/bin/<os>/` へコピー

4. **権限付与**
   ```bash
   chmod +x tools/libwebp/bin/macos/cwebp
   chmod +x tools/libwebp/bin/linux/cwebp
   ```

5. **検証**
   ```bash
   tools/libwebp/bin/macos/cwebp -version
   tools/libwebp/bin/macos/cwebp -help | head -n 20
   ```

6. **アプリ側連携**
   - `PathService.libwebpBinDirectory()` / `cwebpBinPath()` が `tools/libwebp/bin/<os>` を解決
   - `ToolInstaller` が `libwebp/bin/<os>/cwebp` の存在を `isInstalled()` / `repairMissingTools()` で検証し、欠損時は Google Storage から自動取得（`_downloadAndExtractLibwebp()`）
   - `CompressionService._compressWebp()` が `cwebp -preset <preset> -q <quality> -m <method> -mt input -o output` を実行

## 関連ドキュメント

- `docs/design/feature/convert-flow/compression.md` - WebP 圧縮パラメータ（`WEBP_PRESET` / `WEBP_METHOD`）
- `docs/design/feature/convert.md` - フォーマットプルダウンに `WebP` を追加
- `lib/data/services/tool_installer.dart` - Google Storage からの取得ロジック
- `lib/data/services/path_service.dart` - `libwebpBinDirectory()` / `cwebpBinPath()`
- `lib/data/services/compression_service.dart` - WebP 圧縮実装
