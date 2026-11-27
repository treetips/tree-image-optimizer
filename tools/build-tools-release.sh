#!/usr/bin/env bash
# tools/<name> をツール単位ZIPと tools-info.json にまとめる。
#
# 使い方:
#   tools/build-tools-release.sh <output-dir>
#
# 環境変数:
#   REPO_URL  GitHub リポジトリの URL
#   TAG       配布先のリリースタグ（既定: tools-latest）
#   CHANGED_TOOLS 再生成するツール名（空なら全ツール）
#   REMOTE_MANIFEST 変更しないツールの参照元 manifest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/tools-release-common.sh
source "$SCRIPT_DIR/tools-release-common.sh"

OUT_DIR="${1:?出力先ディレクトリを指定してください}"
REPO_URL="${REPO_URL:-https://github.com/treetips/tree-image-optimizer}"
TAG="${TAG:-tools-latest}"
CHANGED_TOOLS="${CHANGED_TOOLS:-$(IFS=,; echo "${TOOL_NAMES[*]}")}"
REMOTE_MANIFEST="${REMOTE_MANIFEST:-}"

[[ "$TAG" == tools-* ]] || {
  echo "::error::TAG は tools- で始まる名前を指定してください: $TAG" >&2
  exit 1
}
for name in ${CHANGED_TOOLS//,/ }; do
  case " ${TOOL_NAMES[*]} " in
    *" $name "*) ;;
    *) echo "::error::CHANGED_TOOLS に未知のツールがあります: $name" >&2; exit 1 ;;
  esac
done

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# 同じ出力ディレクトリへの再実行で古いツールZIPが残らないようにする。
rm -f "$OUT_DIR"/tools-*.zip "$OUT_DIR/tools-info.json" "$OUT_DIR/SHA256SUMS.txt"

entries_file="$(mktemp)"
trap 'rm -f "$entries_file"' EXIT

