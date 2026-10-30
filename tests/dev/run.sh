#!/usr/bin/env bash
# Runs every nested-session check in tests/dev, one nested niri each.
{
# The whole run takes too long for a milestone (rulings E0V8P91Y, 9Q8N1A7A), so an agent runs it only when Saiful asks for it.
if [ -n "${CLAUDECODE:-}" ] && [ "${DOTS_DEV_ALL:-}" != 1 ]; then
  echo "tests/dev/run.sh: an agent runs only the tests/dev scripts its change touches; DOTS_DEV_ALL=1 runs them all, when Saiful asks" >&2
  exit 1
fi
cd "$(dirname "$0")" || exit 1
failed=0
for t in *.sh; do
  [ "$t" = lib.sh ] || [ "$t" = run.sh ] && continue
  echo "== $t"
  bash "$t" || failed=1
done
exit "$failed"
}
