#!/usr/bin/env bash
# tools/<name> をツール単位ZIPと tools-info.json にまとめる。
#
# 使い方:
#   tools/build-tools-release.sh <output-dir>
#
# 環境変数:
#   REPO_URL  GitHub リポジトリの URL
#   TAG       配布先のリリースタグ（既定: tools-latest）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/tools-release-common.sh
source "$SCRIPT_DIR/tools-release-common.sh"

OUT_DIR="${1:?出力先ディレクトリを指定してください}"
REPO_URL="${REPO_URL:-https://github.com/treetips/tree-image-optimizer}"
TAG="${TAG:-tools-latest}"

[[ "$TAG" == tools-* ]] || {
  echo "::error::TAG は tools- で始まる名前を指定してください: $TAG" >&2
  exit 1
}
validate_tool_versions

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# 同じ出力ディレクトリへの再実行で古いツールZIPが残らないようにする。
rm -f "$OUT_DIR"/tools-*.zip "$OUT_DIR/tools-info.json" "$OUT_DIR/SHA256SUMS.txt"

entries_file="$(mktemp)"
trap 'rm -f "$entries_file"' EXIT

for name in "${TOOL_NAMES[@]}"; do
  version="$(tool_version "$name")"
  verify_tool_payload "$name"

  zip_name="tools-${name}-${version}.zip"
  # Why not AppleDouble（._*）を残すか: ツールディレクトリへゴミを配置しないため。
  # ZIPのルートはツール名ディレクトリとし、クライアントの展開規則を変えない。
  COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent \
    "$TOOLS_ROOT/$name" "$OUT_DIR/$zip_name"
  printf '%s\t%s\n' "$name" "$version" >> "$entries_file"
  echo "Created: $zip_name"
done

python3 - "$OUT_DIR" "$REPO_URL" "$TAG" "$entries_file" <<'PY'
import hashlib
import json
import pathlib
import sys


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


out = pathlib.Path(sys.argv[1])
repo_url = sys.argv[2].rstrip("/")
tag = sys.argv[3]
entries = []
checksum_by_name = {}
for line in pathlib.Path(sys.argv[4]).read_text(encoding="utf-8").splitlines():
    name, version = line.split("\t")
    filename = f"tools-{name}-{version}.zip"
    asset = out / filename
    if not asset.is_file():
        raise SystemExit(f"missing asset: {asset}")
    checksum = sha256(asset)
    checksum_by_name[filename] = checksum
    entries.append(
        {
            "name": name,
            "version": version,
            "url": f"{repo_url}/releases/download/{tag}/{filename}",
            "sha256": checksum,
            "required": True,
        }
    )

manifest = out / "tools-info.json"
manifest.write_text(
    json.dumps({"schemaVersion": 1, "tools": entries}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
checksums = out / "SHA256SUMS.txt"
files = sorted(out.glob("tools-*.zip")) + [manifest]
checksums.write_text(
    "".join(
        f"{checksum_by_name.get(path.name) or sha256(path)}  {path.name}\n"
        for path in files
    ),
    encoding="utf-8",
)
print(f"created: {manifest}")
print(f"created: {checksums}")
PY
