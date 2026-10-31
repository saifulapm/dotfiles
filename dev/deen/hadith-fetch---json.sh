#!/usr/bin/env bash
# The fake download: progress every 150 ms from 20 MB to 38 MB, then the cut that deen-hadith-cut asks for, or the rest, the convert and done.
set -euo pipefail
{
total=123880000
# deen-hadith-nodata stands for a machine with no deen-data: the fetch fails before it starts.
if [ -e "$DOTS_DEV_DIR/deen-hadith-nodata" ]; then
  echo '{"event":"error","message":"cannot read the hadith editions at /home/s/.local/share/deen-data/hadith: run dots update, or set DEEN_SOURCES","done":0,"total":0}'
  exit 1
fi
step() { printf '{"event":"progress","done":%d,"total":%d,"rate":6200000}\n' "$1" "$total"; sleep 0.15; }
for mb in $(seq 20 38); do step $((mb * 1000000)); done
if [ -e "$DOTS_DEV_DIR/deen-hadith-cut" ]; then
  printf '{"event":"error","message":"the connection dropped","done":38000000,"total":%d}\n' "$total"
  exit 1
fi
for mb in 50 70 90 110; do step $((mb * 1000000)); done
step "$total"
echo '{"event":"converting"}'
sleep 0.3
printf '{"event":"done","total":%d}\n' "$total"
echo ready >"$DOTS_DEV_DIR/deen-hadith"
exit
}
