#!/bin/sh
# Finishes a video captured by capture_test.dart (streamed to ffmpeg):
# adds the song from <from> seconds and an end card, at the video's size
# and frame rate.
#   tool/promo/finish.sh <video.mp4> <song file> <from s> <card.html> <out.mp4>
set -e
cd "$(dirname "$0")"
VIDEO="$1"; AUDIO="$2"; FROM="$3"; CARD="$4"; OUT="$5"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
TMP=$(mktemp -d)

W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$VIDEO")
H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$VIDEO")
FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$VIDEO")
LEN=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")
OUTRO=3.5                                # the end card
XF=0.6                                   # cross-fade into it
TOTAL=$(echo "scale=3; $LEN + $OUTRO - $XF" | bc)
FADE_AT=$(echo "scale=3; $TOTAL - 3" | bc)
XF_AT=$(echo "scale=3; $LEN - $XF" | bc)

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --allow-file-access-from-files --force-device-scale-factor=1 \
  --virtual-time-budget=4000 --window-size="$W,$H" \
  --screenshot="$TMP/card.png" "file://$PWD/$CARD" >/dev/null 2>&1

ffmpeg -y -v error \
  -i "$VIDEO" \
  -loop 1 -framerate "$FPS" -t "$OUTRO" -i "$TMP/card.png" \
  -ss "$FROM" -t "$TOTAL" -i "$AUDIO" \
  -filter_complex "\
[0:v]format=yuv420p,setsar=1,settb=AVTB,fps=$FPS[a];\
[1:v]scale=$W:$H,format=yuv420p,setsar=1,settb=AVTB,fps=$FPS[b];\
[a][b]xfade=transition=fade:duration=$XF:offset=$XF_AT[v];\
[2:a]aresample=48000,afade=t=in:d=0.3,afade=t=out:st=$FADE_AT:d=3[au]" \
  -map "[v]" -map "[au]" \
  -c:v libx264 -profile:v high -level 5.2 -preset slow -crf 16 \
  -pix_fmt yuv420p -r "$FPS" -movflags +faststart \
  -c:a aac -b:a 256k -ar 48000 \
  -t "$TOTAL" "$OUT"

rm -rf "$TMP"
echo "$OUT (${W}x$H, $FPS fps, $TOTAL s)"
