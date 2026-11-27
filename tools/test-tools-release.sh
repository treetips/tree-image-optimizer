#!/usr/bin/env bash
# tools-release スクリプトを、小さな fixture とモックで検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() {
  echo "::error::$*" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "コマンドは失敗するはずです: $*"
  fi
}

FIXTURE="$WORK_DIR/repo"
DIST="$WORK_DIR/dist"
mkdir -p "$FIXTURE/tools" "$FIXTURE/TreeImageOptimizer/TreeImageOptimizer/Core" "$WORK_DIR/bin"

for name in upscal jpegoptim pngoptim libjxl libavif libwebp realcugan; do
  case "$name" in
    upscal) relative='upscal/bin/upscayl-bin' ;;
    jpegoptim) relative='jpegoptim/bin/macos/jpegoptim' ;;
    pngoptim) relative='pngoptim/bin/macos/pngoptim' ;;
    libjxl) relative='libjxl/bin/macos/cjxl' ;;
    libavif) relative='libavif/bin/macos/avifenc' ;;
    libwebp) relative='libwebp/bin/macos/cwebp' ;;
    realcugan) relative='realcugan/bin/macos/realcugan-ncnn-vulkan' ;;
  esac
  mkdir -p "$FIXTURE/tools/$(dirname "$relative")"
  printf 'fixture %s\n' "$name" > "$FIXTURE/tools/$relative"
done
mkdir -p "$FIXTURE/tools/upscal/models" "$FIXTURE/tools/realcugan/models-se"
printf 'fixture upscal param\n' > "$FIXTURE/tools/upscal/models/model.param"
printf 'fixture upscal bin\n' > "$FIXTURE/tools/upscal/models/model.bin"
printf 'fixture realcugan param\n' > "$FIXTURE/tools/realcugan/models-se/model.param"
printf 'fixture realcugan bin\n' > "$FIXTURE/tools/realcugan/models-se/model.bin"
printf 'fixture dylib\n' > "$FIXTURE/tools/libjxl/bin/macos/libjxl.dylib"
printf 'upscayl-bin-20251207-174704\n' > "$FIXTURE/tools/upscal/.version"
printf 'realcugan-ncnn-vulkan-20220728\n' > "$FIXTURE/tools/realcugan/.version"
printf 'v0.13.0\n' > "$FIXTURE/tools/libjxl/.version"
printf 'v1.4.2\n' > "$FIXTURE/tools/libavif/.version"
cat > "$FIXTURE/TreeImageOptimizer/TreeImageOptimizer/Core/AppInfo.swift" <<'EOF'
enum AppInfo {
    static let jpegVersion = "v1.5.6"
    static let pngVersion = "v0.6.3"
    static let webpVersion = "1.6.0"
}
EOF

export REPO_ROOT="$FIXTURE"
export TOOLS_ROOT="$FIXTURE/tools"
export APPINFO_PATH="$FIXTURE/TreeImageOptimizer/TreeImageOptimizer/Core/AppInfo.swift"
export REPO_URL='https://github.com/example/repo'
export TAG='tools-latest'

# 7ツールのZIP・manifest・チェックサムが生成される。
"$SCRIPT_DIR/build-tools-release.sh" "$DIST"
python3 - "$DIST" "$REPO_URL" "$TAG" <<'PY'
import hashlib
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
repo_url, tag = sys.argv[2:]
data = json.loads((out / "tools-info.json").read_text(encoding="utf-8"))
assert data["schemaVersion"] == 1
assert [entry["name"] for entry in data["tools"]] == [
    "upscal", "jpegoptim", "pngoptim", "libjxl", "libavif", "libwebp", "realcugan"
]
for entry in data["tools"]:
    asset = out / f"tools-{entry['name']}-{entry['version']}.zip"
    assert asset.is_file(), asset
    assert hashlib.sha256(asset.read_bytes()).hexdigest() == entry["sha256"]
    assert entry["url"] == f"{repo_url}/releases/download/{tag}/{asset.name}"
    assert entry["required"] is True
assert len(list(out.glob("tools-*.zip"))) == 7
PY
(
  cd "$DIST"
  shasum -a 256 -c SHA256SUMS.txt >/dev/null
)
python3 - "$DIST" <<'PY'
import pathlib
import sys
import zipfile

out = pathlib.Path(sys.argv[1])
for archive in out.glob("tools-*.zip"):
    name = archive.name.removeprefix("tools-").split("-", 1)[0]
    with zipfile.ZipFile(archive) as zip_file:
        assert zip_file.namelist(), archive
        assert all(path.startswith(f"{name}/") for path in zip_file.namelist()), archive
PY

