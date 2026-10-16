#!/usr/bin/env bash
# The local hub's tokens, from pass into ~/.config/hub/local.env (0600), which
# hub-local.service reads: the peer token every local hub shares, and the
# workflow Slack app's two tokens and Saiful's member id once they exist. An
# env file, not a flag, so no token is in argv. A machine without the
# workflow entries in pass skips quietly, and the unit stays off there.
set -uo pipefail
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
