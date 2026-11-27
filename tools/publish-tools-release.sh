#!/usr/bin/env bash
# ビルド済みツール成果物を tools-latest の事前リリースへ公開する。
#
# 使い方:
#   tools/publish-tools-release.sh <output-dir>
#
# 環境変数:
#   GH_TOKEN     GitHub 認証トークン
#   TAG          配布先のリリースタグ（既定: tools-latest）
#   FORCE        true なら同名assetの内容が異なる場合も明示的に上書きする
#   GITHUB_SHA   新規Releaseのタグ先（既定: main）
set -euo pipefail

OUT_DIR="${1:?成果物ディレクトリを指定してください}"
TAG="${TAG:-tools-latest}"
GH_TOKEN="${GH_TOKEN:?GitHub 認証トークンを指定してください}"
TARGET_COMMIT="${GITHUB_SHA:-main}"
FORCE="${FORCE:-false}"

[[ "$TAG" == tools-* ]] || {
  echo "::error::TAG は tools- で始まる名前を指定してください: $TAG" >&2
  exit 1
}
[[ "$FORCE" == true || "$FORCE" == false ]] || {
  echo "::error::FORCE は true または false を指定してください: $FORCE" >&2
  exit 1
}
[[ -d "$OUT_DIR" ]] || {
  echo "::error::成果物ディレクトリがありません: $OUT_DIR" >&2
  exit 1
}
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
[[ -f "$OUT_DIR/tools-info.json" ]] || {
  echo "::error::tools-info.json がありません: $OUT_DIR" >&2
  exit 1
}
[[ -f "$OUT_DIR/SHA256SUMS.txt" ]] || {
  echo "::error::SHA256SUMS.txt がありません: $OUT_DIR" >&2
  exit 1
}

# 公開前にローカル成果物とmanifestの整合性を確認する。
# 変更されないツールのZIPはremoteにあるため、ローカルにないファイルは検証対象から外す。
python3 - "$OUT_DIR" <<'PY'
import hashlib
import json
import pathlib
import posixpath
import re
import sys
from urllib.parse import unquote, urlparse

out = pathlib.Path(sys.argv[1])


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


manifest = json.loads((out / "tools-info.json").read_text(encoding="utf-8"))
if not isinstance(manifest, dict) or manifest.get("schemaVersion") != 1 or not isinstance(manifest.get("tools"), list):
    raise SystemExit("tools-info.json の形式が不正です")
expected = {"upscal", "jpegoptim", "pngoptim", "libjxl", "libavif", "libwebp", "realcugan"}
seen = set()
files = set()
listed_files = set()
checksums = {}
for entry in manifest["tools"]:
    if not isinstance(entry, dict) or entry.get("name") not in expected or entry.get("name") in seen:
        raise SystemExit("tools-info.json のツール名が不正です")
    name = entry.get("name")
    version = entry.get("version")
    checksum = entry.get("sha256")
    if not isinstance(version, str) or not version or entry.get("required") is not True:
        raise SystemExit(f"tools-info.json の {name} が不正です")
    if not isinstance(checksum, str) or re.fullmatch(r"[0-9a-fA-F]{64}", checksum) is None:
        raise SystemExit(f"tools-info.json の {name} の checksum が不正です")
    filename = unquote(posixpath.basename(urlparse(entry.get("url", "")).path))
    if filename != f"tools-{name}-{version}.zip":
        raise SystemExit(f"tools-info.json の {name} のファイル名が不正です")
    seen.add(name)
    files.add(filename)
    checksums[filename] = checksum.lower()
if seen != expected:
    raise SystemExit("tools-info.json の必須7ツールが不足しています")
