#!/usr/bin/env bash
# The local hub's tokens, from pass into ~/.config/hub/local.env (0600), which
# hub-local.service reads: the peer token every local hub shares, and the
# workflow Slack app's two tokens and Saiful's member id once they exist. An
# env file, not a flag, so no token is in argv. A machine without the
# workflow entries in pass skips quietly, and the unit stays off there.
set -uo pipefail

# Root, by whichever route this run can reach (the ladder of 19-dufs-firewall).
run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "hub-local: asking for authorization on screen…" >&2
    timeout 180 pkexec "$@"
  else
    return 1
  fi
}

# Port 8789 from the tailnet's addresses only; the tailnet ACL narrows it to
# the hub port from Saiful's devices and cloud sessions, and every request
# still needs the peer token.
rule='rule family="ipv4" source address="100.64.0.0/10" port port="8789" protocol="tcp" accept'
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null &&
  ! firewall-cmd --query-rich-rule="$rule" >/dev/null 2>&1; then
  if run_root /bin/sh -c "firewall-cmd --quiet --add-rich-rule='$rule' \
      && firewall-cmd --quiet --permanent --add-rich-rule='$rule'"; then
    echo "hub-local: TCP 8789 open to the tailnet (runtime + permanent)"
  else
    echo "hub-local: not authorized — 8789 stays closed to other machines (rerun 'chezmoi apply' in a terminal)" >&2
  fi
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
