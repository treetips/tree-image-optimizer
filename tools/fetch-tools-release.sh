#!/usr/bin/env bash
# 解決済みの上流バージョンからツール実体を取得し、配布用の tools ツリーを作る。
#
# 使い方:
#   tools/fetch-tools-release.sh <output-tools-dir>
#
# 環境変数:
#   UPSCAL_VERSION / REALCUGAN_VERSION / JPEGOPTIM_VERSION / PNGOPTIM_VERSION
#   LIBJXL_VERSION / LIBAVIF_VERSION / LIBWEBP_VERSION
#   CHANGED_TOOLS       再生成するツール名（空なら全ツール）
#   GH_TOKEN             GitHub API の認証トークン
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/tools-release-common.sh
source "$SCRIPT_DIR/tools-release-common.sh"

OUT_DIR="${1:?ツール配置先の出力ディレクトリを指定してください}"
UPSCAL_VERSION="${UPSCAL_VERSION:?UPSCAL_VERSION を指定してください}"
REALCUGAN_VERSION="${REALCUGAN_VERSION:?REALCUGAN_VERSION を指定してください}"
JPEGOPTIM_VERSION="${JPEGOPTIM_VERSION:?JPEGOPTIM_VERSION を指定してください}"
PNGOPTIM_VERSION="${PNGOPTIM_VERSION:?PNGOPTIM_VERSION を指定してください}"
LIBJXL_VERSION="${LIBJXL_VERSION:?LIBJXL_VERSION を指定してください}"
LIBAVIF_VERSION="${LIBAVIF_VERSION:?LIBAVIF_VERSION を指定してください}"
LIBWEBP_VERSION="${LIBWEBP_VERSION:?LIBWEBP_VERSION を指定してください}"
GH_TOKEN="${GH_TOKEN:?GitHub 認証トークンを指定してください}"
CHANGED_TOOLS="${CHANGED_TOOLS:-$(IFS=,; echo "${TOOL_NAMES[*]}")}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

[[ ! -e "$OUT_DIR" ]] || fail "ツール配置先が既に存在します。空の新しいパスを指定してください: $OUT_DIR"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
export MACOSX_DEPLOYMENT_TARGET=26.0

python3 - "$UPSCAL_VERSION" "$REALCUGAN_VERSION" "$JPEGOPTIM_VERSION" "$PNGOPTIM_VERSION" \
  "$LIBJXL_VERSION" "$LIBAVIF_VERSION" "$LIBWEBP_VERSION" <<'PY'
import re
import sys

labels = ("upscal", "realcugan", "jpegoptim", "pngoptim", "libjxl", "libavif", "libwebp")
for label, value in zip(labels, sys.argv[1:]):
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", value) is None:
        raise SystemExit(f"{label} のバージョンに不正な文字が含まれています: {value}")
PY

for name in ${CHANGED_TOOLS//,/ }; do
  case " ${TOOL_NAMES[*]} " in
    *" $name "*) ;;
    *) fail "CHANGED_TOOLS に未知のツールがあります: $name" ;;
  esac
done

should_fetch() {
  [[ ",$CHANGED_TOOLS," == *",$1,"* ]]
}

download() {
  local url="$1"
  local destination="$2"
  echo "download: $url"
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 -o "$destination" "$url"
  [[ -s "$destination" ]] || fail "ダウンロードしたファイルが空です: $url"
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || fail "SHA-256 が一致しません: $file"
}

verify_deployment_target() {
  python3 - "$@" <<'PY'
import pathlib
import re
import subprocess
import sys

for raw in sys.argv[1:]:
    path = pathlib.Path(raw)
    output = subprocess.check_output(["otool", "-l", str(path)], text=True)
    matches = re.findall(r"\bminos (\d+)(?:\.(\d+))?(?:\.(\d+))?", output)
    versions = [tuple(int(part or 0) for part in match) for match in matches]
    if not versions:
        raise SystemExit(f"deployment target を確認できません: {path}")
    if any(version > (26, 0, 0) for version in versions):
        raise SystemExit(f"deployment target が macOS 26.0 を超えています: {path} {versions}")
PY
}

github_asset_digest() {
  local repository="$1"
  local tag="$2"
  local asset="$3"
  ASSET_NAME="$asset" gh api "repos/${repository}/releases/tags/${tag}" \
    --jq '.assets[] | select(.name == env.ASSET_NAME) | .digest // ""'
}

