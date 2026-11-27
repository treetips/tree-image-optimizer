#!/usr/bin/env bash
# tools-release スクリプトで共有するツール一覧とバージョン解決。

TOOL_NAMES=(upscal jpegoptim pngoptim libjxl libavif libwebp realcugan)
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TOOLS_ROOT="${TOOLS_ROOT:-$REPO_ROOT/tools}"
APPINFO_PATH="${APPINFO_PATH:-$REPO_ROOT/TreeImageOptimizer/TreeImageOptimizer/Core/AppInfo.swift}"

# .version があればそれを正本とし、無い3ツールはアプリの定数から読む。
tool_version() {
  local name="$1"
  local version_file="$TOOLS_ROOT/$name/.version"
  if [[ -f "$version_file" ]]; then
    tr -d '\r' < "$version_file" | head -n1 | tr -d '[:space:]'
    return
  fi

  local key
  case "$name" in
    jpegoptim) key='jpegVersion' ;;
    pngoptim) key='pngVersion' ;;
    libwebp) key='webpVersion' ;;
    *)
      echo "::error::No version source for tool: $name" >&2
      return 1
      ;;
  esac
  grep -E "static let ${key} = \"" "$APPINFO_PATH" \
    | sed -E "s/.*\"([^\"]+)\".*/\1/" \
    | head -n1
}

validate_tool_versions() {
  local name version
  for name in "${TOOL_NAMES[@]}"; do
    version="$(tool_version "$name")"
    if [[ ! "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
      echo "::error::Invalid version for $name: $version" >&2
      return 1
    fi
  done
}

verify_payload_file() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo "::error::Missing or empty tool payload: $file" >&2
    return 1
  fi
  # Why not ファイル存在だけで済ませるか: LFSポインタは空でないため、
  # 実体を取得していないと壊れたZIPを公開してしまう。
  if head -c 128 "$file" | grep -q '^version https://git-lfs.github.com/spec/v1'; then
    echo "::error::Git LFS object was not fetched: $file" >&2
    return 1
  fi
}

verify_model_pair() {
  local param="$1"
  local bin="${param%.param}.bin"
  verify_payload_file "$param"
  verify_payload_file "$bin"
}

# 配布ZIPに必須のバイナリ・モデル・dylibが実体として存在するか確認する。
verify_tool_payload() {
  local name="$1"
  local relative
  case "$name" in
    upscal) relative='upscal/bin/upscayl-bin' ;;
    jpegoptim) relative='jpegoptim/bin/macos/jpegoptim' ;;
    pngoptim) relative='pngoptim/bin/macos/pngoptim' ;;
    libjxl) relative='libjxl/bin/macos/cjxl' ;;
    libavif) relative='libavif/bin/macos/avifenc' ;;
    libwebp) relative='libwebp/bin/macos/cwebp' ;;
    realcugan) relative='realcugan/bin/macos/realcugan-ncnn-vulkan' ;;
    *) echo "::error::Unknown tool: $name" >&2; return 1 ;;
  esac

  verify_payload_file "$TOOLS_ROOT/$relative"

  case "$name" in
    upscal)
      local param found=false
      for param in "$TOOLS_ROOT/upscal/models/"*.param; do
        [[ -f "$param" ]] || continue
        verify_model_pair "$param"
        found=true
      done
      [[ "$found" == true ]] || {
        echo "::error::No complete upscal model pair found" >&2
        return 1
      }
      ;;
    realcugan)
      local param found=false
      for param in "$TOOLS_ROOT/realcugan/"models-*/*.param; do
        [[ -f "$param" ]] || continue
        verify_model_pair "$param"
        found=true
      done
      [[ "$found" == true ]] || {
        echo "::error::No complete Real-CUGAN model pair found" >&2
        return 1
      }
      ;;
    libjxl)
      local dylib found=false
      for dylib in "$TOOLS_ROOT/libjxl/bin/macos/"*.dylib; do
        [[ -f "$dylib" ]] || continue
        verify_payload_file "$dylib"
        found=true
      done
      [[ "$found" == true ]] || {
        echo "::error::No libjxl dylib found" >&2
        return 1
      }
      ;;
  esac
}
