#!/bin/sh
#####################################################################
# rumdl 実行ラッパー
#####################################################################
set -eu

# 導入先が標準と異なる場合は環境変数で明示できる。
if [ -n "${RUMDL_BIN:-}" ]; then
    exec "$RUMDL_BIN" "$@"
fi

# ターミナルから実行した場合は PATH に載っている方を優先する。
if command -v rumdl >/dev/null 2>&1; then
    exec rumdl "$@"
fi

# GUI 起動時は PATH が最小構成なので、よくあるインストール先を直接探す。
for candidate in \
    /opt/homebrew/bin/rumdl \
    /usr/local/bin/rumdl \
    "$HOME/.local/bin/rumdl"
do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "rumdl が見つかりません。'brew install rumdl' で導入してください" >&2
exit 127
