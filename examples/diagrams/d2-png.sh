#!/usr/bin/env bash
# D2 → SVG → PNG without a browser (d2's own PNG export downloads Playwright, which often fails).
# rsvg-convert ignores the WOFF fonts D2 embeds and substitutes a wider font, so labels overrun the gaps D2 cut into
# lines. Fix: let D2 measure with the system's sans-serif TTF and point the SVG at that same font family.
# Usage: d2-png.sh diagram.d2 [out.png] [width-px]   (needs d2, librsvg, fontconfig: pixi add d2 librsvg fontconfig)
# Extra d2 flags via D2_FLAGS, e.g. D2_FLAGS="--theme 0 --pad 20".
set -euo pipefail
in=$1; png=${2:-${in%.d2}.png}; width=${3:-1600}; svg=${png%.*}.svg
font() { fc-match -f '%{file}' "sans-serif:$1"; }   # must be .ttf files (d2 does not read .ttc/.otf)
family=$(fc-match -f '%{family[0]}' sans-serif)
rm -f "$svg"
# shellcheck disable=SC2086
d2 ${D2_FLAGS:-} --font-regular "$(font regular)" --font-italic "$(font italic)" --font-bold "$(font bold)" \
  --font-semibold "$(font bold)" "$in" "$svg" 2>&1 | grep -v '^info: font' >&2 || true
[ -s "$svg" ] || { echo "d2 failed" >&2; exit 1; }
sed -E -i.bak "s/d2-[0-9]+-font-[a-z]+/$family/g" "$svg" && rm -f "$svg.bak"
rsvg-convert -w "$width" -b white "$svg" -o "$png"
echo "$png"