for name in ${CHANGED_TOOLS//,/ }; do
  version="$(tool_version "$name")"
  [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || {
    echo "::error::Invalid version for $name: $version" >&2
    exit 1
  }
  verify_tool_payload "$name"
  printf '%s\t%s\n' "$name" "$version" >> "$entries_file"
done

# Why not ditto を使わないか: checkout日時に依存するZIPを防ぎ、force再公開でもチェックサムを安定させるため。
python3 - "$OUT_DIR" "$TOOLS_ROOT" "$REPO_URL" "$TAG" "$entries_file" "$REMOTE_MANIFEST" "${TOOL_NAMES[*]}" <<'PY'
import hashlib
import json
import os
import pathlib
import posixpath
import re
import stat
import sys
import zipfile
from urllib.parse import unquote, urlparse


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def zip_info(name, mode, is_directory=False):
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = mode << 16
    if is_directory:
        info.external_attr |= 0x10
    return info


def write_directory(archive, name):
    archive.writestr(zip_info(f"{name}/", 0o40755, is_directory=True), b"")


def write_symlink(archive, name, path):
    info = zip_info(name, 0o120777)
    archive.writestr(info, os.readlink(path).encode("utf-8"))


def write_file(archive, name, path):
    mode = path.stat().st_mode
    normalized_mode = 0o40755 if stat.S_ISDIR(mode) else (0o100755 if mode & 0o111 else 0o100644)
    info = zip_info(name, normalized_mode)
    info.file_size = path.stat().st_size
    with archive.open(info, "w", force_zip64=True) as destination, path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            destination.write(chunk)


def write_tree(archive, root, relative):
    path = root / relative
    if path.is_symlink():
        write_symlink(archive, f"{root.name}/{relative.as_posix()}", path)
        return
    if path.is_dir():
        write_directory(archive, f"{root.name}/{relative.as_posix()}" if relative.as_posix() != "." else root.name)
        for child in sorted(path.iterdir(), key=lambda item: item.name):
            if child.name.startswith("._") or child.name == ".DS_Store":
                continue
            write_tree(archive, root, child.relative_to(root))
        return
    if path.is_file():
        write_file(archive, f"{root.name}/{relative.as_posix()}", path)
        return
    raise SystemExit(f"unsupported tool payload: {path}")


def build_archive(name, destination):
    root = tools_root / name
    if not root.is_dir():
        raise SystemExit(f"missing tool directory: {root}")
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        write_tree(archive, root, pathlib.Path("."))


out = pathlib.Path(sys.argv[1])
tools_root = pathlib.Path(sys.argv[2])
repo_url = sys.argv[3].rstrip("/")
tag = sys.argv[4]
entries_path = pathlib.Path(sys.argv[5])
remote_manifest = pathlib.Path(sys.argv[6]) if sys.argv[6] else None
expected_names = sys.argv[7].split()
changed = {}
for line in entries_path.read_text(encoding="utf-8").splitlines():
    name, version = line.split("\t")
    changed[name] = version

if not set(changed) <= set(expected_names):
    raise SystemExit("CHANGED_TOOLS に未知のツールがあります")

remote_entries = {}
if remote_manifest is not None and remote_manifest.is_file():
    try:
        remote = json.loads(remote_manifest.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"既存 manifest を読み込めません: {error}")
    if not isinstance(remote, dict) or remote.get("schemaVersion") != 1 or not isinstance(remote.get("tools"), list):
        raise SystemExit("既存 manifest の形式が不正です")
    for entry in remote["tools"]:
        if not isinstance(entry, dict):
            raise SystemExit("既存 manifest の entry が不正です")
        name = entry.get("name")
        version = entry.get("version")
        checksum = entry.get("sha256")
        if name not in expected_names or name in remote_entries:
            raise SystemExit(f"既存 manifest のツール名が不正です: {name}")
        if not isinstance(version, str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", version) is None:
            raise SystemExit(f"既存 manifest のバージョンが不正です: {name}")
        if entry.get("required") is not True:
            raise SystemExit(f"既存 manifest の {name} が必須ツールではありません")
        if not isinstance(checksum, str) or re.fullmatch(r"[0-9a-fA-F]{64}", checksum) is None:
            raise SystemExit(f"既存 manifest の checksum が不正です: {name}")
        parsed = urlparse(entry.get("url", ""))
        filename = f"tools-{name}-{version}.zip"
        if parsed.scheme != "https" or parsed.netloc != "github.com":
            raise SystemExit(f"既存 manifest の URL が不正です: {name}")
        if not parsed.path.startswith(f"/{repo_url.removeprefix('https://github.com/')}/releases/download/{tag}/"):
            raise SystemExit(f"既存 manifest の URL が配布先と一致しません: {name}")
        if unquote(posixpath.basename(parsed.path)) != filename:
            raise SystemExit(f"既存 manifest のファイル名が不正です: {name}")
        remote_entries[name] = entry
    if set(remote_entries) != set(expected_names):
        raise SystemExit("既存 manifest の必須ツールが不足しています")
elif set(changed) != set(expected_names):
    raise SystemExit("既存 manifest がないため、全ツールを再生成してください")

entries = []
checksum_by_name = {}
for name in expected_names:
    if name in changed:
        version = changed[name]
        filename = f"tools-{name}-{version}.zip"
        asset = out / filename
        build_archive(name, asset)
        checksum = sha256(asset)
        entry = {
            "name": name,
            "version": version,
            "url": f"{repo_url}/releases/download/{tag}/{filename}",
            "sha256": checksum,
            "required": True,
        }
        print(f"Created: {filename}")
    else:
        entry = dict(remote_entries[name])
        filename = unquote(posixpath.basename(urlparse(entry["url"]).path))
        checksum = entry["sha256"]
        print(f"Reuse manifest entry: {filename}")
    entries.append(entry)
    checksum_by_name[filename] = checksum

manifest = out / "tools-info.json"
manifest.write_text(
    json.dumps({"schemaVersion": 1, "tools": entries}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
checksum_by_name[manifest.name] = sha256(manifest)
checksums = out / "SHA256SUMS.txt"
files = [out / unquote(posixpath.basename(urlparse(entry["url"]).path)) for entry in entries] + [manifest]
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
