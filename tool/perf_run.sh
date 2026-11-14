#!/bin/bash
# Runs the profile build of tool/perf_main.dart and prints CPU per scene.
# The window shows for about a minute; nothing plays.
APP="${1:-$(dirname "$0")/../build/macos/Build/Products/Profile/Segue.app}"
TMP=$(mktemp -d)
L=$TMP/log; C=$TMP/cpu
"$APP/Contents/MacOS/Segue" > "$L" 2>&1 &
P=$!
while kill -0 $P 2>/dev/null; do
  t=$(ps -o time= -p $P 2>/dev/null | tr -d ' ')
  [ -n "$t" ] && echo "$(python3 -c 'import time;print(int(time.time()*1000))') $t" >> "$C"
  sleep 0.5
done
python3 - "$L" "$C" <<'PY'
import sys
def secs(t):
    parts = t.replace(',', '.').split(':')
    s = 0.0
    for p in parts: s = s * 60 + float(p)
    return s
cpu = [(int(a), secs(b)) for a, b in (l.split() for l in open(sys.argv[2]) if len(l.split()) == 2)]
for l in open(sys.argv[1]):
    if 'PERF|' not in l or 'done' in l: continue
    _, name, st, en = l.strip().split('PERF|')[1].split('|') and [''] + l.strip().split('PERF|')[1].split('|')
    st, en = int(st), int(en)
    inside = [c for c in cpu if st <= c[0] <= en]
    pct = (inside[-1][1] - inside[0][1]) / ((inside[-1][0] - inside[0][0]) / 1000) * 100 if len(inside) > 1 else -1
    print(f"{name:10s} CPU {pct:5.1f}%")
PY
