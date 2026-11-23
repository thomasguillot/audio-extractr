#!/usr/bin/env bash
#
# Builds static ffmpeg and ffprobe for arm64 macOS from pinned upstream sources,
# configured with only the components one app uses.
#
# Usage:   ./scripts/build-ffmpeg.sh video|audio
#            video: GPL build (libx264, libzimg, libdav1d, VideoToolbox), for Video Extractr
#            audio: LGPL build (libmp3lame), for Audio Extractr
# Output:  Support/binaries/ffmpeg, ffprobe, ffmpeg.LICENSE, ffmpeg.buildinfo
#          dist/ffmpeg-source-<profile>-<version>.tar.gz, the corresponding source
#          (every tarball used plus this script), to attach to each release
# Needs:   Xcode command line tools; brew install meson ninja automake libtool pkgconf
# Cache:   Support/ffmpeg-build/ (git-ignored): downloads and per-profile builds, so a
#          rerun with nothing changed only re-verifies and copies.
# Env:     FFMPEG_JOBS overrides the parallelism (default: half the cores).
#
# Every tarball is checked against the SHA-256 pinned below before it is unpacked. The
# FFmpeg tarball's GPG signature is checked too when gpg is installed.
#
set -euo pipefail

PROFILE="${1:-}"
case "$PROFILE" in
  video|audio) ;;
  *) echo "usage: $0 video|audio" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/$(basename "${BASH_SOURCE[0]}")"
CACHE="$ROOT/Support/ffmpeg-build"
DOWNLOADS="$CACHE/downloads"
WORK="$CACHE/$PROFILE"
PREFIX="$WORK/prefix"
DEST="$ROOT/Support/binaries"
DIST="$ROOT/dist"

MIN_MACOS="26.0"
JOBS="${FFMPEG_JOBS:-$(( $(sysctl -n hw.ncpu) / 2 ))}"
[ "$JOBS" -ge 1 ] || JOBS=1

FFMPEG_VERSION="9.1"
FFMPEG_SHA256="1a4d394ae63d190a526cd052eb4415c156b5c5e2df37efab41a7de0b8fde2433"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
FFMPEG_GPG_FINGERPRINT="FCF986EA15E6E293A5644F10B4322F04D67658D8"
FFMPEG_GPG_KEY_URL="https://ffmpeg.org/ffmpeg-devel.asc"

X264_COMMIT="b35605ace3ddf7c1a5d67a2eb553f034aef41d55"
X264_SHA256="6eeb82934e69fd51e043bd8c5b0d152839638d1ce7aa4eea65a3fedcf83ff224"
X264_URL="https://code.videolan.org/videolan/x264/-/archive/$X264_COMMIT/x264-$X264_COMMIT.tar.bz2"

ZIMG_VERSION="3.0.6"
ZIMG_SHA256="be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577"
ZIMG_URL="https://github.com/sekrit-twc/zimg/archive/refs/tags/release-$ZIMG_VERSION.tar.gz"

DAV1D_VERSION="1.5.5"
DAV1D_SHA256="ca96b1d0ba3f01f55de7231d775892b64994ba061aaeeaaa4f662a390b3abf9e"
DAV1D_URL="https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.xz"

LAME_VERSION="3.100"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"

COMMON_BSFS="aac_adtstoasc extract_extradata null setts vp9_superframe"
COMMON_PARSERS="aac aac_latm ac3 av1 dca flac h264 hevc mlp mpeg4video mpegaudio mpegvideo opus vorbis vp8 vp9"
PCM_DECODERS="pcm_alaw pcm_bluray pcm_dvd pcm_f32be pcm_f32le pcm_f64be pcm_f64le pcm_mulaw
  pcm_s16be pcm_s16le pcm_s16le_planar pcm_s24be pcm_s24le pcm_s32be pcm_s32le pcm_s8 pcm_u8"
COMMON_AUDIO_DECODERS="aac aac_latm ac3 adpcm_ima_qt adpcm_ima_wav adpcm_ms alac amrnb amrwb dca
  eac3 flac mlp mp1 mp1float mp2 mp2float mp3 mp3float opus truehd vorbis wmapro wmav1 wmav2
  $PCM_DECODERS"

