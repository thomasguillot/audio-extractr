# Acknowledgements

Audio Extractr is MIT-licensed. It bundles third-party command-line tools, run as
separate processes (never linked into the app):

## yt-dlp

- https://github.com/yt-dlp/yt-dlp — released into the public domain (Unlicense).
- The app can keep yt-dlp current by downloading official release binaries,
  verified against the release's published SHA2-256SUMS.

## FFmpeg

- https://ffmpeg.org. The bundled `ffmpeg` and `ffprobe` are built by
  `scripts/build-ffmpeg.sh` from unmodified, pinned upstream sources: FFmpeg
  with LAME (https://lame.sourceforge.io) for MP3 encoding. Built without any
  GPL component, the binaries are licensed LGPL-2.1-or-later. The license texts
  ship inside the app at `Contents/Resources/bin/ffmpeg.LICENSE`, and the
  versions and configure line at `Contents/Resources/bin/ffmpeg.buildinfo`.
- Corresponding source: each release carries
  `ffmpeg-source-audio-<version>.tar.gz`, the exact source tarballs plus the
  build script.
