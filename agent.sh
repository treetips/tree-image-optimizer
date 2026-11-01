#!/bin/bash
#
# agent.sh — このリポジトリをワークスペースとして、OpenCodeの対話TUIを起動する。
#
# 使い方:
#   ./agent.sh
#
# プロバイダー opencode / モデル opencode/glm-5.3-flash-free で起動する。
# 引数はそのままopencodeに渡す（例: ./agent.sh --continue）。
#
# フルTUIのopencodeには--modelが無く、モデルは設定でしか指定できない。
# また、既定の共有バックグラウンドサービスは別プロセスの環境変数を読まないため、
# 環境変数だけではモデルが差し替わらない（実測で確認済み）。
# そこで--standaloneでプライベートサーバーを立て、その環境変数を読ませる。
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v opencode >/dev/null 2>&1; then
    echo "error: opencode が見つかりません。OpenCodeをインストールしてください。" >&2
    exit 1
fi

MODEL="opencode/glm-5.3-flash-free"
OPENCODE_CONFIG_CONTENT=$(printf '{"$schema":"https://opencode.ai/config.json","model":"%s"}' "$MODEL")
export OPENCODE_CONFIG_CONTENT

exec opencode --standalone "$@"
