#!/usr/bin/env bash
# 現在のツールバージョンと既存の tools-latest を比較し、再公開の要否を決める。
#
# 使い方:
#   tools/preflight-tools-release.sh
#
# 環境変数:
#   REPOSITORY  GitHub リポジトリ（owner/name）
#   TAG         配布先のリリースタグ（既定: tools-latest）
#   FORCE       true なら既存配布情報に関係なく更新ありとして扱う
#   GH_TOKEN    GitHub API の認証トークン（任意）
#   GITHUB_OUTPUT changed の出力先
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/tools-release-common.sh
source "$SCRIPT_DIR/tools-release-common.sh"

TAG="${TAG:-tools-latest}"
REPOSITORY="${REPOSITORY:-treetips/tree-image-optimizer}"
FORCE="${FORCE:-false}"
OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

[[ "$FORCE" == true || "$FORCE" == false ]] || fail "FORCE は true または false を指定してください。"
[[ "$TAG" == tools-* ]] || fail "TAG は tools- で始まる名前を指定してください: $TAG"
if [[ "$TAG" != tools-latest ]]; then
  echo "::warning::アプリは tools-latest のみを参照します: $TAG"
fi
python3 - "$REPOSITORY" <<'PY'
import sys
parts = sys.argv[1].split("/")
if len(parts) != 2 or not all(parts) or any(char.isspace() for part in parts for char in part):
    raise SystemExit("REPOSITORY は owner/name 形式で指定してください")
PY
validate_tool_versions
for name in "${TOOL_NAMES[@]}"; do
  verify_tool_payload "$name"
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

api_curl() {
  local -a args=(
    -sS -L
    --retry 3
    --retry-delay 2
    --connect-timeout 30
    -H 'Accept: application/vnd.github+json'
    -H 'X-GitHub-Api-Version: 2022-11-28'
    -H 'User-Agent: tree-image-optimizer-tools-release'
  )
  if [[ -n "${GH_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer $GH_TOKEN")
  fi
  curl "${args[@]}" "$@"
}

changed=true
if [[ "$FORCE" == true ]]; then
  echo "FORCE が指定されたため、既存配布情報に関係なく再作成します。"
else
  encoded_tag="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TAG")"
  release_api="https://api.github.com/repos/${REPOSITORY}/releases/tags/${encoded_tag}"
  release_response="$WORK_DIR/release.json"

  if ! status="$(api_curl -o "$release_response" -w '%{http_code}' "$release_api")"; then
    fail "配布先リリース $TAG の API 問い合わせに失敗しました。"
  fi

  case "$status" in
    200)
      manifest_url="$(python3 - "$release_response" "$TAG" <<'PY'
import json
import pathlib
import sys
from urllib.parse import urlparse

path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"リリース {sys.argv[2]} の情報を読み込めません: {error}")
if not isinstance(data, dict) or not isinstance(data.get("assets"), list):
    raise SystemExit(f"リリース {sys.argv[2]} の情報の形式が不正です")
assets = [asset for asset in data["assets"] if isinstance(asset, dict) and asset.get("name") == "tools-info.json"]
if not assets:
    # Why not 欠落を即失敗しないか: 部分公開の復旧時は manifest から再作成する。
    print("")
    raise SystemExit(0)
if len(assets) != 1:
    raise SystemExit(f"リリース {sys.argv[2]} に tools-info.json が複数あります")
url = assets[0].get("browser_download_url")
parsed = urlparse(url) if isinstance(url, str) else None
if parsed is None or parsed.scheme != "https" or parsed.netloc != "github.com":
    raise SystemExit(f"リリース {sys.argv[2]} の tools-info.json URL が不正です")
