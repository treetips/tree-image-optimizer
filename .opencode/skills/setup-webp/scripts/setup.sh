#!/bin/bash
set -euo pipefail

# WebP セットアップスクリプト（shell 版）
# Google Storage から libwebp を取得して tools/libwebp に配置する
# 使用: bash .opencode/skills/setup-webp/scripts/setup.sh [--current-only]

VERSION="1.6.0"
BASE_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp"

CURRENT_ONLY=false
if [[ "${1:-}" == "--current-only" ]]; then
  CURRENT_ONLY=true
fi

# OS/Arch 判定
OS="$(uname -s)"
ARCH="$(uname -m)"
echo "VERSION=$VERSION OS=$OS ARCH=$ARCH CURRENT_ONLY=$CURRENT_ONLY"

download_and_extract() {
  local archive_name="$1"
  local dest_dir="$2"
  local url="$BASE_URL/$archive_name"
  local tmp_file="/tmp/$archive_name"

  echo "=== $archive_name -> $dest_dir ==="
  echo "url=$url"

  if [[ -f "$tmp_file" ]]; then
    rm -f "$tmp_file"
  fi

  echo "downloading..."
  curl -L -o "$tmp_file" "$url"
  echo "downloaded $tmp_file ($(du -h "$tmp_file" | cut -f1))"

  mkdir -p "$dest_dir"
  local exe_name="cwebp"
  if [[ "$dest_dir" == *"windows"* ]]; then
    exe_name="cwebp.exe"
  fi

  if [[ "$archive_name" == *.zip ]]; then
    unzip -o -j "$tmp_file" "*/bin/$exe_name" -d "$dest_dir" 2>/dev/null || {
      echo "Trying alternative unzip pattern..."
      unzip -l "$tmp_file" | grep cwebp
      unzip -o "$tmp_file" -d "/tmp/webp_extract"
      find /tmp/webp_extract -name "$exe_name" -type f -exec cp {} "$dest_dir/$exe_name" \;
      rm -rf /tmp/webp_extract
    }
    # unzip -j は bin パスを除去して直接配置する
    if [[ -f "$dest_dir/$exe_name" ]]; then
      echo "extracted $dest_dir/$exe_name"
    else
      # fallback: find
      find /tmp -name "$exe_name" 2>/dev/null | head -5
      echo "failed to extract $exe_name from $archive_name"
      unzip -l "$tmp_file" | head -20
      exit 1
    fi
  else
    local tmp_extract="/tmp/webp_extract_$$"
    mkdir -p "$tmp_extract"
    tar -xzf "$tmp_file" -C "$tmp_extract"
    local found
    found="$(find "$tmp_extract" -name "$exe_name" -type f | head -n1)"
    if [[ -z "$found" ]]; then
      echo "cwebp not found in $archive_name"
      find "$tmp_extract" -type f | head -20
      rm -rf "$tmp_extract"
      exit 1
    fi
    cp "$found" "$dest_dir/$exe_name"
    echo "extracted $dest_dir/$exe_name from $found"
    rm -rf "$tmp_extract"
  fi

  if [[ "$dest_dir" != *"windows"* ]]; then
    chmod +x "$dest_dir/$exe_name"
    echo "chmod +x $dest_dir/$exe_name"
  fi

  if [[ -f "$dest_dir/$exe_name" ]]; then
    echo "verify: $dest_dir/$exe_name -version"
    "$dest_dir/$exe_name" -version || "$dest_dir/$exe_name" -help | head -n 5 || true
  fi

  rm -f "$tmp_file"
}

if [[ "$CURRENT_ONLY" == true ]]; then
  if [[ "$OS" == "Darwin" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
      download_and_extract "libwebp-${VERSION}-mac-arm64.tar.gz" "tools/libwebp/bin/macos"
    else
      download_and_extract "libwebp-${VERSION}-mac-x86-64.tar.gz" "tools/libwebp/bin/macos"
    fi
  elif [[ "$OS" == "Linux" ]]; then
    if [[ "$ARCH" == "aarch64" ]]; then
      download_and_extract "libwebp-${VERSION}-linux-aarch64.tar.gz" "tools/libwebp/bin/linux"
    else
      download_and_extract "libwebp-${VERSION}-linux-x86-64.tar.gz" "tools/libwebp/bin/linux"
    fi
  elif [[ "$OS" == *"MINGW"* || "$OS" == *"MSYS"* || "$OS" == *"CYGWIN"* ]]; then
    download_and_extract "libwebp-${VERSION}-windows-x64.zip" "tools/libwebp/bin/windows"
  else
    echo "Unknown OS: $OS, trying macos arm64 as fallback"
    download_and_extract "libwebp-${VERSION}-mac-arm64.tar.gz" "tools/libwebp/bin/macos"
  fi
else
  # 全OS分をダウンロード（配布用）
  download_and_extract "libwebp-${VERSION}-mac-arm64.tar.gz" "tools/libwebp/bin/macos"
  # x86_64 は同じ dest なので別途保存しない（必要なら macos-x64 として分離可能）
  # download_and_extract "libwebp-${VERSION}-mac-x86-64.tar.gz" "tools/libwebp/bin/macos-x64"
  download_and_extract "libwebp-${VERSION}-linux-x86-64.tar.gz" "tools/libwebp/bin/linux"
  # aarch64 は同様にスキップ
  download_and_extract "libwebp-${VERSION}-windows-x64.zip" "tools/libwebp/bin/windows"
fi

echo ""
echo "Done. Installed:"
ls -lh tools/libwebp/bin/macos/cwebp 2>/dev/null || echo "  macos: not found"
ls -lh tools/libwebp/bin/linux/cwebp 2>/dev/null || echo "  linux: not found"
ls -lh tools/libwebp/bin/windows/cwebp.exe 2>/dev/null || echo "  windows: not found"
