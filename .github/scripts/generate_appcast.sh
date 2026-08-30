#!/bin/bash

# Generate Sparkle appcast.xml for auto_updater.
#
# Usage:
#   generate_appcast.sh \
#     <version> \
#     <build_number> \
#     <zip_name> \
#     <zip_size> \
#     <ed_signature> \
#     <output_path> \
#     <repo_url>
#
# Example:
#   generate_appcast.sh \
#     0.0.4 \
#     4 \
#     Tree-Image-Optimizer-v0.0.4-macos.zip \
#     21308388 \
#     "BASE64_SIGNATURE" \
#     appcast.xml \
#     https://github.com/treetips/tree-image-optimizer

set -euo pipefail

VERSION="${1:?version is required}"
BUILD_NUMBER="${2:?build_number is required}"
ZIP_NAME="${3:?zip_name is required}"
ZIP_SIZE="${4:?zip_size is required}"
ED_SIGNATURE="${5:?ed_signature is required}"
OUTPUT_PATH="${6:?output_path is required}"
REPO_URL="${7:?repo_url is required}"

PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

DOWNLOAD_URL="${REPO_URL}/releases/download/v${VERSION}/${ZIP_NAME}"
RELEASE_NOTES_URL="${REPO_URL}/releases/tag/v${VERSION}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

cat > "$OUTPUT_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Tree Image Optimizer</title>
    <link>${REPO_URL}</link>
    <description>Updates for Tree Image Optimizer</description>
    <language>ja</language>

    <item>
      <title>Version ${VERSION}</title>

      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>

      <sparkle:releaseNotesLink>
        ${RELEASE_NOTES_URL}
      </sparkle:releaseNotesLink>

      <pubDate>${PUB_DATE}</pubDate>

      <enclosure
        url="${DOWNLOAD_URL}"
        sparkle:edSignature="${ED_SIGNATURE}"
        sparkle:os="macos"
        length="${ZIP_SIZE}"
        type="application/octet-stream" />
    </item>

  </channel>
</rss>
XML

echo "Generated appcast:"
echo "  Version:       ${VERSION}"
echo "  Build number:  ${BUILD_NUMBER}"
echo "  ZIP:           ${ZIP_NAME}"
echo "  ZIP size:      ${ZIP_SIZE}"
echo "  Download URL:  ${DOWNLOAD_URL}"
echo "  Output:        ${OUTPUT_PATH}"
