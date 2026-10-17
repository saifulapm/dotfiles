#!/usr/bin/env bash
# Joins this machine's memory to the mem store on Cloudflare, once. When the
# local hub's env file (run_after_39-hub-local writes it from pass) has no
# HUB_STORE_TOKEN, `workflow switch` mints this machine's token, seeds the
# store, switches mem to it, writes the store's keys beside the ones 39
# wrote and restarts hub-local. After 46-workflow, which builds the binaries
# it runs. A fresh mem catches up from the store through the local hub.
#
# A machine without the workflow entries in pass has no env file and skips
# quietly. A refused switch (the store's import budget for the day is spent)
# is tried again on the next apply.
set -uo pipefail

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

store="wss://mem.on-rexa.com/store/share"
env=$HOME/.config/hub/local.env

[ -f "$env" ] || exit 0
command -v workflow >/dev/null 2>&1 || exit 0
grep -q '^HUB_STORE_TOKEN=' "$env" && exit 0

workflow switch --store "$store"
case $? in
0) ;;
2) echo "workflow-store: workflow switch refused; the next chezmoi apply tries again" >&2 ;;
*) echo "workflow-store: workflow switch failed; the next chezmoi apply tries again" >&2 ;;
esac

# A hub that cannot start on what local.env holds restarts every 5 s; say so
# here instead of leaving it to the journal.
sleep 3
systemctl --user is-active --quiet hub-local.service ||
  echo "workflow-store: hub-local is not running: journalctl --user -u hub-local" >&2
exit 0
