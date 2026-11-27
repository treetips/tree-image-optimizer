#!/usr/bin/env bash
# 上流ツールのバージョンを解決し、既存の tools-latest と比較する。
#
# 使い方:
#   tools/preflight-tools-release.sh
#
# 環境変数:
#   REPOSITORY       GitHub リポジトリ（owner/name）
#   TAG              配布先のリリースタグ（既定: tools-latest）
#   UPSCAL_VERSION   上流の代わりに使う upscal の版（空なら最新を解決）
#   REALCUGAN_VERSION 同様
#   JPEGOPTIM_VERSION 同様
#   PNGOPTIM_VERSION  同様
#   LIBJXL_VERSION    同様
#   LIBAVIF_VERSION   同様
#   LIBWEBP_VERSION   同様
#   FORCE             true なら既存配布情報に関係なく更新ありとして扱う
#   GH_TOKEN          GitHub API の認証トークン（任意）
#   GITHUB_OUTPUT     changed / <tool>_version の出力先
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

resolve_latest_tag() {
  local repository="$1"
  local response="$2"
  local url="https://api.github.com/repos/${repository}/releases/latest"

  api_curl -fsSL "$url" -o "$response" || return 1
  python3 - "$response" "$repository" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"{sys.argv[2]} の最新リリース情報を読み込めません: {error}")
if not isinstance(data, dict):
    raise SystemExit(f"{sys.argv[2]} の最新リリース情報の形式が不正です")
version = data.get("tag_name")
if not isinstance(version, str) or not version or any(char.isspace() for char in version):
    raise SystemExit(f"{sys.argv[2]} の最新リリースに tag_name がありません")
print(version)
PY
}

resolve_libwebp_version() {
  local response="$1"
  # Why not api_curl を使わないか: GitHub token を Google Storage へ送らないため。
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 \
    'https://storage.googleapis.com/downloads.webmproject.org/releases/webp/index.html' \
    -o "$response" || return 1
  python3 - "$response" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
versions = set(re.findall(r"libwebp-(\d+\.\d+\.\d+)-mac-arm64\.tar\.gz", text))
if not versions:
    raise SystemExit("libwebp の macOS arm64 配布物が見つかりません")
print(max(versions, key=lambda value: tuple(map(int, value.split(".")))))
PY
}

explicit_version() {
  case "$1" in
    upscal) printf '%s' "${UPSCAL_VERSION:-}" ;;
    realcugan) printf '%s' "${REALCUGAN_VERSION:-}" ;;
    jpegoptim) printf '%s' "${JPEGOPTIM_VERSION:-}" ;;
    pngoptim) printf '%s' "${PNGOPTIM_VERSION:-}" ;;
    libjxl) printf '%s' "${LIBJXL_VERSION:-}" ;;
    libavif) printf '%s' "${LIBAVIF_VERSION:-}" ;;
    libwebp) printf '%s' "${LIBWEBP_VERSION:-}" ;;
  esac
}

resolve_upstream_versions() {
  local name version repository tag
  for name in "${TOOL_NAMES[@]}"; do
    version="$(explicit_version "$name")"
    if [[ -z "$version" ]]; then
      case "$name" in
        upscal)
          repository='upscayl/upscayl-ncnn'
          if ! tag="$(resolve_latest_tag "$repository" "$WORK_DIR/upscal-latest.json")"; then
            fail "upscal の最新バージョンを解決できませんでした。"
          fi
          version="upscayl-bin-$tag"
          ;;
        realcugan)
          repository='nihui/realcugan-ncnn-vulkan'
          if ! tag="$(resolve_latest_tag "$repository" "$WORK_DIR/realcugan-latest.json")"; then
            fail "Real-CUGAN の最新バージョンを解決できませんでした。"
          fi
          version="realcugan-ncnn-vulkan-$tag"
          ;;
        jpegoptim)
          if ! version="$(resolve_latest_tag 'tjko/jpegoptim' "$WORK_DIR/jpegoptim-latest.json")"; then
            fail "jpegoptim の最新バージョンを解決できませんでした。"
          fi
          ;;
        pngoptim)
          if ! version="$(resolve_latest_tag 'okooo5km/pngoptim' "$WORK_DIR/pngoptim-latest.json")"; then
            fail "pngoptim の最新バージョンを解決できませんでした。"
          fi
          ;;
        libjxl)
          if ! version="$(resolve_latest_tag 'libjxl/libjxl' "$WORK_DIR/libjxl-latest.json")"; then
            fail "libjxl の最新バージョンを解決できませんでした。"
          fi
          ;;
        libavif)
          if ! version="$(resolve_latest_tag 'AOMediaCodec/libavif' "$WORK_DIR/libavif-latest.json")"; then
            fail "libavif の最新バージョンを解決できませんでした。"
          fi
          ;;
        libwebp)
          if ! version="$(resolve_libwebp_version "$WORK_DIR/libwebp-index.html")"; then
            fail "libwebp の最新バージョンを解決できませんでした。"
          fi
          ;;
      esac
    fi
    printf '%s\t%s\n' "$name" "$version" >> "$versions_file"
  done

  python3 - "$versions_file" <<'PY'