download_github_asset() {
  local repository="$1"
  local tag="$2"
  local asset="$3"
  local destination="$4"
  local allow_missing_digest="${5:-false}"
  local digest

  download "https://github.com/${repository}/releases/download/${tag}/${asset}" "$destination"
  digest="$(github_asset_digest "$repository" "$tag" "$asset")"
  if [[ -n "$digest" ]]; then
    [[ "$digest" =~ ^sha256:[0-9a-fA-F]{64}$ ]] || fail "GitHub API の digest が不正です: $asset"
    verify_sha256 "$destination" "${digest#sha256:}"
  else
    [[ "$allow_missing_digest" == true ]] || fail "$asset には GitHub API の digest がありません。"
    echo "::warning::$asset には GitHub API の digest がありません。"
  fi
}

require_single_file() {
  local root="$1"
  local name="$2"
  local -a matches=()
  local file
  while IFS= read -r file; do
    matches+=("$file")
  done < <(find "$root" -type f -name "$name" -print)
  [[ "${#matches[@]}" -eq 1 ]] || fail "$root に $name が1個ありません: ${#matches[@]}個"
  printf '%s\n' "${matches[0]}"
}

require_single_directory() {
  local root="$1"
  local name="$2"
  local -a matches=()
  local directory
  while IFS= read -r directory; do
    matches+=("$directory")
  done < <(find "$root" -type d -name "$name" -print)
  [[ "${#matches[@]}" -eq 1 ]] || fail "$root に $name が1個ありません: ${#matches[@]}個"
  printf '%s\n' "${matches[0]}"
}

write_version() {
  local name="$1"
  local version="$2"
  printf '%s\n' "$version" > "$OUT_DIR/$name/.version"
}

copy_repository_tool() {
  local name="$1"
  cp -R "$TOOLS_ROOT/$name" "$OUT_DIR/$name"
  write_version "$name" "$(tool_version "$name")"
}

