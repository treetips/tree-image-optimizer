#!/bin/bash
#
# start.sh — Xcodeを起動せずにアプリをビルドして起動する。
#
# 使い方:
#   ./start.sh
#
# macOSデスクトップアプリにエミュレーター（シミュレーター）は存在しないため、
# xcodebuild でビルドした .app を `open` でそのまま起動する（Mac上でネイティブ動作）。
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="TreeImageOptimizer/TreeImageOptimizer.xcodeproj"
SCHEME="TreeImageOptimizer"
CONFIGURATION="Debug"
DERIVED_DATA="$PWD/.build/derivedData"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild が見つかりません。Xcodeをインストールしてください。" >&2
    exit 1
fi

echo "==> Building (${CONFIGURATION})..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build

APP_PATH=$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION" -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP_PATH" ]; then
    echo "error: .app が見つかりませんでした。" >&2
    exit 1
fi

echo "==> Launching: $APP_PATH"
open "$APP_PATH"
