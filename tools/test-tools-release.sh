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
  case "$name" in
    jpegoptim)
      cat > "$FIXTURE/tools/$relative" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
  echo 'jpegoptim v1.5.6'
  exit 0
fi
destination=''
while (($#)); do
  if [[ "$1" == -d ]]; then
    destination="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "$destination" ]]
mkdir -p "$destination"
printf 'fixture jpeg\n' > "$destination/sample.jpg"
EOF
      ;;
    pngoptim)
      cat > "$FIXTURE/tools/$relative" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
  echo 'pngoptim 0.6.3'
  exit 0
fi
destination=''
while (($#)); do
  if [[ "$1" == -o ]]; then
    destination="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "$destination" ]]
printf 'fixture png\n' > "$destination"
EOF
      ;;
    libwebp)
      cat > "$FIXTURE/tools/$relative" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == -version ]]; then
  echo '1.6.0'
  exit 0
fi
destination=''
while (($#)); do
  if [[ "$1" == -o ]]; then
    destination="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "$destination" ]]
printf 'fixture webp\n' > "$destination"
EOF
      ;;
    *) printf 'fixture %s\n' "$name" > "$FIXTURE/tools/$relative" ;;
  esac
  chmod +x "$FIXTURE/tools/$relative"
done
mkdir -p "$FIXTURE/tools/upscal/models" "$FIXTURE/tools/realcugan/models-se"
printf 'fixture upscal param\n' > "$FIXTURE/tools/upscal/models/model.param"
printf 'fixture upscal bin\n' > "$FIXTURE/tools/upscal/models/model.bin"
printf 'fixture realcugan param\n' > "$FIXTURE/tools/realcugan/models-se/model.param"
printf 'fixture realcugan bin\n' > "$FIXTURE/tools/realcugan/models-se/model.bin"
printf 'fixture dylib\n' > "$FIXTURE/tools/libjxl/bin/macos/libjxl.dylib"
for name in upscal realcugan libjxl libavif; do
  printf 'fixture license %s\n' "$name" > "$FIXTURE/tools/$name/LICENSE"
done
printf 'fixture upscal readme\n' > "$FIXTURE/tools/upscal/README.md"
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
        assert all(item.date_time == (1980, 1, 1, 0, 0, 0) for item in zip_file.infolist()), archive
        binary = next(item for item in zip_file.infolist() if item.filename.rsplit("/", 1)[-1] in {"upscayl-bin", "jpegoptim", "pngoptim", "cjxl", "avifenc", "cwebp", "realcugan-ncnn-vulkan"})
        assert (binary.external_attr >> 16) & 0o111, archive
PY
unzip -q "$DIST/tools-jpegoptim-v1.5.6.zip" -d "$WORK_DIR/unzipped"
[[ -x "$WORK_DIR/unzipped/jpegoptim/bin/macos/jpegoptim" ]] || fail 'ZIP展開後に実行権が失われています'

# 再実行時に古いツールZIPが残らず、mtimeが変わってもZIPの内容が変わらない。
python3 - "$DIST" "$WORK_DIR/first-hashes.json" <<'PY'
import hashlib
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(out.iterdir()) if path.is_file()}
pathlib.Path(sys.argv[2]).write_text(json.dumps(hashes, sort_keys=True), encoding="utf-8")
PY
touch "$DIST/tools-old-v0.zip"
find "$FIXTURE/tools" -exec touch -t 203001020304.05 {} +
"$SCRIPT_DIR/build-tools-release.sh" "$DIST" >/dev/null
[[ ! -e "$DIST/tools-old-v0.zip" ]] || fail '古いツールZIPが削除されていません'
python3 - "$DIST" "$WORK_DIR/first-hashes.json" <<'PY'
import hashlib
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
expected = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
actual = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(out.iterdir()) if path.is_file()}
assert actual == expected, "mtime変更後に成果物のハッシュが変わりました"
PY

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
failure="${MOCK_CURL_FAIL_SUBSTRING:-}"
if [[ -n "$failure" && "$url" == *"$failure"* ]]; then
  exit 22
