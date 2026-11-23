#!/usr/bin/env bash
#
# Puts the bundled tool binaries in Support/binaries/ (git-ignored). yt-dlp is
# downloaded at a pinned release tag and verified against a pinned SHA-256;
# ffmpeg and ffprobe are built from pinned sources by scripts/build-ffmpeg.sh.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Support/binaries"
mkdir -p "$DEST"

YTDLP_TAG="2026.10.26"
YTDLP_SHA256="0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa"   # yt-dlp 2026.10.26 yt-dlp_macos

cleanup() {
  rm -f "$DEST/yt-dlp.download"
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

"$ROOT/scripts/build-ffmpeg.sh" audio

echo "==> Done"
ls -lh "$DEST"