if [ "$PROFILE" = video ]; then
  LICENSE_KIND="GPL-2.0-or-later"
  DEMUXERS="aac asf avi dv flac flv matroska mov mp3 mpegps mpegts mpegvideo mxf ogg wav"
  DECODERS="dnxhd dvvideo flv h263 h264 hevc libdav1d mjpeg mpeg1video mpeg2video mpeg4
    msmpeg4v1 msmpeg4v2 msmpeg4v3 png prores qtrle rawvideo theora vc1 vp6 vp6a vp6f vp8 vp9
    wmv1 wmv2 wmv3 $COMMON_AUDIO_DECODERS"
  ENCODERS="aac h264_videotoolbox libx264 mjpeg wrapped_avframe"
  MUXERS="image2 ipod matroska mov mp4 null webm"
  PARSERS="$COMMON_PARSERS h263 mjpeg vc1"
  FILTERS="aformat anull aresample atempo format fps hstack null scale setparams setpts setsar
    showinfo testsrc2 tonemap trim zscale"
  LIBRARIES="--enable-gpl --enable-libx264 --enable-libzimg --enable-libdav1d --enable-videotoolbox"
else
  LICENSE_KIND="LGPL-2.1-or-later"
  DEMUXERS="aac ac3 aiff amr ape asf au avi caf dsf dts dtshd dv eac3 flac flv loas matroska mlp
    mov mp3 mpc mpc8 mpegps mpegts mpegvideo mxf ogg rm shorten tak truehd tta voc w64 wav wv"
  DECODERS="adpcm_g726 ape atrac3 cook dsd_lsbf dsd_lsbf_planar dsd_msbf dsd_msbf_planar gsm
    gsm_ms mpc7 mpc8 ra_144 ra_288 shorten tak tta wavpack wmalossless $COMMON_AUDIO_DECODERS"
  ENCODERS="aac libmp3lame pcm_s16le"
  MUXERS="ipod matroska mov mp3 mp4 pcm_s16le webm"
  PARSERS="$COMMON_PARSERS amr tak"
  FILTERS="aformat anull aresample atempo"
  LIBRARIES="--enable-libmp3lame --disable-swscale"
fi

list() { echo $1 | tr ' ' ','; }

FFMPEG_CONFIGURE=(
  --disable-everything --disable-autodetect --disable-network --disable-avdevice
  --disable-ffplay --disable-doc --disable-debug --disable-shared --enable-static
  --enable-zlib --pkg-config-flags=--static
  --extra-cflags="-mmacosx-version-min=$MIN_MACOS"
  --extra-ldflags="-mmacosx-version-min=$MIN_MACOS"
  $LIBRARIES
  --enable-protocol=file,pipe
  --enable-demuxer="$(list "$DEMUXERS")"
  --enable-decoder="$(list "$DECODERS")"
  --enable-encoder="$(list "$ENCODERS")"
  --enable-muxer="$(list "$MUXERS")"
  --enable-parser="$(list "$PARSERS")"
  --enable-bsf="$(list "$COMMON_BSFS")"
  --enable-filter="$(list "$FILTERS")"
)
if [ "$PROFILE" = video ]; then
  FFMPEG_CONFIGURE+=(--extra-libs=-lc++)
fi

for tool in curl shasum make clang pkg-config; do
  command -v "$tool" >/dev/null || { echo "error: $tool not found" >&2; exit 1; }
done
if [ "$PROFILE" = video ]; then
  for tool in meson ninja autoreconf automake glibtoolize; do
    command -v "$tool" >/dev/null || { echo "error: $tool not found (brew install meson ninja automake libtool)" >&2; exit 1; }
  done
fi

unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH PKG_CONFIG_PATH DYLD_LIBRARY_PATH
export MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"
# Only our own prefix: Homebrew's shared copies of the same libraries must never be picked up.
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export CFLAGS="-arch arm64 -mmacosx-version-min=$MIN_MACOS -O2"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch arm64 -mmacosx-version-min=$MIN_MACOS"

mkdir -p "$DOWNLOADS" "$WORK" "$PREFIX" "$DEST" "$DIST"

fetch() {
  local url="$1" file="$2" expected="$3" path="$DOWNLOADS/$2"
  if [ ! -f "$path" ] || [ "$(shasum -a 256 "$path" | awk '{print $1}')" != "$expected" ]; then
    echo "==> Downloading $file"
    curl -fL --retry 3 -o "$path.part" "$url"
    local actual
    actual="$(shasum -a 256 "$path.part" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
      rm -f "$path.part"
      echo "error: $file SHA-256 mismatch (expected $expected, got $actual)" >&2
      exit 1
    fi
    mv "$path.part" "$path"
  fi
  echo "    $file verified"
}

