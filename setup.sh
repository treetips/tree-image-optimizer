#!/bin/sh
##################################################################
# プロジェクトのセットアップ
##################################################################
set -eu

cd "$(dirname "$0")"

# 依存パッケージのインストール
brew bundle install

# git hooks のインストール
prek install

# VSCode Extension のインストール
if command -v code >/dev/null 2>&1; then
    extensions=$(jq -r '.recommendations[]' .vscode/extensions.json)
    for extension in $extensions; do
        code --install-extension "$extension"
    done
else
    echo "code コマンドが見つからないため、VSCode Extension のインストールをスキップします" >&2
fi