print(url)
PY
      )" || fail "配布先リリース $TAG のマニフェスト情報を確認できませんでした。"

      if [[ -z "$manifest_url" ]]; then
        echo "tools-info.json が無いため、配布物を再作成します。"
        changed=true
      else
      manifest="$WORK_DIR/tools-info.json"
      api_curl -fsSL "$manifest_url" -o "$manifest" \
        || fail "配布先リリース $TAG の tools-info.json を取得できませんでした。"

      versions_file="$WORK_DIR/versions.txt"
      for name in "${TOOL_NAMES[@]}"; do
        printf '%s\t%s\n' "$name" "$(tool_version "$name")" >> "$versions_file"
      done

      changed="$(python3 - "$manifest" "$release_response" "$versions_file" "$TAG" "$REPOSITORY" <<'PY'
import json
import pathlib
import posixpath
import re
import sys
from urllib.parse import unquote, urlparse

manifest_path, release_path, versions_path, tag, repository = sys.argv[1:]
try:
    data = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"))
    release = json.loads(pathlib.Path(release_path).read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"配布情報を読み込めません: {error}")
if not isinstance(data, dict) or type(data.get("schemaVersion")) is not int or data["schemaVersion"] != 1:
    raise SystemExit("tools-info.json の schemaVersion が不正です")
entries = data.get("tools")
if not isinstance(entries, list):
    raise SystemExit("tools-info.json の tools が不正です")

resolved = {}
for line in pathlib.Path(versions_path).read_text(encoding="utf-8").splitlines():
    name, version = line.split("\t", 1)
    resolved[name] = version

seen = set()
entry_files = set()
current = {}
for entry in entries:
    if not isinstance(entry, dict):
        raise SystemExit("tools-info.json の entry が不正です")
    name = entry.get("name")
    version = entry.get("version")
    url = entry.get("url")
    checksum = entry.get("sha256")
    if name not in resolved:
        raise SystemExit(f"tools-info.json に未知のツールがあります: {name}")
    if name in seen:
        raise SystemExit(f"tools-info.json の {name} が重複しています")
    if not isinstance(version, str) or not version:
        raise SystemExit(f"tools-info.json の {name} に version がありません")
    if entry.get("required") is not True:
        raise SystemExit(f"tools-info.json の {name} が必須配布物ではありません")
    parsed = urlparse(url) if isinstance(url, str) else None
    expected_prefix = f"/{repository}/releases/download/{tag}/"
    if parsed is None or parsed.scheme != "https" or parsed.netloc != "github.com":
        raise SystemExit(f"tools-info.json の {name} の URL が不正です")
    if not parsed.path.startswith(expected_prefix):
        raise SystemExit(f"tools-info.json の {name} の URL が {tag} を参照していません")
    if unquote(posixpath.basename(parsed.path)) != f"tools-{name}-{version}.zip":
        raise SystemExit(f"tools-info.json の {name} のファイル名が不正です")
    if not isinstance(checksum, str) or re.fullmatch(r"[0-9a-fA-F]{64}", checksum) is None:
        raise SystemExit(f"tools-info.json の {name} の checksum が不正です")
    seen.add(name)
    entry_files.add(unquote(posixpath.basename(parsed.path)))
    current[name] = version

if seen != set(resolved):
    raise SystemExit("tools-info.json の必須 entry が不足しています")
asset_names = {
    asset.get("name")
    for asset in release.get("assets", [])
    if isinstance(asset, dict) and isinstance(asset.get("name"), str)
}
missing_assets = (entry_files | {"SHA256SUMS.txt"}) - asset_names
version_changed = any(current[name] != resolved[name] for name in resolved)
release_visibility_changed = release.get("prerelease") is not True or release.get("draft") is True
print("true" if version_changed or missing_assets or release_visibility_changed else "false")
PY
      )" || fail "配布先リリース $TAG の tools-info.json が不正です。"
      fi
      ;;
    404)
      echo "配布先リリース $TAG はまだ存在しません。"
      ;;
    *)
      fail "配布先リリース $TAG の API 問い合わせが HTTP $status で失敗しました。"
      ;;
  esac
fi

{
  printf 'changed=%s\n' "$changed"
} >> "$OUTPUT_FILE"

if [[ "$changed" == true ]]; then
  echo "ツール配布物の更新あり"
else
  echo "ツール配布物は最新です"
fi
