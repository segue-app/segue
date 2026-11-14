#!/bin/sh
# Draws the README pictures from art.html with headless Chrome:
#   tool/readme_art/render.sh            (all)
#   tool/readme_art/render.sh hero:en    (one)
set -e
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
OUT=../../assets/readme
TMP=$(mktemp -d)
mkdir -p "$OUT/en" "$OUT/ru"

size() {
  case "$1" in
    hero) echo 1280,660 ;;
    arch) echo 1280,500 ;;
    btn-*) echo 260,72 ;;
    *) echo 620,470 ;;
  esac
}

one() {
  id=${1%%:*}; lang=${1##*:}
  case "$id" in btn-*) dest="$OUT/$lang/$id.webp" ;; *) dest="$OUT/$lang/$id.webp" ;; esac
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --allow-file-access-from-files --force-device-scale-factor=2 \
    --default-background-color=00000000 --virtual-time-budget=6000 \
    --window-size="$(size "$id")" --screenshot="$TMP/s.png" \
    "file://$PWD/art.html#$id:$lang" >/dev/null 2>&1
  cwebp -quiet -q 90 -alpha_q 100 "$TMP/s.png" -o "$dest"
  echo "$dest"
}

if [ -n "$1" ]; then one "$1"; exit; fi
for lang in en ru; do
  for id in hero wave import lyrics devices sound auto dj lights arch btn-android btn-windows btn-macos btn-linux; do
    one "$id:$lang"
  done
done