fi
case "$url" in
  *api.github.com/repos/upscayl/upscayl-ncnn/releases/latest)
    cp "$MOCK_UPSCAL_LATEST" "$output"
    ;;
  *api.github.com/repos/nihui/realcugan-ncnn-vulkan/releases/latest)
    cp "$MOCK_REALCUGAN_LATEST" "$output"
    ;;
  *api.github.com/repos/tjko/jpegoptim/releases/latest)
    cp "$MOCK_JPEGOPTIM_LATEST" "$output"
    ;;
  *api.github.com/repos/okooo5km/pngoptim/releases/latest)
    cp "$MOCK_PNGOPTIM_LATEST" "$output"
    ;;
  *api.github.com/repos/libjxl/libjxl/releases/latest)
    cp "$MOCK_LIBJXL_LATEST" "$output"
    ;;
  *api.github.com/repos/AOMediaCodec/libavif/releases/latest)
    cp "$MOCK_LIBAVIF_LATEST" "$output"
    ;;
  *api.github.com/repos/example/repo*)
    printf '%s' "$MOCK_RELEASE_STATUS"
    if [[ "$MOCK_RELEASE_STATUS" == 200 ]]; then
      cp "$MOCK_RELEASE_JSON" "$output"
    fi
    ;;
  *storage.googleapis.com/downloads.webmproject.org/releases/webp/index.html)
    cp "$MOCK_LIBWEBP_INDEX" "$output"
    ;;
  *tools-info.json)
    cp "$MOCK_MANIFEST" "$output"
    ;;
  *)
    cp "$MOCK_ASSET_DIR/${url##*/}" "$output"
    ;;
esac
EOF
chmod +x "$WORK_DIR/bin/curl"

python3 - "$DIST" "$WORK_DIR/release.json" <<'PY'
import hashlib
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
manifest = json.loads((out / "tools-info.json").read_text(encoding="utf-8"))
assets = [{"name": path.name} for path in sorted(out.iterdir()) if path.is_file()]
for asset in assets:
    path = out / asset["name"]
    asset["digest"] = f"sha256:{hashlib.sha256(path.read_bytes()).hexdigest()}"
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
printf '{"tag_name":"20251207-174704"}\n' > "$WORK_DIR/upscal-latest.json"
printf '{"tag_name":"20220728"}\n' > "$WORK_DIR/realcugan-latest.json"
printf '{"tag_name":"v1.5.6"}\n' > "$WORK_DIR/jpegoptim-latest.json"
printf '{"tag_name":"v0.6.3"}\n' > "$WORK_DIR/pngoptim-latest.json"
printf '{"tag_name":"v0.13.0"}\n' > "$WORK_DIR/libjxl-latest.json"
printf '{"tag_name":"v1.4.2"}\n' > "$WORK_DIR/libavif-latest.json"
printf 'libwebp-1.6.0-mac-arm64.tar.gz\n' > "$WORK_DIR/libwebp-index.html"
export MOCK_UPSCAL_LATEST="$WORK_DIR/upscal-latest.json"
export MOCK_REALCUGAN_LATEST="$WORK_DIR/realcugan-latest.json"
export MOCK_JPEGOPTIM_LATEST="$WORK_DIR/jpegoptim-latest.json"
export MOCK_PNGOPTIM_LATEST="$WORK_DIR/pngoptim-latest.json"
export MOCK_LIBJXL_LATEST="$WORK_DIR/libjxl-latest.json"
export MOCK_LIBAVIF_LATEST="$WORK_DIR/libavif-latest.json"
export MOCK_LIBWEBP_INDEX="$WORK_DIR/libwebp-index.html"
export PATH="$WORK_DIR/bin:$PATH"
export REPOSITORY='example/repo'
export FORCE=false

GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" >/dev/null
grep -q '^changed=false$' "$WORK_DIR/output" || fail '同一バージョンで再公開しようとしています'
grep -q '^changed_tools=$' "$WORK_DIR/output" || fail '更新なしで更新対象を出力しています'
grep -q '^upscal_version=upscayl-bin-20251207-174704$' "$WORK_DIR/output" || fail 'upscal の上流バージョンを解決できていません'
grep -q '^libwebp_version=1.6.0$' "$WORK_DIR/output" || fail 'libwebp の上流バージョンを解決できていません'

