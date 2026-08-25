#!/usr/bin/env bash
#
# Downloads the bundled tool binaries into Support/binaries/ (git-ignored).
# yt-dlp: latest release, verified against its published SHA2-256SUMS.
# ffmpeg: eugeneware/ffmpeg-static pinned tag (arm64), verified against the pinned hash.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Support/binaries"
mkdir -p "$DEST"

FFMPEG_TAG="b6.1.1"
FFMPEG_SHA256="a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584"   # eugeneware/ffmpeg-static b6.1.1 ffmpeg-darwin-arm64

cleanup() {
  rm -f "$DEST/yt-dlp.download" "$DEST/ffmpeg.download"
}
trap cleanup EXIT

echo "==> yt-dlp (latest release)"
TAG="$(curl -fsSL --retry 3 https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest \
  | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
BASE="https://github.com/yt-dlp/yt-dlp/releases/download/$TAG"
curl -fL --retry 3 -o "$DEST/yt-dlp.download" "$BASE/yt-dlp_macos"
curl -fL --retry 3 -o "$DEST/SHA2-256SUMS" "$BASE/SHA2-256SUMS"
EXPECTED="$(awk '$2 == "yt-dlp_macos" {print $1}' "$DEST/SHA2-256SUMS")"
ACTUAL="$(shasum -a 256 "$DEST/yt-dlp.download" | awk '{print $1}')"
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "error: yt-dlp SHA-256 mismatch (expected ${EXPECTED:-<none>}, got $ACTUAL)" >&2
  exit 1
fi
rm -f "$DEST/SHA2-256SUMS"
chmod +x "$DEST/yt-dlp.download"
mv "$DEST/yt-dlp.download" "$DEST/yt-dlp"
printf '%s' "$TAG" > "$DEST/yt-dlp.tag"
echo "    yt-dlp $TAG verified"

echo "==> ffmpeg ($FFMPEG_TAG, darwin-arm64)"
FBASE="https://github.com/eugeneware/ffmpeg-static/releases/download/$FFMPEG_TAG"
curl -fL --retry 3 -o "$DEST/ffmpeg.download" "$FBASE/ffmpeg-darwin-arm64"
curl -fL --retry 3 -o "$DEST/ffmpeg.LICENSE" "$FBASE/darwin-arm64.LICENSE"
ACTUAL="$(shasum -a 256 "$DEST/ffmpeg.download" | awk '{print $1}')"
if [ -z "$FFMPEG_SHA256" ]; then
  echo "note: FFMPEG_SHA256 not pinned — edit scripts/fetch-binaries.sh and set it to: $ACTUAL"
elif [ "$FFMPEG_SHA256" != "$ACTUAL" ]; then
  echo "error: ffmpeg SHA-256 mismatch (expected $FFMPEG_SHA256, got $ACTUAL)" >&2
  exit 1
fi
chmod +x "$DEST/ffmpeg.download"
mv "$DEST/ffmpeg.download" "$DEST/ffmpeg"

echo "==> Done"
ls -lh "$DEST"
