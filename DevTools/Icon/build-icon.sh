#!/bin/bash
# Rasterize AppIcon.svg into the AppIcon.appiconset PNG set with system tools.
#
# `qlmanage` renders through WebKit, which handles the glyph's transform and arc
# segments; ImageMagick's internal MSVG renderer silently drops them (and the
# rsvg-convert delegate isn't installed here).
#
# Only needs to run when the art changes; the PNGs are committed.
set -e
cd "$(dirname "$0")"

SET="../Assets.xcassets/AppIcon.appiconset"
WORK=$(mktemp -d)

qlmanage -t -s 1024 -o "$WORK" AppIcon.svg >/dev/null 2>&1
MASTER="$WORK/AppIcon.svg.png"
[ -f "$MASTER" ] || { echo "qlmanage produced no PNG" >&2; exit 1; }

# size:filename (filename per AppIcon.appiconset/Contents.json)
for spec in 16:icon_16 32:icon_16@2x 32:icon_32 64:icon_32@2x \
            128:icon_128 256:icon_128@2x 256:icon_256 512:icon_256@2x \
            512:icon_512 1024:icon_512@2x; do
    sips -z "${spec%%:*}" "${spec%%:*}" "$MASTER" --out "$SET/${spec##*:}.png" >/dev/null
done

rm -rf "$WORK"
echo "Wrote PNG set to $SET"