printf 'v9.9.9\n' > "$FIXTURE/tools/libjxl/.version"
printf '{"tag_name":"v9.9.9"}\n' > "$MOCK_LIBJXL_LATEST"
: > "$WORK_DIR/output"
GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" >/dev/null
grep -q '^changed=true$' "$WORK_DIR/output" || fail 'ツール更新を検出できていません'
grep -q '^changed_tools=libjxl$' "$WORK_DIR/output" || fail '更新対象をlibjxlだけに絞れていません'
grep -q '^libjxl_version=v9.9.9$' "$WORK_DIR/output" || fail '解決した上流バージョンを出力できていません'
printf 'v0.13.0\n' > "$FIXTURE/tools/libjxl/.version"
printf '{"tag_name":"v0.13.0"}\n' > "$MOCK_LIBJXL_LATEST"

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
grep -q '^changed_tools=upscal,jpegoptim,pngoptim,libjxl,libavif,libwebp,realcugan$' "$WORK_DIR/output" || fail '欠落manifestの再作成対象が不正です'
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
grep -q '^changed_tools=upscal,jpegoptim,pngoptim,libjxl,libavif,libwebp,realcugan$' "$WORK_DIR/output" || fail '未公開Releaseの再作成対象が不正です'

export MOCK_RELEASE_STATUS=200
printf '{}\n' > "$WORK_DIR/broken.json"
export MOCK_MANIFEST="$WORK_DIR/broken.json"
expect_failure env GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" >/dev/null
export MOCK_MANIFEST="$DIST/tools-info.json"

# 上流APIの失敗を更新なしとして扱わない。
: > "$WORK_DIR/output"
if MOCK_CURL_FAIL_SUBSTRING='api.github.com/repos/libjxl/libjxl/releases/latest' \
  GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" \
  > "$WORK_DIR/upstream-error.log" 2>&1; then
  fail '上流APIの失敗時に正常終了しています'
fi
grep -q 'libjxl の最新バージョンを解決できませんでした' "$WORK_DIR/upstream-error.log" \
  || fail '上流APIの失敗理由が出力されていません'
[[ ! -s "$WORK_DIR/output" ]] || fail '上流APIの失敗時に更新判定を出力しています'

# Release asset と manifest の checksum 不一致を更新なしとして扱わない。
python3 - "$MOCK_RELEASE_JSON" "$WORK_DIR/release-bad-digest.json" <<'PY'
import json
import pathlib
import sys

release = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
asset = next(asset for asset in release["assets"] if asset["name"].endswith(".zip"))
asset["digest"] = "sha256:" + "0" * 64
pathlib.Path(sys.argv[2]).write_text(json.dumps(release), encoding="utf-8")
PY
export MOCK_RELEASE_JSON="$WORK_DIR/release-bad-digest.json"
: > "$WORK_DIR/output"
if GITHUB_OUTPUT="$WORK_DIR/output" "$SCRIPT_DIR/preflight-tools-release.sh" \
  > "$WORK_DIR/digest-error.log" 2>&1; then
  fail 'Release assetのchecksum不一致時に正常終了しています'
fi
grep -q 'SHA-256 が一致しません' "$WORK_DIR/digest-error.log" || fail 'checksum不一致の理由が出力されていません'
[[ ! -s "$WORK_DIR/output" ]] || fail 'checksum不一致時に更新判定を出力しています'
export MOCK_RELEASE_JSON="$WORK_DIR/release.json"

# publish 用の gh モック。
cat > "$WORK_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_GH_LOG"
if [[ "$1" == api ]]; then
  if [[ "$ASSET_NAME" == realcugan-ncnn-vulkan-20220728-macos.zip ]]; then
    exit 0
  fi
  digest="$(shasum -a 256 "$MOCK_ASSET_DIR/$ASSET_NAME" | awk '{print $1}')"
  printf 'sha256:%s\n' "$digest"
  exit 0
fi
release_exists="${MOCK_RELEASE_EXISTS}"
if [[ -f "$MOCK_RELEASE_STATE" ]]; then
  release_exists="$(cat "$MOCK_RELEASE_STATE")"
fi
if [[ "$1 $2" == 'release download' ]]; then
  destination="${!#}"
  mkdir -p "$destination"
  cp "$MOCK_REMOTE_MANIFEST" "$destination/tools-info.json"
  exit 0
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
cat > "$WORK_DIR/bin/lipo" <<'EOF'
#!/usr/bin/env bash
printf 'arm64\n'
EOF
chmod +x "$WORK_DIR/bin/lipo"
cat > "$WORK_DIR/bin/otool" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -l ]]; then
  printf 'cmd LC_BUILD_VERSION\nminos %s\n' "${MOCK_OTOOL_MINOS:-26.0}"