# 再実行時に古いツールZIPが残らない。
touch "$DIST/tools-old-v0.zip"
"$SCRIPT_DIR/build-tools-release.sh" "$DIST" >/dev/null
[[ ! -e "$DIST/tools-old-v0.zip" ]] || fail '古いツールZIPが削除されていません'

# preflight 用の curl モック。
cat > "$WORK_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=''
url=''
while (($#)); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  *api.github.com*)
    printf '%s' "$MOCK_RELEASE_STATUS"
    if [[ "$MOCK_RELEASE_STATUS" == 200 ]]; then
      cp "$MOCK_RELEASE_JSON" "$output"
    fi
    ;;
  *tools-info.json)
    cp "$MOCK_MANIFEST" "$output"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$WORK_DIR/bin/curl"

python3 - "$DIST" "$WORK_DIR/release.json" <<'PY'
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
manifest = json.loads((out / "tools-info.json").read_text(encoding="utf-8"))
assets = [{"name": path.name} for path in sorted(out.iterdir()) if path.is_file()]
for asset in assets:
    if asset["name"] == "tools-info.json":
        asset["browser_download_url"] = "https://github.com/example/repo/releases/download/tools-latest/tools-info.json"
pathlib.Path(sys.argv[2]).write_text(
    json.dumps({"assets": assets, "prerelease": True, "draft": False}),
    encoding="utf-8",
)
PY

export MOCK_RELEASE_JSON="$WORK_DIR/release.json"
export MOCK_MANIFEST="$DIST/tools-info.json"
export MOCK_RELEASE_STATUS=200
export PATH="$WORK_DIR/bin:$PATH"
export REPOSITORY='example/repo'
export FORCE=false

GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" >/dev/null
grep -q '^changed=false$' "$WORK_DIR/output" || fail '同一バージョンで再公開しようとしています'

printf 'v9.9.9\n' > "$FIXTURE/tools/libjxl/.version"
: > "$WORK_DIR/output"
GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" >/dev/null
grep -q '^changed=true$' "$WORK_DIR/output" || fail 'ツール更新を検出できていません'
printf 'v0.13.0\n' > "$FIXTURE/tools/libjxl/.version"

# manifest が無い部分公開状態なら、Force なしで再作成する。
python3 - "$WORK_DIR/release.json" "$WORK_DIR/release-without-manifest.json" <<'PY'
import json
import pathlib
import sys

release = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
release["assets"] = [asset for asset in release["assets"] if asset["name"] != "tools-info.json"]
pathlib.Path(sys.argv[2]).write_text(json.dumps(release), encoding="utf-8")
PY
export MOCK_RELEASE_JSON="$WORK_DIR/release-without-manifest.json"
: > "$WORK_DIR/output"
GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" >/dev/null
grep -q '^changed=true$' "$WORK_DIR/output" || fail '欠落manifestを再作成できません'
export MOCK_RELEASE_JSON="$WORK_DIR/release.json"

# 別ホストのURLを更新なしと誤認しない。
python3 - "$DIST/tools-info.json" "$WORK_DIR/wrong-host.json" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
manifest["tools"][0]["url"] = "https://example.com/releases/download/tools-latest/tools-upscal-v1.zip"
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest), encoding="utf-8")
PY
export MOCK_MANIFEST="$WORK_DIR/wrong-host.json"
expect_failure env GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" >/dev/null
export MOCK_MANIFEST="$DIST/tools-info.json"

export MOCK_RELEASE_STATUS=404
: > "$WORK_DIR/output"
GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" >/dev/null
grep -q '^changed=true$' "$WORK_DIR/output" || fail '未公開Releaseを更新ありと判定できていません'

export MOCK_RELEASE_STATUS=200
printf '{}\n' > "$WORK_DIR/broken.json"
export MOCK_MANIFEST="$WORK_DIR/broken.json"
expect_failure env GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" >/dev/null
export MOCK_MANIFEST="$DIST/tools-info.json"

# publish 用の gh モック。
cat > "$WORK_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_GH_LOG"
release_exists="${MOCK_RELEASE_EXISTS}"
if [[ -f "$MOCK_RELEASE_STATE" ]]; then
  release_exists="$(cat "$MOCK_RELEASE_STATE")"
fi
if [[ "$1 $2" == 'release view' ]]; then
  if [[ "$*" == *'--json'* && "$release_exists" != true ]]; then
    exit 1
  fi
  if [[ "$*" == *'--json isDraft'* ]]; then
    printf '%s\n' "${MOCK_RELEASE_DRAFT:-false}"
    exit 0
  fi
  if [[ "$*" == *'--json assets'* ]]; then
    if [[ "$*" == *'@tsv'* ]]; then
      cat "$MOCK_REMOTE_ASSETS"
    else
      cut -f1 "$MOCK_REMOTE_ASSETS"
    fi
    exit 0
  fi
  [[ "$release_exists" == true ]]
  exit
