<img src="site/public/icon-512.png" alt="" width="96" height="96">

# Audio Extractr

A native macOS app that turns any video into an MP3: paste a link or drop a
file, trim it, set the speed, and save it to disk, plus a transcript if you
want one. No browser, no extra installs: everything is bundled.

**→ [Download page](https://thomasguillot.github.io/audio-extractr/)**: always
points at the latest release.

**Requires macOS 26 (Tahoe) or later, Apple Silicon. Unsigned, no Apple
Developer Program needed.**

Audio Extractr fetches whatever you point it at. Whether you may keep a copy is
between you, the rights holder, and the terms you agreed to.

## What it does

- **Paste a link**: downloads audio from hundreds of supported sites
  (powered by yt-dlp), converted to MP3 (192 kbps).
- **Or drop a file**: any audio or video file ffmpeg can read.
- **Trim**: start/end times (`1:23` or `0:01:23` style).
- **Speed**: 0.25× to 2× without pitch chaos (ffmpeg atempo).
- **Transcript** (experimental): transcribed on device and saved beside the
  MP3 as Markdown or plain text.
- **Self-updating**: the app updates itself from GitHub Releases, and keeps
  its bundled yt-dlp current (SHA-verified) so site changes don't break you.

## Install

The app is unsigned, so macOS blocks it on first launch:

1. Double-click **Audio Extractr**; when macOS says it "can't verify the
   developer," click **Done** (*not* "Move to Trash").
2. Open **System Settings → Privacy & Security**, scroll to **Security**.
3. Click **Open Anyway**, authenticate, then **Open**. macOS only asks once.

## For developers

Requirements: macOS 26+, Xcode 26+, `brew install xcodegen swiftlint create-dmg`.

```sh
cd ExtractrKit && swift test        # all logic tests
./scripts/fetch-binaries.sh         # fetch yt-dlp + ffmpeg (verified)
cd App && xcodegen                  # generate the Xcode project
open App/AudioExtractr.xcodeproj    # or xcodebuild
```

Release: bump `MARKETING_VERSION` in `App/project.yml`, run
`./scripts/make-dmg.sh`, publish with `gh release create`.

## License

MIT. See [LICENSE](LICENSE). Bundled tools are separate processes with their
own licenses. See [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md).