verify_ffmpeg_signature() {
  local tarball="$DOWNLOADS/ffmpeg-$FFMPEG_VERSION.tar.xz"
  if ! command -v gpg >/dev/null; then
    echo "    gpg not installed, skipping the signature check (the SHA-256 is still pinned)"
    return
  fi
  if ! curl -fsSL --retry 3 -o "$DOWNLOADS/ffmpeg-$FFMPEG_VERSION.tar.xz.asc" "$FFMPEG_URL.asc" \
    || ! curl -fsSL --retry 3 -o "$DOWNLOADS/ffmpeg-devel.asc" "$FFMPEG_GPG_KEY_URL"; then
    echo "    warning: could not fetch the FFmpeg signature or key, skipping the signature check" >&2
    return
  fi
  local home status
  home="$(mktemp -d)"
  GNUPGHOME="$home" gpg --batch --quiet --import "$DOWNLOADS/ffmpeg-devel.asc" 2>/dev/null || true
  status="$(GNUPGHOME="$home" gpg --batch --status-fd 1 --verify \
    "$DOWNLOADS/ffmpeg-$FFMPEG_VERSION.tar.xz.asc" "$tarball" 2>/dev/null || true)"
  rm -rf "$home"
  if ! grep -q "^\[GNUPG:\] VALIDSIG $FFMPEG_GPG_FINGERPRINT " <<<"$status"; then
    echo "error: ffmpeg-$FFMPEG_VERSION.tar.xz is not signed by $FFMPEG_GPG_FINGERPRINT" >&2
    exit 1
  fi
  echo "    ffmpeg-$FFMPEG_VERSION.tar.xz signature verified ($FFMPEG_GPG_FINGERPRINT)"
}

unpack() {
  local file="$1" dir="$WORK/src/$2"
  rm -rf "$dir"
  mkdir -p "$dir"
  tar -xf "$DOWNLOADS/$file" -C "$dir" --strip-components 1
  echo "$dir"
}

stamp_matches() { [ -f "$WORK/$1.stamp" ] && [ "$(cat "$WORK/$1.stamp")" = "$2" ]; }
write_stamp() {
  printf '%s' "$2" > "$WORK/$1.stamp"
  [ "$1" = ffmpeg ] || rm -f "$WORK/ffmpeg.stamp"
}

build_x264() {
  local key="x264 $X264_COMMIT $X264_SHA256 $MIN_MACOS"
  stamp_matches x264 "$key" && { echo "==> x264 (cached)"; return; }
  echo "==> Building x264 ($X264_COMMIT)"
  local src
  src="$(unpack "x264-$X264_COMMIT.tar.bz2" x264)"
  (
    cd "$src"
    nice -n 15 ./configure --prefix="$PREFIX" --enable-static --enable-pic --disable-cli \
      --bit-depth=8 --chroma-format=420 --disable-opencl --disable-avs --disable-swscale \
      --disable-lavf --disable-ffms --disable-gpac --disable-lsmash \
      --extra-cflags="-mmacosx-version-min=$MIN_MACOS" --extra-ldflags="-mmacosx-version-min=$MIN_MACOS"
    nice -n 15 make -j"$JOBS"
    make install-lib-static
  )
  write_stamp x264 "$key"
}

build_zimg() {
  local key="zimg $ZIMG_VERSION $ZIMG_SHA256 $MIN_MACOS"
  stamp_matches zimg "$key" && { echo "==> zimg (cached)"; return; }
  echo "==> Building zimg $ZIMG_VERSION"
  local src
  src="$(unpack "zimg-$ZIMG_VERSION.tar.gz" zimg)"
  (
    cd "$src"
    LIBTOOLIZE=glibtoolize nice -n 15 ./autogen.sh
    nice -n 15 ./configure --prefix="$PREFIX" --enable-static --disable-shared \
      --disable-testapp --disable-example --disable-unit-test
    nice -n 15 make -j"$JOBS"
    make install
  )
  write_stamp zimg "$key"
}

build_dav1d() {
  local key="dav1d $DAV1D_VERSION $DAV1D_SHA256 $MIN_MACOS"
  stamp_matches dav1d "$key" && { echo "==> dav1d (cached)"; return; }
  echo "==> Building dav1d $DAV1D_VERSION"
  local src
  src="$(unpack "dav1d-$DAV1D_VERSION.tar.xz" dav1d)"
  (
    cd "$src"
    nice -n 15 meson setup build --prefix="$PREFIX" --libdir=lib --buildtype=release \
      --default-library=static -Denable_tools=false -Denable_tests=false \
      -Denable_examples=false -Denable_docs=false
    nice -n 15 ninja -C build -j "$JOBS"
    ninja -C build install
  )
  write_stamp dav1d "$key"
}

