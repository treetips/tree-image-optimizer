#!/bin/sh
#####################################################################
# betterleaks 実行ラッパー
#####################################################################
set -eu

# 導入先が標準と異なる場合は環境変数で明示できる。
if [ -n "${BETTERLEAKS_BIN:-}" ]; then
    exec "$BETTERLEAKS_BIN" "$@"
fi

# ターミナルから実行した場合は PATH に載っている方を優先する。
if command -v betterleaks >/dev/null 2>&1; then
    exec betterleaks "$@"
fi

# GUI 起動時は PATH が最小構成なので、よくあるインストール先を直接探す。
for candidate in \
    /opt/homebrew/bin/betterleaks \
    /usr/local/bin/betterleaks \
    "$HOME/.local/bin/betterleaks"
do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "betterleaks が見つかりません。'./setup.sh'（または 'brew install betterleaks'）で導入してください" >&2
exit 127