import pathlib
import re
import sys

for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    name, version = line.split("\t", 1)
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", version) is None:
        raise SystemExit(f"{name} のバージョンに不正な文字が含まれています: {version}")
PY
}

versions_file="$WORK_DIR/versions.txt"
resolve_upstream_versions

changed=true
changed_tools=""
all_tools="$(IFS=,; echo "${TOOL_NAMES[*]}")"
if [[ "$FORCE" == true ]]; then
  changed_tools="$all_tools"
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
        changed_tools="$all_tools"
      else
        manifest="$WORK_DIR/tools-info.json"
        # Why not api_curl を使わないか: Release asset の CDN へ GitHub token を転送しないため。
        curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 \
          "$manifest_url" -o "$manifest" \
          || fail "配布先リリース $TAG の tools-info.json を取得できませんでした。"

        comparison="$(python3 - "$manifest" "$release_response" "$versions_file" "$TAG" "$REPOSITORY" <<'PY'
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
asset_digests = {
    asset.get("name"): asset.get("digest")
    for asset in release.get("assets", [])
    if isinstance(asset, dict) and isinstance(asset.get("name"), str)
}
missing_assets = (entry_files | {"SHA256SUMS.txt"}) - set(asset_digests)
for entry in entries:
    filename = unquote(posixpath.basename(urlparse(entry["url"]).path))
    digest = asset_digests.get(filename)
    if not isinstance(digest, str) or re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest) is None:
        raise SystemExit(f"Release asset の digest が不正です: {filename}")
    if digest.removeprefix("sha256:").lower() != entry["sha256"].lower():
        raise SystemExit(f"Release asset と manifest の SHA-256 が一致しません: {filename}")
version_changed_names = [name for name in resolved if current[name] != resolved[name]]
version_changed = bool(version_changed_names)
release_visibility_changed = release.get("prerelease") is not True or release.get("draft") is True
repair_all = bool(missing_assets) or release_visibility_changed
changed_names = list(resolved) if repair_all else version_changed_names
print("true" if version_changed or missing_assets or release_visibility_changed else "false")
print(",".join(changed_names))
PY
        )" || fail "配布先リリース $TAG の tools-info.json が不正です。"
        changed="${comparison%%$'\n'*}"
        if [[ "$comparison" == *$'\n'* ]]; then
          changed_tools="${comparison#*$'\n'}"
        else
          changed_tools=""
        fi
      fi
      ;;
    404)
      echo "配布先リリース $TAG はまだ存在しません。"
      changed_tools="$all_tools"
      ;;
    *)
      fail "配布先リリース $TAG の API 問い合わせに HTTP $status で失敗しました。"
      ;;
  esac
fi

{
  printf 'changed=%s\n' "$changed"
  printf 'changed_tools=%s\n' "$changed_tools"
  while IFS=$'\t' read -r name version; do
    printf '%s_version=%s\n' "$name" "$version"
  done < "$versions_file"
} >> "$OUTPUT_FILE"

if [[ "$changed" == true ]]; then
  echo "ツール配布物の更新あり"
  echo "  更新対象: $changed_tools"
  while IFS=$'\t' read -r name version; do
    echo "  $name: $version"
  done < "$versions_file"
else
  echo "ツール配布物は最新です"
  while IFS=$'\t' read -r name version; do
    echo "  $name: $version"
  done < "$versions_file"
fi