build_lame() {
  local key="lame $LAME_VERSION $LAME_SHA256 $MIN_MACOS"
  stamp_matches lame "$key" && { echo "==> lame (cached)"; return; }
  echo "==> Building LAME $LAME_VERSION"
  local src
  src="$(unpack "lame-$LAME_VERSION.tar.gz" lame)"
  (
    cd "$src"
    nice -n 15 ./configure --prefix="$PREFIX" --host=aarch64-apple-darwin \
      --enable-static --disable-shared --disable-frontend --disable-decoder --disable-gtktest
    nice -n 15 make -j"$JOBS"
    make install
  )
  write_stamp lame "$key"
}

# configure warns about an unknown component only when none in a list match, so each is checked.
check_components() {
  local kind names known name missing=""
  for kind in demuxer decoder encoder muxer parser bsf filter protocol; do
    case "$kind" in
      demuxer) names="$DEMUXERS" ;;
      decoder) names="$DECODERS" ;;
      encoder) names="$ENCODERS" ;;
      muxer) names="$MUXERS" ;;
      parser) names="$PARSERS" ;;
      bsf) names="$COMMON_BSFS" ;;
      filter) names="$FILTERS" ;;
      protocol) names="file pipe" ;;
    esac
    known="$(./configure --list-${kind}s | tr -s ' \t' '\n')"
    for name in $names; do
      grep -qx "$name" <<<"$known" || missing="$missing $kind:$name"
    done
  done
  if [ -n "$missing" ]; then
    echo "error: FFmpeg $FFMPEG_VERSION has no$missing" >&2
    exit 1
  fi
}

build_ffmpeg() {
  local key="ffmpeg $FFMPEG_VERSION $FFMPEG_SHA256 ${FFMPEG_CONFIGURE[*]}"
  local out="$WORK/src/ffmpeg"
  if stamp_matches ffmpeg "$key" && [ -x "$out/ffmpeg" ] && [ -x "$out/ffprobe" ]; then
    echo "==> FFmpeg $FFMPEG_VERSION (cached)"
    return
  fi
  echo "==> Building FFmpeg $FFMPEG_VERSION ($PROFILE)"
  local src
  src="$(unpack "ffmpeg-$FFMPEG_VERSION.tar.xz" ffmpeg)"
  (
    cd "$src"
    # ffmpeg -version prints the configure line, so the local prefix is passed through the environment.
    export CPATH="$PREFIX/include" LIBRARY_PATH="$PREFIX/lib"
    check_components
    nice -n 15 ./configure "${FFMPEG_CONFIGURE[@]}" | tee "$WORK/configure.log"
    nice -n 15 make -j"$JOBS" ffmpeg ffprobe
  )
  write_stamp ffmpeg "$key"
}

check_binary() {
  local bin="$1" libs
  libs="$(otool -L "$bin" | tail -n +2 | awk '{print $1}')"
  if grep -vE '^(/System/Library/Frameworks/|/usr/lib/)' <<<"$libs" | grep -q .; then
    echo "error: $bin links a library outside the system:" >&2
    echo "$libs" >&2
    exit 1
  fi
  local minos
  minos="$(otool -l "$bin" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
  if [ "$minos" != "$MIN_MACOS" ]; then
    echo "error: $bin targets macOS $minos, expected $MIN_MACOS" >&2
    exit 1
  fi
  lipo -archs "$bin" | grep -qx arm64 || { echo "error: $bin is not arm64-only" >&2; exit 1; }
}

write_license() {
  local src="$WORK/src" out="$DEST/ffmpeg.LICENSE"
  {
    echo "The bundled ffmpeg and ffprobe are built from unmodified upstream sources by"
    echo "scripts/build-ffmpeg.sh ($PROFILE profile). As built they are licensed under the"
    if [ "$PROFILE" = video ]; then
      echo "GNU General Public License, version 2 or later (FFmpeg configured with --enable-gpl,"
      echo "linking x264). The complete corresponding source is published with each release as"
    else
      echo "GNU Lesser General Public License, version 2.1 or later. The complete corresponding"
      echo "source is published with each release as"
    fi
    echo "ffmpeg-source-$PROFILE-$FFMPEG_VERSION.tar.gz. ffmpeg.buildinfo lists every version"
    echo "and the configure line."
    echo
    echo "Components:"
    echo "  FFmpeg $FFMPEG_VERSION, https://ffmpeg.org, $LICENSE_KIND as configured"
    if [ "$PROFILE" = video ]; then
      echo "  x264 $X264_COMMIT, https://code.videolan.org/videolan/x264, GPL-2.0-or-later"
      echo "  zimg $ZIMG_VERSION, https://github.com/sekrit-twc/zimg, WTFPL"
      echo "  dav1d $DAV1D_VERSION, https://code.videolan.org/videolan/dav1d, BSD-2-Clause"
    else
      echo "  LAME $LAME_VERSION, https://lame.sourceforge.io, LGPL-2.0-or-later"
    fi
    echo
    echo "==== FFmpeg LICENSE.md ===="
    cat "$src/ffmpeg/LICENSE.md"
    if [ "$PROFILE" = video ]; then
      echo
      echo "==== GNU General Public License, version 2 (FFmpeg COPYING.GPLv2, also x264's license) ===="
      cat "$src/ffmpeg/COPYING.GPLv2"
      echo
      echo "==== zimg COPYING ===="
      cat "$src/zimg/COPYING"
      echo
      echo "==== dav1d COPYING ===="
      cat "$src/dav1d/COPYING"
    else
      echo
      echo "==== GNU Lesser General Public License, version 2.1 (FFmpeg COPYING.LGPLv2.1) ===="
      cat "$src/ffmpeg/COPYING.LGPLv2.1"
      echo
      echo "==== LAME COPYING ===="
      cat "$src/lame/COPYING"
    fi
  } > "$out"
}