repository_source_compatible() {
  local name="$1"
  case "$name" in
    libjxl)
      verify_deployment_target "$OUT_DIR/libjxl/bin/macos/cjxl" \
        "$OUT_DIR"/libjxl/bin/macos/*.dylib 2>/dev/null
      ;;
    libavif)
      verify_deployment_target "$OUT_DIR/libavif/bin/macos/avifenc" 2>/dev/null
      ;;
  esac
}

fetch_upscal() {
  local tag="${UPSCAL_VERSION#upscayl-bin-}"
  local archive="$WORK_DIR/upscal.zip"
  local extracted="$WORK_DIR/upscal"
  local binary destination

  download_github_asset 'upscayl/upscayl-ncnn' "$tag" "upscayl-bin-${tag}-macos.zip" "$archive"
  mkdir -p "$extracted"
  unzip -q "$archive" -d "$extracted"
  binary="$(require_single_file "$extracted" 'upscayl-bin')"
  destination="$OUT_DIR/upscal"
  mkdir -p "$destination/bin"
  cp "$binary" "$destination/bin/upscayl-bin"
  cp "$TOOLS_ROOT/upscal/LICENSE" "$destination/LICENSE"
  cp "$TOOLS_ROOT/upscal/README.md" "$destination/README.md"
  cp -R "$TOOLS_ROOT/upscal/models" "$destination/models"
  chmod +x "$destination/bin/upscayl-bin"
  write_version upscal "$UPSCAL_VERSION"
}

fetch_realcugan() {
  local tag="${REALCUGAN_VERSION#realcugan-ncnn-vulkan-}"
  local archive="$WORK_DIR/realcugan.zip"
  local extracted="$WORK_DIR/realcugan"
  local binary models package_root destination digest

  download_github_asset 'nihui/realcugan-ncnn-vulkan' "$tag" \
    "realcugan-ncnn-vulkan-${tag}-macos.zip" "$archive" true
  digest="$(github_asset_digest 'nihui/realcugan-ncnn-vulkan' "$tag" \
    "realcugan-ncnn-vulkan-${tag}-macos.zip")"
  mkdir -p "$extracted"
  unzip -q "$archive" -d "$extracted"
  binary="$(require_single_file "$extracted" 'realcugan-ncnn-vulkan')"
  models="$(require_single_directory "$extracted" 'models-se')"
  package_root="$(cd "$(dirname "$binary")" && pwd)"
  destination="$OUT_DIR/realcugan"
  mkdir -p "$destination/bin/macos"
  cp "$binary" "$destination/bin/macos/realcugan-ncnn-vulkan"
  cp -R "$models" "$destination/models-se"
  [[ ! -f "$package_root/LICENSE" ]] || cp "$package_root/LICENSE" "$destination/LICENSE"
  chmod +x "$destination/bin/macos/realcugan-ncnn-vulkan"
  write_version realcugan "$REALCUGAN_VERSION"

  # Why not checksum無しの旧assetを無条件で採用しないか: 現行版との一致で検証できない未知の版は公開しないため。
  if [[ -z "$digest" ]]; then
    [[ "$REALCUGAN_VERSION" == "$(tool_version realcugan)" ]] \
      || fail "Real-CUGAN $REALCUGAN_VERSION には checksum がありません。"
    cmp "$destination/bin/macos/realcugan-ncnn-vulkan" \
      "$TOOLS_ROOT/realcugan/bin/macos/realcugan-ncnn-vulkan" \
      || fail "checksum のない Real-CUGAN は現行バイナリと一致しません。"
    diff -r "$destination/models-se" "$TOOLS_ROOT/realcugan/models-se" \
      || fail "checksum のない Real-CUGAN は現行モデルと一致しません。"
  fi
}

fetch_jpegoptim() {
  local tag="$JPEGOPTIM_VERSION"
  local archive="$WORK_DIR/jpegoptim.zip"
  local extracted="$WORK_DIR/jpegoptim"
  local binary destination

  download_github_asset 'tjko/jpegoptim' "$tag" "jpegoptim-${tag#v}-x64-osx.zip" "$archive"
  mkdir -p "$extracted"
  unzip -q "$archive" -d "$extracted"
  binary="$(require_single_file "$extracted" 'jpegoptim')"
  destination="$OUT_DIR/jpegoptim/bin/macos"
  mkdir -p "$destination"
  cp "$binary" "$destination/jpegoptim"
  chmod +x "$destination/jpegoptim"
  write_version jpegoptim "$JPEGOPTIM_VERSION"
}

fetch_pngoptim() {
  local tag="$PNGOPTIM_VERSION"
  local archive="$WORK_DIR/pngoptim.tar.gz"
  local extracted="$WORK_DIR/pngoptim"
  local binary destination

  download_github_asset 'okooo5km/pngoptim' "$tag" \
    "pngoptim_${tag#v}_darwin_universal.tar.gz" "$archive"
  mkdir -p "$extracted"
  tar -xzf "$archive" -C "$extracted"
  binary="$(require_single_file "$extracted" 'pngoptim')"
  destination="$OUT_DIR/pngoptim/bin/macos"
  mkdir -p "$destination"
  cp "$binary" "$destination/pngoptim"
  chmod +x "$destination/pngoptim"
  write_version pngoptim "$PNGOPTIM_VERSION"
}

fetch_libwebp() {
  local archive="$WORK_DIR/libwebp.tar.gz"
  local extracted="$WORK_DIR/libwebp"
  local binary destination

  download "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${LIBWEBP_VERSION}-mac-arm64.tar.gz" "$archive"
  mkdir -p "$extracted"
  tar -xzf "$archive" -C "$extracted"
  binary="$(require_single_file "$extracted" 'cwebp')"
  destination="$OUT_DIR/libwebp/bin/macos"
  mkdir -p "$destination"
  cp "$binary" "$destination/cwebp"
  chmod +x "$destination/cwebp"
  write_version libwebp "$LIBWEBP_VERSION"
}

build_libjxl() {
  local tag="$LIBJXL_VERSION"
  local archive="$WORK_DIR/libjxl.tar.gz"
  local extracted="$WORK_DIR/libjxl-source"
  local source_dir="$extracted/libjxl-${tag#v}"
  local build_dir="$WORK_DIR/libjxl-build"
  local destination="$OUT_DIR/libjxl/bin/macos"
  local binary version_output smoke_dir

  HOMEBREW_NO_AUTO_UPDATE=1 brew install brotli highway lcms2 libpng jpeg-turbo giflib libdeflate zstd openexr imath
  download "https://github.com/libjxl/libjxl/archive/refs/tags/${tag}.tar.gz" "$archive"
  mkdir -p "$extracted"
  tar -xzf "$archive" -C "$extracted"
  [[ -d "$source_dir" ]] || fail "libjxl のソースディレクトリがありません: $source_dir"
  cmake -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
    -DCMAKE_PREFIX_PATH=/opt/homebrew \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DJPEGXL_ENABLE_MANPAGES=OFF \
    -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF \
    -DJPEGXL_ENABLE_SJPEG=OFF \
    -DJPEGXL_ENABLE_VIEWERS=OFF \
    -DJPEGXL_ENABLE_JNI=OFF \
    -DJPEGXL_ENABLE_SKCMS=OFF \
    -DJPEGXL_FORCE_SYSTEM_HWY=ON \
    -DJPEGXL_FORCE_SYSTEM_BROTLI=ON
  cmake --build "$build_dir" --target cjxl --parallel 3
  binary="$(require_single_file "$build_dir" 'cjxl')"
  mkdir -p "$destination"
  cp "$source_dir/LICENSE" "$OUT_DIR/libjxl/LICENSE"

  python3 - "$binary" "$build_dir" "$destination" <<'PY'
import hashlib
import pathlib
import re
import shutil
import subprocess
import sys

binary, build_dir, destination = map(pathlib.Path, sys.argv[1:])
destination.mkdir(parents=True, exist_ok=True)
files = {binary.resolve(): destination / binary.name}
shutil.copy2(binary, files[binary.resolve()])
rewrites = {}
queue = [binary.resolve()]
rpaths_by_file = {}


def output(*args):
    return subprocess.check_output(args, text=True)


def rpaths(path):
    if path in rpaths_by_file:
        return rpaths_by_file[path]
    lines = output("otool", "-l", str(path)).splitlines()
    result = []
    for index, line in enumerate(lines):
        if line.strip() == "cmd LC_RPATH" and index + 1 < len(lines):
            match = re.match(r"\s*path (.*) \(offset \d+\)", lines[index + 1])
            if match:
                result.append(match.group(1))
    rpaths_by_file[path] = result
    return result


def resolve_dependency(path, dependency):
    if dependency.startswith("/usr/lib/") or dependency.startswith("/System/"):
        return None
    if dependency.startswith("@loader_path/"):
        candidate = path.parent / dependency.removeprefix("@loader_path/")
    elif dependency.startswith("@executable_path/"):
        candidate = binary.parent / dependency.removeprefix("@executable_path/")
    elif dependency.startswith("@rpath/"):
        suffix = dependency.removeprefix("@rpath/")
        candidates = [path.parent / suffix, destination / suffix, build_dir / suffix, build_dir / "lib" / suffix]
        candidates.extend(pathlib.Path(rpath) / suffix for rpath in rpaths(path) if rpath.startswith("/"))
        candidate = next((item for item in candidates if item.is_file()), None)
        if candidate is None:
            raise SystemExit(f"resolve dependency failed: {path}: {dependency}")
    else:
        candidate = pathlib.Path(dependency)
    candidate = candidate.resolve()
    if not candidate.is_file():
        raise SystemExit(f"dependency not found: {path}: {dependency}")
    return candidate


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


while queue:
    path = queue.pop(0)
    lines = output("otool", "-L", str(path)).splitlines()
    changes = []
    for line in lines[1:]:
        dependency = line.strip().split(" (compatibility version", 1)[0].strip()
        if not dependency:
            continue
        resolved = resolve_dependency(path, dependency)
        if resolved is None:
            continue
        target = destination / resolved.name
        if resolved not in files:
            existing = next((item for item in files.values() if item.name == target.name), None)
            if existing is not None:
                if digest(existing) != digest(resolved):
                    raise SystemExit(f"dylib basename conflict: {resolved} / {existing}")
            else:
                shutil.copy2(resolved, target)
            files[resolved] = target
            queue.append(resolved)
        changes.append((dependency, target.name))
    rewrites[path] = changes

for path, target in files.items():
    for dependency, basename in rewrites.get(path, []):
        subprocess.run(["install_name_tool", "-change", dependency, f"@loader_path/{basename}", str(target)], check=True)
    if "LC_ID_DYLIB" in output("otool", "-l", str(target)):
        subprocess.run(["install_name_tool", "-id", f"@loader_path/{target.name}", str(target)], check=True)
    for rpath in rpaths(path):
        subprocess.run(["install_name_tool", "-delete_rpath", rpath, str(target)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(target)], check=True)
PY

  version_output="$("$destination/cjxl" --version | head -n1)"
  [[ "$version_output" == *"${LIBJXL_VERSION#v}"* ]] \
    || fail "libjxl のバージョンが一致しません: $version_output"
  for file in "$destination"/*; do
    if otool -L "$file" | tail -n +2 | grep -Eq '/opt/homebrew|/private/var/folders|/Users/|/Applications/'; then
      fail "libjxl に外部パスへの依存が残っています: $file"
    fi
  done
  verify_deployment_target "$destination"/*
  smoke_dir="$WORK_DIR/libjxl-smoke"
  mkdir -p "$smoke_dir"
  env -i HOME="$WORK_DIR" "$destination/cjxl" \
    "$REPO_ROOT/docs/images/app-batch-convert01.png" "$smoke_dir/output.jxl" \
    --distance=1.0 -e 7 --num_threads=4
  [[ -s "$smoke_dir/output.jxl" ]] || fail "libjxl のエンコード検証に失敗しました。"
  write_version libjxl "$LIBJXL_VERSION"
}

build_libavif() {
  local tag="$LIBAVIF_VERSION"
  local archive="$WORK_DIR/libavif.tar.gz"
  local extracted="$WORK_DIR/libavif-source"
  local source_dir="$extracted/libavif-${tag#v}"
  local build_dir="$WORK_DIR/libavif-build"
  local destination="$OUT_DIR/libavif/bin/macos"
  local binary version_output dependencies smoke_dir

  download "https://github.com/AOMediaCodec/libavif/archive/refs/tags/${tag}.tar.gz" "$archive"
  mkdir -p "$extracted"
  tar -xzf "$archive" -C "$extracted"
  [[ -d "$source_dir" ]] || fail "libavif のソースディレクトリがありません: $source_dir"
  cmake -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DAVIF_BUILD_APPS=ON \
    -DAVIF_BUILD_EXAMPLES=OFF \
    -DAVIF_BUILD_TESTS=OFF \
    -DAVIF_CODEC_AOM=LOCAL \
    -DAVIF_CODEC_SVT=LOCAL \
    -DAVIF_CODEC_DAV1D=OFF \
    -DAVIF_ZLIBPNG=LOCAL \
    -DAVIF_JPEG=LOCAL \
    -DAVIF_LIBYUV=LOCAL
  cmake --build "$build_dir" --target avifenc --parallel 3
  binary="$(require_single_file "$build_dir" 'avifenc')"
  mkdir -p "$destination"
  cp "$binary" "$destination/avifenc"
  cp "$source_dir/LICENSE" "$OUT_DIR/libavif/LICENSE"
  chmod +x "$destination/avifenc"
  codesign --force --sign - "$destination/avifenc"

  version_output="$("$destination/avifenc" --version)"
  [[ "$version_output" == *"${LIBAVIF_VERSION#v}"* ]] \
    || fail "libavif のバージョンが一致しません: $version_output"
  [[ "$version_output" == *aom* && "$version_output" == *svt* ]] \
    || fail "libavif に aom または svt が含まれていません: $version_output"
  dependencies="$(otool -L "$destination/avifenc" | tail -n +2)"
  if grep -Eq '/opt/homebrew|/private/var/folders|/Users/|/Applications/' <<< "$dependencies"; then
    fail "libavif に外部パスへの依存が残っています。"
  fi
  verify_deployment_target "$destination/avifenc"
  smoke_dir="$WORK_DIR/libavif-smoke"
  mkdir -p "$smoke_dir"
  "$destination/avifenc" -c aom --speed 6 -q 60 -y 420 -j 4 \
    "$REPO_ROOT/docs/images/app-batch-convert01.png" "$smoke_dir/output-aom.avif"
  "$destination/avifenc" -c svt --speed 6 -q 60 -y 420 -j 4 \
    "$REPO_ROOT/docs/images/app-batch-convert01.png" "$smoke_dir/output-svt.avif"
  [[ -s "$smoke_dir/output-aom.avif" && -s "$smoke_dir/output-svt.avif" ]] \
    || fail "libavif のエンコード検証に失敗しました。"
  write_version libavif "$LIBAVIF_VERSION"
}

should_fetch upscal && fetch_upscal
should_fetch realcugan && fetch_realcugan
should_fetch jpegoptim && fetch_jpegoptim
should_fetch pngoptim && fetch_pngoptim
should_fetch libwebp && fetch_libwebp

# Why not ソースビルド済みバイナリを毎回再ビルドしないか: 変更のないツールは公開中assetを再利用し、再ビルドによるchecksum変動を避けるため。
if should_fetch libjxl; then
  if [[ "$LIBJXL_VERSION" != "$(tool_version libjxl)" ]]; then
    build_libjxl
  else
    copy_repository_tool libjxl
    if ! repository_source_compatible libjxl; then
      rm -rf "$OUT_DIR/libjxl"
      build_libjxl
    fi
  fi
fi
if should_fetch libavif; then
  if [[ "$LIBAVIF_VERSION" != "$(tool_version libavif)" ]]; then
    build_libavif
  else
    copy_repository_tool libavif
    if ! repository_source_compatible libavif; then
      rm -rf "$OUT_DIR/libavif"
      build_libavif
    fi
  fi
fi

TOOLS_ROOT="$OUT_DIR"
for name in ${CHANGED_TOOLS//,/ }; do
  [[ -d "$OUT_DIR/$name" ]] || fail "変更対象ツールを取得できませんでした: $name"
  version="$(tool_version "$name")"
  [[ -n "$version" ]] || fail "変更対象ツールのバージョンがありません: $name"
  verify_tool_payload "$name"
done

for relative in \
  'upscal/bin/upscayl-bin' \
  'realcugan/bin/macos/realcugan-ncnn-vulkan' \
  'jpegoptim/bin/macos/jpegoptim' \
  'pngoptim/bin/macos/pngoptim' \
  'libjxl/bin/macos/cjxl' \
  'libavif/bin/macos/avifenc' \
  'libwebp/bin/macos/cwebp'; do
  [[ -f "$OUT_DIR/$relative" ]] || continue
  architectures="$(lipo -archs "$OUT_DIR/$relative")"
  [[ "$architectures" == *arm64* ]] || fail "$relative は arm64 に対応していません: $architectures"
  verify_deployment_target "$OUT_DIR/$relative"
done
if [[ -d "$OUT_DIR/libjxl/bin/macos" ]]; then
  verify_deployment_target "$OUT_DIR"/libjxl/bin/macos/*.dylib
fi

if should_fetch jpegoptim; then
  version_output="$("$OUT_DIR/jpegoptim/bin/macos/jpegoptim" --version | head -n1)"
  [[ "$version_output" == *"${JPEGOPTIM_VERSION#v}"* ]] || fail "jpegoptim のバージョンが一致しません: $version_output"
fi
if should_fetch pngoptim; then
  version_output="$("$OUT_DIR/pngoptim/bin/macos/pngoptim" --version)"
  [[ "$version_output" == *"${PNGOPTIM_VERSION#v}"* ]] || fail "pngoptim のバージョンが一致しません: $version_output"
fi
if should_fetch libwebp; then
  version_output="$("$OUT_DIR/libwebp/bin/macos/cwebp" -version)"
  [[ "$version_output" == *"$LIBWEBP_VERSION"* ]] || fail "libwebp のバージョンが一致しません: $version_output"
fi

if should_fetch jpegoptim || should_fetch pngoptim || should_fetch libwebp; then
  smoke_dir="$WORK_DIR/direct-tools-smoke"
  mkdir -p "$smoke_dir/jpeg"
  sips -s format jpeg "$REPO_ROOT/docs/images/app-batch-convert01.png" --out "$smoke_dir/sample.jpg" >/dev/null
  if should_fetch jpegoptim; then
    "$OUT_DIR/jpegoptim/bin/macos/jpegoptim" -m80 -o -d "$smoke_dir/jpeg" "$smoke_dir/sample.jpg"
    [[ -s "$smoke_dir/jpeg/sample.jpg" ]] || fail 'jpegoptim のエンコード検証に失敗しました。'
  fi
  if should_fetch pngoptim; then
    "$OUT_DIR/pngoptim/bin/macos/pngoptim" "$REPO_ROOT/docs/images/app-batch-convert01.png" \
      -o "$smoke_dir/output.png" --quality 80
    [[ -s "$smoke_dir/output.png" ]] || fail 'pngoptim のエンコード検証に失敗しました。'
  fi
  if should_fetch libwebp; then
    "$OUT_DIR/libwebp/bin/macos/cwebp" -preset photo -q 80 -m 6 -mt \
      "$REPO_ROOT/docs/images/app-batch-convert01.png" -o "$smoke_dir/output.webp"
    [[ -s "$smoke_dir/output.webp" ]] || fail 'libwebp のエンコード検証に失敗しました。'
  fi
fi

echo "Fetched tools: $OUT_DIR"