else
  printf '%s:\n\t/usr/lib/libSystem.B.dylib\n' "${2:-fixture}"
fi
EOF
chmod +x "$WORK_DIR/bin/otool"
export GH_TOKEN='test-token'
export MOCK_GH_LOG="$WORK_DIR/gh.log"
export MOCK_RELEASE_EXISTS=true
export MOCK_RELEASE_STATE="$WORK_DIR/release-exists"
printf 'stale.zip\t\n' > "$WORK_DIR/remote-assets.tsv"
export MOCK_REMOTE_ASSETS="$WORK_DIR/remote-assets.tsv"
export MOCK_REMOTE_MANIFEST="$DIST/tools-info.json"

# 上流assetのfixtureを作り、取得からZIP生成までネットワークなしで検証する。
ASSET_DIR="$WORK_DIR/upstream-assets"
UPSTREAM_ROOT="$WORK_DIR/upstream"
mkdir -p "$ASSET_DIR" "$UPSTREAM_ROOT"
upscal_package="$UPSTREAM_ROOT/upscayl-bin-20251207-174704-macos"
mkdir -p "$upscal_package"
cp "$FIXTURE/tools/upscal/bin/upscayl-bin" "$upscal_package/upscayl-bin"
cp "$FIXTURE/tools/upscal/LICENSE" "$upscal_package/LICENSE"
cp "$FIXTURE/tools/upscal/README.md" "$upscal_package/README.md"
(cd "$UPSTREAM_ROOT" && zip -qr "$ASSET_DIR/upscayl-bin-20251207-174704-macos.zip" 'upscayl-bin-20251207-174704-macos')
realcugan_package="$UPSTREAM_ROOT/realcugan-ncnn-vulkan-20220728-macos"
mkdir -p "$realcugan_package"
cp "$FIXTURE/tools/realcugan/bin/macos/realcugan-ncnn-vulkan" "$realcugan_package/realcugan-ncnn-vulkan"
cp -R "$FIXTURE/tools/realcugan/models-se" "$realcugan_package/models-se"
cp "$FIXTURE/tools/realcugan/LICENSE" "$realcugan_package/LICENSE"
(cd "$UPSTREAM_ROOT" && zip -qr "$ASSET_DIR/realcugan-ncnn-vulkan-20220728-macos.zip" 'realcugan-ncnn-vulkan-20220728-macos')
jpegoptim_package="$UPSTREAM_ROOT/jpegoptim"
mkdir -p "$jpegoptim_package"
cp "$FIXTURE/tools/jpegoptim/bin/macos/jpegoptim" "$jpegoptim_package/jpegoptim"
(cd "$UPSTREAM_ROOT" && zip -qr "$ASSET_DIR/jpegoptim-1.5.6-x64-osx.zip" jpegoptim)
pngoptim_package="$UPSTREAM_ROOT/pngoptim"
mkdir -p "$pngoptim_package"
cp "$FIXTURE/tools/pngoptim/bin/macos/pngoptim" "$pngoptim_package/pngoptim"
tar -czf "$ASSET_DIR/pngoptim_0.6.3_darwin_universal.tar.gz" -C "$pngoptim_package" .
libwebp_package="$UPSTREAM_ROOT/libwebp"
mkdir -p "$libwebp_package/bin"
cp "$FIXTURE/tools/libwebp/bin/macos/cwebp" "$libwebp_package/bin/cwebp"
tar -czf "$ASSET_DIR/libwebp-1.6.0-mac-arm64.tar.gz" -C "$libwebp_package" .
export MOCK_ASSET_DIR="$ASSET_DIR"
FETCHED_TOOLS="$WORK_DIR/fetched-tools"
env REPO_ROOT="$SCRIPT_DIR/.." \
  UPSCAL_VERSION=upscayl-bin-20251207-174704 \
  REALCUGAN_VERSION=realcugan-ncnn-vulkan-20220728 \
  JPEGOPTIM_VERSION=v1.5.6 PNGOPTIM_VERSION=v0.6.3 \
  LIBJXL_VERSION=v0.13.0 LIBAVIF_VERSION=v1.4.2 LIBWEBP_VERSION=1.6.0 \
  "$SCRIPT_DIR/fetch-tools-release.sh" "$FETCHED_TOOLS" >/dev/null
for name in upscal jpegoptim pngoptim libjxl libavif libwebp realcugan; do
  [[ -s "$FETCHED_TOOLS/$name/.version" ]] || fail "$name の取得結果にバージョンがありません"
