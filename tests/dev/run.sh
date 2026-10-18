#!/usr/bin/env bash
# Runs every nested-session check in tests/dev, one nested niri each.
cd "$(dirname "$0")" || exit 1
failed=0
for t in *.sh; do
  [ "$t" = lib.sh ] || [ "$t" = run.sh ] && continue
  echo "== $t"
  bash "$t" || failed=1
done
exit "$failed"
