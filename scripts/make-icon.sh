#!/bin/bash
# Regenerates the app icon and the site mark from one glyph definition: a
# full-bleed rounded square with the media glyph centred on it. The app icon is
# flat #1b1d22 with a #fcfcfd glyph, single appearance. site/public/icon.svg
# carries its own prefers-color-scheme block so the site mark and the favicon
# invert in dark mode. Writes the asset-catalog PNGs, site/public/icon-512.png
# and site/public/icon.svg.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

read -r -d '' GLYPH_PATHS <<'PATHS' || true
  <path d="M9 11C9.55231 11 10 11.4478 10 12C10 12.5522 9.55231 13 9 13C8.44769 13 8 12.5522 8 12C8 11.4478 8.44769 11 9 11Z"/>
  <path d="M15 11C15.5522 11 16 11.4478 16 12C16 12.5522 15.5522 13 15 13C14.4478 13 14 12.5522 14 12C14 11.4478 14.4478 11 15 11Z"/>
  <path d="M15.25 8.5C15.6642 8.5 16 8.83579 16 9.25C16 9.66421 15.6642 10 15.25 10H8.75C8.33579 10 8 9.66421 8 9.25C8 8.83579 8.33579 8.5 8.75 8.5H15.25Z"/>
  <path fill-rule="evenodd" clip-rule="evenodd" d="M17.25 5C18.7688 5 20 6.23122 20 7.75V16.25C20 17.7688 18.7688 19 17.25 19H6.75C5.23122 19 4 17.7688 4 16.25V7.75C4 6.23122 5.23122 5 6.75 5H17.25ZM6.75 6.5C6.05964 6.5 5.5 7.05964 5.5 7.75V16.25C5.5 16.9404 6.05964 17.5 6.75 17.5H7.16992L8.34473 15.3857L8.39941 15.3008C8.53979 15.1131 8.76171 15 9 15H15C15.2723 15 15.523 15.1478 15.6553 15.3857L16.8301 17.5H17.25C17.9404 17.5 18.5 16.9404 18.5 16.25V7.75C18.5 7.05964 17.9404 6.5 17.25 6.5H6.75ZM8.88574 17.5H15.1143L14.5586 16.5H9.44141L8.88574 17.5Z"/>
PATHS

{
  echo '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 24 24" fill="#fcfcfd">'
  echo "$GLYPH_PATHS"
  echo '</svg>'
} > "$TMP/glyph.svg"

mkdir -p site/public
{
  echo '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 24 24">'
  echo '  <style>'
  echo '    .tile { fill: #1b1d22 }'
  echo '    .glyph { fill: #fcfcfd }'
  echo '    @media (prefers-color-scheme: dark) {'
  echo '      .tile { fill: #ecedef }'
  echo '      .glyph { fill: #161719 }'
  echo '    }'
  echo '  </style>'
  echo '  <rect class="tile" width="24" height="24" rx="5.376" ry="5.376"/>'
  echo '  <g class="glyph" transform="translate(12 12) scale(0.75) translate(-12 -12)">'
  echo "$GLYPH_PATHS"
  echo '  </g>'
  echo '</svg>'
} > site/public/icon.svg

swift - "$TMP/glyph.svg" "$TMP/icon-1024.png" <<'EOF'
import AppKit

let glyphURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size: CGFloat = 1024

let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let radius = size * 0.224
let rounded = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                     cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(rounded)
ctx.clip()

ctx.setFillColor(CGColor(srgbRed: 0x1b / 255, green: 0x1d / 255, blue: 0x22 / 255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// The glyph's ink is 16 of its 24 viewBox units wide, so 0.75 puts its longest
// side at 0.50 of the tile.
guard let glyph = NSImage(contentsOf: glyphURL) else {
    fatalError("Cannot load glyph SVG")
}
let box = size * 0.75
let glyphRect = CGRect(x: (size - box) / 2, y: (size - box) / 2, width: box, height: box)
let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx
glyph.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: outURL)
EOF

ICONSET="App/Sources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" > /dev/null
    d=$((s * 2))
    sips -z $d $d "$TMP/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" > /dev/null
done
sips -Z 512 "$TMP/icon-1024.png" --out site/public/icon-512.png > /dev/null

cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images": [
    { "filename": "icon_16x16.png",     "idiom": "mac", "scale": "1x", "size": "16x16" },
    { "filename": "icon_16x16@2x.png",  "idiom": "mac", "scale": "2x", "size": "16x16" },
    { "filename": "icon_32x32.png",     "idiom": "mac", "scale": "1x", "size": "32x32" },
    { "filename": "icon_32x32@2x.png",  "idiom": "mac", "scale": "2x", "size": "32x32" },
    { "filename": "icon_128x128.png",   "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "filename": "icon_128x128@2x.png","idiom": "mac", "scale": "2x", "size": "128x128" },
    { "filename": "icon_256x256.png",   "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "filename": "icon_256x256@2x.png","idiom": "mac", "scale": "2x", "size": "256x256" },
    { "filename": "icon_512x512.png",   "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "icon_512x512@2x.png","idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
JSON

echo "Wrote $ICONSET, site/public/icon.svg and site/public/icon-512.png"