done
PARTIAL_FETCHED_TOOLS="$WORK_DIR/partial-fetched-tools"
env REPO_ROOT="$SCRIPT_DIR/.." CHANGED_TOOLS=jpegoptim \
  UPSCAL_VERSION=upscayl-bin-20251207-174704 \
  REALCUGAN_VERSION=realcugan-ncnn-vulkan-20220728 \
  JPEGOPTIM_VERSION=v1.5.6 PNGOPTIM_VERSION=v0.6.3 \
  LIBJXL_VERSION=v0.13.0 LIBAVIF_VERSION=v1.4.2 LIBWEBP_VERSION=1.6.0 \
  "$SCRIPT_DIR/fetch-tools-release.sh" "$PARTIAL_FETCHED_TOOLS" >/dev/null
[[ -s "$PARTIAL_FETCHED_TOOLS/jpegoptim/.version" ]] || fail '変更対象ツールを取得できていません'
[[ ! -e "$PARTIAL_FETCHED_TOOLS/libjxl" && ! -e "$PARTIAL_FETCHED_TOOLS/libavif" ]] \
  || fail '変更されていないソースビルドツールを取得しています'
if MOCK_OTOOL_MINOS=27.2 env REPO_ROOT="$SCRIPT_DIR/.." CHANGED_TOOLS=jpegoptim \
  UPSCAL_VERSION=upscayl-bin-20251207-174704 \
  REALCUGAN_VERSION=realcugan-ncnn-vulkan-20220728 \
  JPEGOPTIM_VERSION=v1.5.6 PNGOPTIM_VERSION=v0.6.3 \
  LIBJXL_VERSION=v0.13.0 LIBAVIF_VERSION=v1.4.2 LIBWEBP_VERSION=1.6.0 \
  "$SCRIPT_DIR/fetch-tools-release.sh" "$WORK_DIR/incompatible-tools" \
  > "$WORK_DIR/incompatible.log" 2>&1; then
  fail 'deployment target 超過時に正常終了しています'
fi
grep -q 'macOS 26.0 を超えています' "$WORK_DIR/incompatible.log" || fail 'deployment target 超過の理由が出力されていません'
TOOLS_ROOT="$FETCHED_TOOLS" "$SCRIPT_DIR/build-tools-release.sh" "$WORK_DIR/fetched-dist" >/dev/null
python3 - "$WORK_DIR/fetched-dist" <<'PY'
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
data = json.loads((out / "tools-info.json").read_text(encoding="utf-8"))
assert [entry["name"] for entry in data["tools"]] == [
    "upscal", "jpegoptim", "pngoptim", "libjxl", "libavif", "libwebp", "realcugan"
]
assert len(list(out.glob("tools-*.zip"))) == 7
PY

# 変更されたツールだけをZIP化し、同版ツールは既存manifestから引き継ぐ。
PARTIAL_DIST="$WORK_DIR/partial-dist"
CHANGED_TOOLS=jpegoptim REMOTE_MANIFEST="$DIST/tools-info.json" \
  "$SCRIPT_DIR/build-tools-release.sh" "$PARTIAL_DIST" >/dev/null
python3 - "$DIST" "$PARTIAL_DIST" <<'PY'
import json
import pathlib
import sys