for line in (out / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
    checksum, filename = line.split("  ", 1)
    listed_files.add(filename)
    if filename == "tools-info.json":
        checksums[filename] = checksum.lower()
    elif filename not in files or checksums.get(filename) != checksum.lower():
        raise SystemExit(f"SHA256SUMS.txt の内容が manifest と一致しません: {filename}")
if listed_files != files | {"tools-info.json"}:
    raise SystemExit("SHA256SUMS.txt のファイル集合が manifest と一致しません")
for filename, expected_checksum in checksums.items():
    path = out / filename
    if path.is_file():
        actual = sha256(path)
        if actual != expected_checksum:
            raise SystemExit(f"ローカル成果物の SHA-256 が一致しません: {filename}")
PY

binary_assets=()
for file in "$OUT_DIR"/tools-*.zip; do
  [[ -f "$file" ]] || continue
  binary_assets+=("$file")
done
[[ "${#binary_assets[@]}" -gt 0 ]] || {
  echo "::error::アップロードするツール成果物がありません: $OUT_DIR" >&2
  exit 1
}

release_exists=false
remote_assets=""
remote_manifest=""
METADATA_DIR="$(mktemp -d)"
trap 'rm -rf "$METADATA_DIR"' EXIT
if remote_assets="$(gh release view "$TAG" --json assets \
  --jq '.assets[] | [.name, (.digest // "")] | @tsv' 2>/dev/null)"; then
  release_exists=true
  if gh release download "$TAG" --pattern 'tools-info.json' --dir "$METADATA_DIR" >/dev/null 2>&1; then
    remote_manifest="$METADATA_DIR/tools-info.json"
  fi
fi
printf '%s\n' "$remote_assets" > "$METADATA_DIR/remote-assets.tsv"
python3 - "$OUT_DIR/tools-info.json" "$METADATA_DIR/remote-assets.tsv" "$OUT_DIR" <<'PY'
import json
import pathlib
import posixpath
import sys
from urllib.parse import unquote, urlparse

manifest_path, remote_path, out_dir = sys.argv[1:]
out = pathlib.Path(out_dir)
manifest = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"))
filenames = {
    unquote(posixpath.basename(urlparse(entry.get("url", "")).path))
    for entry in manifest.get("tools", [])
    if isinstance(entry, dict)
}
remote_names = {
    line.split("\t", 1)[0]
    for line in pathlib.Path(remote_path).read_text(encoding="utf-8").splitlines()
    if line
}
remote_digests = {
    parts[0]: parts[1] if len(parts) > 1 else ""
    for line in pathlib.Path(remote_path).read_text(encoding="utf-8").splitlines()
    if line
    for parts in [line.split("\t", 1)]
}
missing = {
    filename
    for filename in filenames
    if not (out / filename).is_file() and filename not in remote_names
}
if missing:
    raise SystemExit(f"公開するZIPがローカルにもremoteにもありません: {sorted(missing)}")
for entry in manifest.get("tools", []):
    if not isinstance(entry, dict):
        continue
    filename = unquote(posixpath.basename(urlparse(entry.get("url", "")).path))
    if (out / filename).is_file():
        continue
    digest = remote_digests.get(filename, "")
    if digest.removeprefix("sha256:").lower() != entry.get("sha256", "").lower():
        raise SystemExit(f"remote asset と manifest の SHA-256 が一致しません: {filename}")
PY

if [[ "$release_exists" == false ]]; then
  # Why not 公開状態で先に作るか: アップロード失敗時に利用者へ壊れた配布物を露出しないため。
  gh release create "$TAG" \
    --target "$TARGET_COMMIT" \
    --title "Tools" \
    --notes "Tree Image Optimizer の外部ツール配布物です。アプリが起動時に取得します。" \
    --prerelease --draft
  # 既存Draftの再開も、全assetを揃えてから下の編集ステップで公開する。
fi

# 通常公開は同名assetの内容差を拒否し、force時だけ明示的な上書きを許す。
# 既存assetとチェックサムが一致した場合はどちらの場合もアップロードを省略する。
reuse_assets=()
for file in "${binary_assets[@]}"; do
  name="${file##*/}"
  remote_digest="$(printf '%s\n' "$remote_assets" | awk -F '\t' -v name="$name" '$1 == name { print $2 }')"
  if [[ -n "$remote_digest" ]]; then
    local_digest="sha256:$(shasum -a 256 "$file" | awk '{print $1}')"
    if [[ "$remote_digest" != "$local_digest" ]]; then
      if [[ "$FORCE" == true ]]; then
        echo "Replace changed asset: $name"
        gh release upload "$TAG" "$file" --clobber
        continue
      fi
      if [[ -n "$remote_manifest" ]] && python3 - "$OUT_DIR/tools-info.json" "$remote_manifest" \
        "$name" "$remote_digest" <<'PY'
import json
import pathlib
import sys

local_path, remote_path, filename, remote_digest = sys.argv[1:]
local = json.loads(pathlib.Path(local_path).read_text(encoding="utf-8"))
remote = json.loads(pathlib.Path(remote_path).read_text(encoding="utf-8"))
local_entries = [entry for entry in local.get("tools", []) if pathlib.PurePosixPath(entry.get("url", "")).name == filename]
remote_entries = [entry for entry in remote.get("tools", []) if pathlib.PurePosixPath(entry.get("url", "")).name == filename]
if len(local_entries) != 1 or len(remote_entries) != 1:
    raise SystemExit(1)
if local_entries[0].get("name") != remote_entries[0].get("name"):
    raise SystemExit(1)
if local_entries[0].get("version") != remote_entries[0].get("version"):
    raise SystemExit(1)
if remote_entries[0].get("sha256", "").lower() != remote_digest.removeprefix("sha256:").lower():
    raise SystemExit(1)
PY
      then
        echo "Reuse unchanged version asset: $name"
        reuse_assets+=("$name")
        continue
      fi
      echo "::error::$name は既存assetと内容が異なります。ツールバージョンを変更してください。" >&2
      exit 1
    fi
    echo "Skip unchanged asset: $name"
  else
    gh release upload "$TAG" "$file"
  fi
done

if [[ "${#reuse_assets[@]}" -gt 0 ]]; then
  python3 - "$OUT_DIR/tools-info.json" "$OUT_DIR/SHA256SUMS.txt" "$remote_manifest" \
    "${reuse_assets[@]}" <<'PY'
import json
import pathlib
import sys

manifest_path, checksums_path, remote_path, *filenames = sys.argv[1:]
manifest_path = pathlib.Path(manifest_path)
checksums_path = pathlib.Path(checksums_path)
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
remote = json.loads(pathlib.Path(remote_path).read_text(encoding="utf-8"))
remote_by_file = {
    pathlib.PurePosixPath(entry.get("url", "")).name: entry
    for entry in remote.get("tools", [])
}
checksums = {}
for filename in filenames:
    entry = remote_by_file[filename]
    for local_entry in manifest["tools"]:
        if pathlib.PurePosixPath(local_entry.get("url", "")).name == filename:
            local_entry["sha256"] = entry["sha256"]
            checksums[filename] = entry["sha256"]
manifest_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
lines = pathlib.Path(checksums_path).read_text(encoding="utf-8").splitlines()
updated = [
    f"{checksums[pathlib.Path(line.split('  ', 1)[1]).name]}  {line.split('  ', 1)[1]}"
    if line.split("  ", 1)[1] in checksums
    else line
    for line in lines
]
pathlib.Path(checksums_path).write_text("\n".join(updated) + "\n", encoding="utf-8")
PY
fi

# メタデータは最後に更新し、新しいZIPが見える前にmanifestを切り替えない。
gh release upload "$TAG" "$OUT_DIR/SHA256SUMS.txt" --clobber
gh release upload "$TAG" "$OUT_DIR/tools-info.json" --clobber

keep_assets=" SHA256SUMS.txt tools-info.json "
manifest_asset_names="$(python3 - "$OUT_DIR/tools-info.json" <<'PY'
import json
import pathlib
import posixpath
import sys
from urllib.parse import unquote, urlparse

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for entry in manifest["tools"]:
    print(unquote(posixpath.basename(urlparse(entry["url"]).path)))
PY
)" || {
  echo "::error::公開対象assetの一覧を取得できませんでした。" >&2
  exit 1
}
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  keep_assets+=" $name "
done <<< "$manifest_asset_names"

# Why not process substitution を使うか: API失敗を set -e で検出できないため。
asset_names="$(gh release view "$TAG" --json assets --jq '.assets[].name')" || {
  echo "::error::公開後assetの一覧を取得できませんでした。" >&2
  exit 1
}
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  if [[ "$keep_assets" != *" $name "* ]]; then
    gh release delete-asset "$TAG" "$name" --yes
  fi
done <<< "$asset_names"

# 新規・再開Draftは全assetの公開後だけ一般公開する。
# Why not 通常リリースへ戻すか: アプリ本体の releases/latest を隠さないため。
gh release edit "$TAG" --prerelease --draft=false