fi
if [[ "$1 $2" == 'release create' ]]; then
  printf 'true\n' > "$MOCK_RELEASE_STATE"
  exit 0
fi
EOF
chmod +x "$WORK_DIR/bin/gh"
export GH_TOKEN='test-token'
export MOCK_GH_LOG="$WORK_DIR/gh.log"
export MOCK_RELEASE_EXISTS=true
export MOCK_RELEASE_STATE="$WORK_DIR/release-exists"
printf 'stale.zip\t\n' > "$WORK_DIR/remote-assets.tsv"
export MOCK_REMOTE_ASSETS="$WORK_DIR/remote-assets.tsv"
: > "$MOCK_GH_LOG"
"$SCRIPT_DIR/publish-tools-release.sh" "$DIST" >/dev/null
grep -q '^release edit tools-latest --prerelease --draft=false$' "$MOCK_GH_LOG" || fail '事前リリースを維持していません'
grep -q '^release delete-asset tools-latest stale.zip --yes$' "$MOCK_GH_LOG" || fail '古い資産を削除していません'
manifest_line="$(grep -n 'release upload tools-latest .*tools-info.json' "$MOCK_GH_LOG" | cut -d: -f1)"
zip_line="$(grep -n 'release upload tools-latest .*tools-.*\.zip' "$MOCK_GH_LOG" | tail -n1 | cut -d: -f1)"
[[ "$manifest_line" -gt "$zip_line" ]] || fail 'manifestをZIPより先に公開しています'

# 同一assetはチェックサムが一致した場合だけ再アップロードを省略する。
same_name='tools-libavif-v1.4.2.zip'
same_digest="sha256:$(shasum -a 256 "$DIST/$same_name" | awk '{print $1}')"
printf '%s\t%s\nstale.zip\t\n' "$same_name" "$same_digest" > "$MOCK_REMOTE_ASSETS"
: > "$MOCK_GH_LOG"
publish_output="$("$SCRIPT_DIR/publish-tools-release.sh" "$DIST")"
grep -q "Skip unchanged asset: $same_name" <<< "$publish_output" || fail '同一assetを省略できていません'
if grep -q "release upload tools-latest .*$same_name" "$MOCK_GH_LOG"; then
  fail '同一assetを再アップロードしています'
fi

# 同名でも内容が異なる場合は上書きせず失敗する。
printf '%s\tsha256:%064d\nstale.zip\t\n' "$same_name" 0 > "$MOCK_REMOTE_ASSETS"
: > "$MOCK_GH_LOG"
expect_failure "$SCRIPT_DIR/publish-tools-release.sh" "$DIST" >/dev/null
if grep -q "release upload tools-latest .*$same_name" "$MOCK_GH_LOG"; then
  fail '異なる内容のassetを上書きしようとしています'
fi
printf 'stale.zip\t\n' > "$MOCK_REMOTE_ASSETS"

export MOCK_RELEASE_EXISTS=false
rm -f "$MOCK_RELEASE_STATE"
: > "$MOCK_GH_LOG"
"$SCRIPT_DIR/publish-tools-release.sh" "$DIST" >/dev/null
grep -q '^release create tools-latest .*--prerelease --draft$' "$MOCK_GH_LOG" || fail '新規Releaseを事前ReleaseのDraftとして作成していません'

# チェックサム不一致の成果物は公開しない。
printf 'broken\n' >> "$DIST/tools-upscal-upscayl-bin-20251207-174704.zip"
: > "$MOCK_GH_LOG"
expect_failure "$SCRIPT_DIR/publish-tools-release.sh" "$DIST" >/dev/null
[[ ! -s "$MOCK_GH_LOG" ]] || fail '検証前に gh を呼び出しています'

# モデルや dylib が欠けた配布物は公開しない。
rm "$FIXTURE/tools/upscal/models/model.bin"
expect_failure "$SCRIPT_DIR/build-tools-release.sh" "$WORK_DIR/missing-model-dist" >/dev/null
printf 'fixture upscal bin\n' > "$FIXTURE/tools/upscal/models/model.bin"
rm "$FIXTURE/tools/libjxl/bin/macos/libjxl.dylib"
expect_failure "$SCRIPT_DIR/build-tools-release.sh" "$WORK_DIR/missing-dylib-dist" >/dev/null
printf 'fixture dylib\n' > "$FIXTURE/tools/libjxl/bin/macos/libjxl.dylib"

# LFSポインタを実体と誤認して公開しない。
printf 'version https://git-lfs.github.com/spec/v1\noid sha256:placeholder\nsize 1\n' \
  > "$FIXTURE/tools/upscal/bin/upscayl-bin"
expect_failure "$SCRIPT_DIR/build-tools-release.sh" "$WORK_DIR/lfs-dist" >/dev/null

echo 'tools-release tests passed'