remote = json.loads((pathlib.Path(sys.argv[1]) / "tools-info.json").read_text(encoding="utf-8"))
partial = json.loads((pathlib.Path(sys.argv[2]) / "tools-info.json").read_text(encoding="utf-8"))
assert partial == remote
assert len(list(pathlib.Path(sys.argv[2]).glob("tools-*.zip"))) == 1
assert len((pathlib.Path(sys.argv[2]) / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines()) == 8
PY

: > "$MOCK_GH_LOG"
"$SCRIPT_DIR/publish-tools-release.sh" "$DIST" >/dev/null
grep -q '^release edit tools-latest --prerelease --draft=false$' "$MOCK_GH_LOG" || fail '事前リリースを維持していません'
grep -q '^release delete-asset tools-latest stale.zip --yes$' "$MOCK_GH_LOG" || fail '古い資産を削除していません'
manifest_line="$(grep -n 'release upload tools-latest .*tools-info.json' "$MOCK_GH_LOG" | cut -d: -f1)"
zip_line="$(grep -n 'release upload tools-latest .*tools-.*\.zip' "$MOCK_GH_LOG" | tail -n1 | cut -d: -f1)"
[[ "$manifest_line" -gt "$zip_line" ]] || fail 'manifestをZIPより先に公開しています'

# 部分更新でも、ローカルにない同版assetを削除しない。
python3 - "$DIST" "$WORK_DIR/partial-remote-assets.tsv" <<'PY'
import hashlib
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
lines = [f"{path.name}\tsha256:{hashlib.sha256(path.read_bytes()).hexdigest()}" for path in sorted(out.iterdir()) if path.is_file()]
lines.append("stale.zip\t")
pathlib.Path(sys.argv[2]).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
export MOCK_REMOTE_ASSETS="$WORK_DIR/partial-remote-assets.tsv"
: > "$MOCK_GH_LOG"
"$SCRIPT_DIR/publish-tools-release.sh" "$PARTIAL_DIST" >/dev/null
if grep -q '^release delete-asset tools-latest tools-' "$MOCK_GH_LOG"; then
  fail '部分更新で同版assetを削除しています'
fi
grep -q '^release delete-asset tools-latest stale.zip --yes$' "$MOCK_GH_LOG" || fail '部分更新で古い資産を削除できていません'
printf 'stale.zip\t\n' > "$MOCK_REMOTE_ASSETS"

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

# 同版assetは既存manifestと一致するremote checksumを再利用する。
REUSE_DIST="$WORK_DIR/reuse-dist"
cp -R "$DIST" "$REUSE_DIST"
python3 - "$REUSE_DIST/tools-info.json" "$WORK_DIR/reuse-remote-manifest.json" "$same_name" <<'PY'
import json
import pathlib
import sys

source, destination, filename = sys.argv[1:]
data = json.loads(pathlib.Path(source).read_text(encoding="utf-8"))
for entry in data["tools"]:
    if pathlib.PurePosixPath(entry["url"]).name == filename:
        entry["sha256"] = "0" * 64
pathlib.Path(destination).write_text(json.dumps(data), encoding="utf-8")
PY
export MOCK_REMOTE_MANIFEST="$WORK_DIR/reuse-remote-manifest.json"
: > "$MOCK_GH_LOG"
publish_output="$("$SCRIPT_DIR/publish-tools-release.sh" "$REUSE_DIST")"
grep -q "Reuse unchanged version asset: $same_name" <<< "$publish_output" || fail '同版assetを再利用できていません'
if grep -q "release upload tools-latest .*$same_name" "$MOCK_GH_LOG"; then
  fail '再利用した同版assetを再アップロードしています'
fi
python3 - "$REUSE_DIST/tools-info.json" "$REUSE_DIST/SHA256SUMS.txt" "$same_name" <<'PY'
import json
import pathlib
import sys

manifest_path, checksums_path, filename = sys.argv[1:]
data = json.loads(pathlib.Path(manifest_path).read_text(encoding="utf-8"))
entry = next(entry for entry in data["tools"] if pathlib.PurePosixPath(entry["url"]).name == filename)
assert entry["sha256"] == "0" * 64
line = next(line for line in pathlib.Path(checksums_path).read_text(encoding="utf-8").splitlines() if line.endswith(f"  {filename}"))
assert line.startswith("0" * 64)
PY
export MOCK_REMOTE_MANIFEST="$DIST/tools-info.json"

# force を明示した場合だけ、同名assetの内容差を上書きして復旧する。
: > "$MOCK_GH_LOG"
FORCE=true "$SCRIPT_DIR/publish-tools-release.sh" "$DIST" >/dev/null
grep -q "^release upload tools-latest .*$same_name --clobber$" "$MOCK_GH_LOG" || fail 'force で異なる内容のassetを上書きできていません'
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

# 必須ツールが欠けたmanifestは公開しない。
INCOMPLETE_DIST="$WORK_DIR/incomplete-dist"
cp -R "$DIST" "$INCOMPLETE_DIST"
python3 - "$INCOMPLETE_DIST/tools-info.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["tools"].pop()
path.write_text(json.dumps(data), encoding="utf-8")
PY
: > "$MOCK_GH_LOG"
expect_failure "$SCRIPT_DIR/publish-tools-release.sh" "$INCOMPLETE_DIST" >/dev/null
[[ ! -s "$MOCK_GH_LOG" ]] || fail '不完全manifestの検証前に gh を呼び出しています'

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
