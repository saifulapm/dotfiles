#!/usr/bin/env bash
# The fake's corpus is ready once a fetch has run to its end, else partial at the 38 MB a cut fetch keeps.
set -euo pipefail
{
dir=$HOME/.local/share/deen/hadith
if [ "$(cat "$DOTS_DEV_DIR/deen-hadith" 2>/dev/null)" = ready ]; then
  printf '{"state":"ready","done":0,"total":0,"dir":"%s"}\n' "$dir"
else
  printf '{"state":"partial","done":38000000,"total":123880000,"dir":"%s"}\n' "$dir"
fi
exit
}
