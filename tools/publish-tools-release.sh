#!/usr/bin/env bash
# ビルド済みツール成果物を tools-latest の事前リリースへ公開する。
#
# 使い方:
#   tools/publish-tools-release.sh <output-dir>
#
# 環境変数:
#   GH_TOKEN     GitHub 認証トークン
#   TAG          配布先のリリースタグ（既定: tools-latest）
#   GITHUB_SHA   新規Releaseのタグ先（既定: main）
set -euo pipefail

OUT_DIR="${1:?成果物ディレクトリを指定してください}"
TAG="${TAG:-tools-latest}"
GH_TOKEN="${GH_TOKEN:?GitHub 認証トークンを指定してください}"
TARGET_COMMIT="${GITHUB_SHA:-main}"

[[ "$TAG" == tools-* ]] || {
  echo "::error::TAG は tools- で始まる名前を指定してください: $TAG" >&2
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

# 公開前にローカル成果物の整合性を確認する。
(
  cd "$OUT_DIR"
  shasum -a 256 -c SHA256SUMS.txt
)

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
if remote_assets="$(gh release view "$TAG" --json assets \
  --jq '.assets[] | [.name, (.digest // "")] | @tsv' 2>/dev/null)"; then
  release_exists=true
fi

if [[ "$release_exists" == false ]]; then
  # Why not 公開状態で先に作るか: アップロード失敗時に利用者へ壊れた配布物を露出しないため。
  gh release create "$TAG" \
    --target "$TARGET_COMMIT" \
    --title "Tools" \
    --notes "Tree Image Optimizer の外部ツール配布物です。アプリが起動時に取得します。" \
    --prerelease --draft
  # 既存Draftの再開も、全assetを揃えてから下の編集ステップで公開する。
fi

# 同一版の force 再公開でも、異なる内容を同名assetへ上書きしない。
# 既存assetとチェックサムが一致した場合だけアップロードを省略する。
for file in "${binary_assets[@]}"; do
  name="${file##*/}"
  remote_digest="$(printf '%s\n' "$remote_assets" | awk -F '\t' -v name="$name" '$1 == name { print $2 }')"
  if [[ -n "$remote_digest" ]]; then
    local_digest="sha256:$(shasum -a 256 "$file" | awk '{print $1}')"
    if [[ "$remote_digest" != "$local_digest" ]]; then
      echo "::error::$name は既存assetと内容が異なります。ツールバージョンを変更してください。" >&2
      exit 1
    fi
    echo "Skip unchanged asset: $name"
  else
    gh release upload "$TAG" "$file"
  fi
done

# メタデータは最後に更新し、新しいZIPが見える前にmanifestを切り替えない。
gh release upload "$TAG" "$OUT_DIR/SHA256SUMS.txt" --clobber
gh release upload "$TAG" "$OUT_DIR/tools-info.json" --clobber

keep_assets=" "
for file in "${binary_assets[@]}"; do
  keep_assets+=" ${file##*/} "
done
keep_assets+=" SHA256SUMS.txt tools-info.json "

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
