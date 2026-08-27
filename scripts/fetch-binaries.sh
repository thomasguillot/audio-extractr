#!/usr/bin/env bash
#
# Downloads the bundled tool binaries into Support/binaries/ (git-ignored).
# yt-dlp and ffmpeg are both pinned to a specific release tag and verified
# against a pinned SHA-256 before being installed.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Support/binaries"
mkdir -p "$DEST"

YTDLP_TAG="2026.08.19"
YTDLP_SHA256="0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202"   # yt-dlp 2026.08.19 yt-dlp_macos

FFMPEG_TAG="b6.1.1"
FFMPEG_SHA256="a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584"   # eugeneware/ffmpeg-static b6.1.1 ffmpeg-darwin-arm64

cleanup() {
  rm -f "$DEST/yt-dlp.download" "$DEST/ffmpeg.download"
}
trap cleanup EXIT

# An empty pin aborts rather than installing unverified; ALLOW_UNVERIFIED=1 is the
# deliberate opt-out, for bootstrapping a new pin.
fetch_verified() {
  local label="$1" url="$2" download_path="$3" expected="$4" final_path="$5"
  curl -fL --retry 3 -o "$download_path" "$url"
  local actual
  actual="$(shasum -a 256 "$download_path" | awk '{print $1}')"
  if [ -z "$expected" ]; then
    if [ "${ALLOW_UNVERIFIED:-}" = "1" ]; then
      echo "warning: $label SHA-256 not pinned — ALLOW_UNVERIFIED=1 set, installing unverified (actual: $actual)" >&2
    else
      echo "error: $label SHA-256 not pinned — set it in scripts/fetch-binaries.sh, or set ALLOW_UNVERIFIED=1 to bootstrap a new pin (actual: $actual)" >&2
      exit 1
    fi
  elif [ "$expected" != "$actual" ]; then
    echo "error: $label SHA-256 mismatch (expected $expected, got $actual)" >&2
    exit 1
  fi
  chmod +x "$download_path"
  mv "$download_path" "$final_path"
}

echo "==> yt-dlp ($YTDLP_TAG)"
fetch_verified "yt-dlp" \
  "https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_TAG/yt-dlp_macos" \
  "$DEST/yt-dlp.download" "$YTDLP_SHA256" "$DEST/yt-dlp"
printf '%s' "$YTDLP_TAG" > "$DEST/yt-dlp.tag"
echo "    yt-dlp $YTDLP_TAG verified"

echo "==> ffmpeg ($FFMPEG_TAG, darwin-arm64)"
FBASE="https://github.com/eugeneware/ffmpeg-static/releases/download/$FFMPEG_TAG"
curl -fL --retry 3 -o "$DEST/ffmpeg.LICENSE" "$FBASE/darwin-arm64.LICENSE"
fetch_verified "ffmpeg" "$FBASE/ffmpeg-darwin-arm64" "$DEST/ffmpeg.download" "$FFMPEG_SHA256" "$DEST/ffmpeg"
echo "    ffmpeg $FFMPEG_TAG verified"

echo "==> Done"
ls -lh "$DEST"
