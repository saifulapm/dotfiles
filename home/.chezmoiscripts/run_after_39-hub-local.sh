#!/usr/bin/env bash
# The local hub's tokens, from pass into ~/.config/hub/local.env (0600), which
# hub-local.service reads: the peer token every local hub shares, and the
# workflow Slack app's two tokens and Saiful's member id once they exist. An
# env file, not a flag, so no token is in argv. Every other line in the file
# stays as it was: the store's keys are `workflow switch`'s, which
# run_after_47-workflow-store runs once the binaries are built. A machine
# without the workflow entries in pass skips quietly, and the unit stays off
# there.
set -uo pipefail

# Port 8789 on this machine's tailnet address, handed to the hub on
# loopback by tailscaled itself: no firewall rule and no root (the user is
# tailscale's operator), and the port never faces another network. The
# tailnet ACL narrows who may dial it; every request still needs the peer
# token.
if command -v tailscale >/dev/null 2>&1 &&
  ! tailscale serve status 2>/dev/null | grep -q 'tcp://localhost:8789\|127.0.0.1:8789'; then
  tailscale serve --bg --tcp 8789 tcp://localhost:8789 >/dev/null ||
    echo "hub-local: tailscale serve --tcp 8789 failed; other machines cannot reach this hub" >&2
fi

command -v pass >/dev/null || exit 0
token=$(pass show workflow/hub-peer-token 2>/dev/null) || exit 0
[ -n "$token" ] || exit 0

env=$HOME/.config/hub/local.env
mkdir -p "$(dirname "$env")"
new=$(mktemp "$env.XXXXXX")
chmod 600 "$new"
{
  printf 'HUB_PEER_TOKEN=%s\n' "$token"
  v=$(pass show workflow/slack-bot-token 2>/dev/null) && printf 'SLACK_BOT_TOKEN=%s\n' "$v"
  v=$(pass show workflow/slack-app-token 2>/dev/null) && printf 'SLACK_APP_TOKEN=%s\n' "$v"
  v=$(pass show workflow/slack-user-id 2>/dev/null || pass show dulali/slack-user-id 2>/dev/null) &&
    printf 'SLACK_USER_ID=%s\n' "$v"
  [ -f "$env" ] && grep -Ev '^(HUB_PEER_TOKEN|SLACK_BOT_TOKEN|SLACK_APP_TOKEN|SLACK_USER_ID)=' "$env"
} >"$new"

changed=
if cmp -s "$new" "$env"; then
  rm -f "$new"
else
  mv -f "$new" "$env"
  changed=1
fi
systemctl --user daemon-reload
systemctl --user enable hub-local.service >/dev/null 2>&1 || true
if [ -n "$changed" ]; then
  systemctl --user restart hub-local.service
else
  systemctl --user start hub-local.service
fi
