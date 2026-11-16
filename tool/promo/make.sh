#!/bin/sh
# Turns frames from capture_test.dart into an Instagram Reel:
#   tool/promo/make.sh <frames dir> <from seconds> <out.mp4>
# The frames are 30 a second from <from> in the song; the song file sits in
# the same folder (the capture downloads it). The video ends on the logo
# card (outro.html) while the music fades out under it.
set -e
cd "$(dirname "$0")"
FRAMES="$1"; FROM="$2"; OUT="$3"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
TMP=$(mktemp -d)

N=$(ls "$FRAMES"/f*.png | wc -l | tr -d ' ')
AUDIO=$(ls "$FRAMES"/*.webm "$FRAMES"/*.m4a 2>/dev/null | head -1)
LEN=$(echo "scale=3; $N / 30" | bc)      # seconds of song on screen
OUTRO=3.5                                # the logo card
XF=0.6                                   # cross-fade into it
TOTAL=$(echo "scale=3; $LEN + $OUTRO - $XF" | bc)
FADE_AT=$(echo "scale=3; $TOTAL - 3" | bc)
XF_AT=$(echo "scale=3; $LEN - $XF" | bc)

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --allow-file-access-from-files --force-device-scale-factor=1 \
  --virtual-time-budget=4000 --window-size=1080,1920 \
  --screenshot="$TMP/outro.png" "file://$PWD/outro.html" >/dev/null 2>&1

ffmpeg -y -v error \
  -framerate 30 -i "$FRAMES/f%05d.png" \
  -loop 1 -framerate 30 -t "$OUTRO" -i "$TMP/outro.png" \
  -ss "$FROM" -t "$TOTAL" -i "$AUDIO" \
  -filter_complex "\
[0:v]format=yuv420p,setsar=1,settb=AVTB,fps=30[a];\
[1:v]scale=1080:1920,format=yuv420p,setsar=1,settb=AVTB,fps=30[b];\
[a][b]xfade=transition=fade:duration=$XF:offset=$XF_AT[v];\
[2:a]aresample=48000,afade=t=in:d=0.3,afade=t=out:st=$FADE_AT:d=3[au]" \
  -map "[v]" -map "[au]" \
  -c:v libx264 -profile:v high -preset slow -crf 17 -pix_fmt yuv420p \
  -r 30 -movflags +faststart \
  -c:a aac -b:a 192k -ar 48000 \
  -t "$TOTAL" "$OUT"

rm -rf "$TMP"
echo "$OUT ($TOTAL s)"
