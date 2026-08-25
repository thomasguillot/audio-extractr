# Acknowledgements

Audio Extractr is MIT-licensed. It bundles two third-party command-line tools,
run as separate processes (never linked into the app):

## yt-dlp

- https://github.com/yt-dlp/yt-dlp — released into the public domain (Unlicense).
- The app can keep yt-dlp current by downloading official release binaries,
  verified against the release's published SHA2-256SUMS.

## FFmpeg

- Binary build from https://github.com/eugeneware/ffmpeg-static (GPLv3 build of
  https://ffmpeg.org). The build's license text ships inside the app at
  `Contents/Resources/bin/ffmpeg.LICENSE`.
- FFmpeg source: https://ffmpeg.org/download.html — the bundled binary's
  corresponding source is available from the two projects above.