write_buildinfo() {
  local out="$DEST/ffmpeg.buildinfo"
  {
    echo "profile: $PROFILE"
    echo "license: $LICENSE_KIND"
    echo "ffmpeg: $FFMPEG_VERSION sha256=$FFMPEG_SHA256 $FFMPEG_URL"
    if [ "$PROFILE" = video ]; then
      echo "x264: $X264_COMMIT sha256=$X264_SHA256 $X264_URL"
      echo "zimg: $ZIMG_VERSION sha256=$ZIMG_SHA256 $ZIMG_URL"
      echo "dav1d: $DAV1D_VERSION sha256=$DAV1D_SHA256 $DAV1D_URL"
    else
      echo "lame: $LAME_VERSION sha256=$LAME_SHA256 $LAME_URL"
    fi
    echo "target: arm64-apple-macos$MIN_MACOS"
    echo "compiler: $(clang --version | head -1)"
    echo "sdk: $(xcrun --show-sdk-version)"
    echo "configure: ${FFMPEG_CONFIGURE[*]}"
  } > "$out"
}

write_source_bundle() {
  local name="ffmpeg-source-$PROFILE-$FFMPEG_VERSION"
  local stage
  stage="$(mktemp -d)"
  mkdir -p "$stage/$name"
  cp "$DOWNLOADS/ffmpeg-$FFMPEG_VERSION.tar.xz" "$stage/$name/"
  if [ "$PROFILE" = video ]; then
    cp "$DOWNLOADS/x264-$X264_COMMIT.tar.bz2" "$DOWNLOADS/zimg-$ZIMG_VERSION.tar.gz" \
      "$DOWNLOADS/dav1d-$DAV1D_VERSION.tar.xz" "$stage/$name/"
  else
    cp "$DOWNLOADS/lame-$LAME_VERSION.tar.gz" "$stage/$name/"
  fi
  cp "$SCRIPT" "$stage/$name/build-ffmpeg.sh"
  cp "$DEST/ffmpeg.buildinfo" "$DEST/ffmpeg.LICENSE" "$stage/$name/"
  tar -czf "$DIST/$name.tar.gz" -C "$stage" "$name"
  rm -rf "$stage"
  echo "$DIST/$name.tar.gz"
}

echo "==> Sources ($PROFILE)"
fetch "$FFMPEG_URL" "ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_SHA256"
verify_ffmpeg_signature
if [ "$PROFILE" = video ]; then
  fetch "$X264_URL" "x264-$X264_COMMIT.tar.bz2" "$X264_SHA256"
  fetch "$ZIMG_URL" "zimg-$ZIMG_VERSION.tar.gz" "$ZIMG_SHA256"
  fetch "$DAV1D_URL" "dav1d-$DAV1D_VERSION.tar.xz" "$DAV1D_SHA256"
  build_x264
  build_zimg
  build_dav1d
else
  fetch "$LAME_URL" "lame-$LAME_VERSION.tar.gz" "$LAME_SHA256"
  build_lame
fi
build_ffmpeg

for bin in ffmpeg ffprobe; do
  check_binary "$WORK/src/ffmpeg/$bin"
  cp "$WORK/src/ffmpeg/$bin" "$DEST/$bin.download"
  chmod +x "$DEST/$bin.download"
  mv "$DEST/$bin.download" "$DEST/$bin"
done
write_license
write_buildinfo
BUNDLE="$(write_source_bundle)"

echo "==> Done ($PROFILE)"
ls -lh "$DEST/ffmpeg" "$DEST/ffprobe" "$BUNDLE"
