#!/usr/bin/env bash
# Runs every nested-session check in tests/dev, one nested niri each.
{
cd "$(dirname "$0")" || exit 1
# One list feeds both the run and --list, so what --list prints is what runs; a lib*.sh is a helper.
checks() {
  for t in *.sh; do
    case $t in lib*.sh | run.sh) continue ;; esac
    echo "$t"
  done
}
if [ "${1:-}" = --list ]; then
  checks
  exit 0
fi
# The whole run takes too long for a milestone (rulings E0V8P91Y, 9Q8N1A7A), so an agent runs it only when Saiful asks for it.
if [ -n "${CLAUDECODE:-}" ] && [ "${DOTS_DEV_ALL:-}" != 1 ]; then
  echo "tests/dev/run.sh: an agent runs only the tests/dev scripts its change touches; DOTS_DEV_ALL=1 runs them all, when Saiful asks" >&2
  exit 1
fi
failed=0
for t in $(checks); do
  echo "== $t"
  bash "$t" || failed=1
done
exit "$failed"
}
