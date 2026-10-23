#!/usr/bin/env bash
# A v1 machine in a fedora:44 container with a live user manager: v1's units running and its data in place, then dots install, then dots cutover twice.
set -uo pipefail
{
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
branch=$(git -C "$here" symbolic-ref --short -q HEAD) || { echo "FAIL: HEAD is detached, check out a branch" >&2; exit 1; }
gitdir=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)
snap=$(mktemp -d)
git clone -q --bare --single-branch --branch "$branch" "$gitdir" "$snap/src.git" || { echo "FAIL: could not snapshot $branch"; exit 1; }
name=dots-cutover-test-$$
image=localhost/dots-cutover-test:44
home=/home/saiful
failed=0

check() {
  local what=$1
  shift
  if "$@"; then echo "PASS: $what"; else echo "FAIL: $what"; failed=1; fi
}
as_root() { podman exec -u root "$name" bash -c "$1"; }
as_user() {
  podman exec -u saiful -w "$home" -e HOME="$home" -e LANG=C.UTF-8 -e XDG_RUNTIME_DIR=/run/user/1000 \
    -e PATH="$home/.local/bin:/usr/local/bin:/usr/bin:/bin" "$name" bash -c "$1"
}
# put <path>: writes stdin to the user's file; podman exec passes stdin only with -i.
put() { podman exec -i -u saiful "$name" bash -c "cat > $1"; }
# shellcheck disable=SC2329 # called through check
dots_install() {
  git -C "$snap/src.git" show "$branch:bin/dots" |
    podman exec -i -u saiful -w "$home" -e HOME="$home" -e XDG_RUNTIME_DIR=/run/user/1000 -e PATH=/usr/local/bin:/usr/bin:/bin \
      -e DOTS_REPO=/src.git -e DOTS_BRANCH="$branch" -e DOTS_MACHINE=test "$name" bash -s install
}
unit_state() { as_user "echo \$(systemctl --user is-enabled $1 2>/dev/null) \$(systemctl --user is-active $1 2>/dev/null)"; }
snapshot() { as_user "find ~ \\( -type f -o -type l \\) -printf '%p %s %T@ %l\\n' | sort"; }

trap 'podman rm -f -t 0 "$name" >/dev/null 2>&1; rm -rf "$snap"' EXIT
# systemd runs as the container's init, so the image carries it, and procps-ng as every Fedora install does; downloaded rpms stay in the install test's cache volume.
podman volume exists dots-install-dnf-cache || podman volume create dots-install-dnf-cache >/dev/null
cache=$(podman volume inspect dots-install-dnf-cache --format '{{.Mountpoint}}')
printf 'FROM docker.io/library/fedora:44\nRUN echo keepcache=True >> /etc/dnf/dnf.conf && dnf -y -q install systemd sudo procps-ng\nCMD ["/sbin/init"]\n' |
  podman build -q -t "$image" -v "$cache:/var/cache/libdnf5:z" -f - >/dev/null || { echo "FAIL: image did not build"; exit 1; }
# keep-id would start init as saiful, so it runs as root.
podman run -d --name "$name" --user root --systemd=always --userns=keep-id --security-opt label=disable \
  --passwd-entry "saiful:*:1000:1000::$home:/bin/bash" \
  -v "$snap/src.git:/src.git:ro" -v dots-install-dnf-cache:/var/cache/libdnf5 \
  "$image" >/dev/null || { echo "FAIL: container did not start"; exit 1; }

as_root "
  set -e
  until systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'; do sleep 0.2; done
  mkdir -p $home && chown saiful: $home
  echo 'saiful ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/saiful
  loginctl enable-linger saiful
  until systemctl is-active -q user@1000.service; do sleep 0.2; done
" || { echo "FAIL: no user manager"; exit 1; }

# v1 as a machine has it: units linked from ~/.dotfiles and enabled, links that outrank v2, and the shell's data.
as_user '
  set -e
  d=~/.dotfiles/home/dot_config/systemd/user
  mkdir -p $d ~/.config/systemd/user ~/.config/chezmoi ~/.config/fish/conf.d ~/.config/qshell \
    ~/.local/state/qshell/notes/attachments ~/.local/state/qshell/goals ~/.local/share/fish
  echo "sourceDir = \"~/.dotfiles\"" > ~/.config/chezmoi/chezmoi.toml
  for u in qshell hub-local pxy; do printf "[Service]\nExecStart=/bin/sleep infinity\n[Install]\nWantedBy=default.target\n" > $d/$u.service; done
  for u in qshell-sync update-all; do
    printf "[Service]\nType=oneshot\nExecStart=/bin/true\n" > $d/$u.service
    printf "[Timer]\nOnCalendar=daily\n[Install]\nWantedBy=timers.target\n" > $d/$u.timer
  done
  printf "[Service]\nExecStart=/bin/sleep infinity\n[Install]\nWantedBy=graphical-session.target\n" > $d/imapnotify@.service
  for f in $d/*; do ln -s $f ~/.config/systemd/user/; done
  # v1 ran its mail watcher from an instance file of its own, wanted by the graphical session, as on the NUC.
  mkdir -p ~/.config/systemd/user/graphical-session.target.wants
  ln -s $d/imapnotify@.service ~/.config/systemd/user/imapnotify@icloud.service
  ln -s $d/imapnotify@.service ~/.config/systemd/user/graphical-session.target.wants/imapnotify@icloud.service
  systemctl --user daemon-reload
  systemctl --user enable --now qshell.service hub-local.service pxy.service qshell-sync.timer update-all.timer 2>/dev/null
  systemctl --user start imapnotify@icloud.service
  printf "[user]\n\tname = v1\n" > ~/.dotfiles/home/dot_gitconfig
  ln -s ~/.dotfiles/home/dot_gitconfig ~/.gitconfig
  echo "set -g fish_history test_box" > ~/.dotfiles/home/10-history.fish
  ln -s ~/.dotfiles/home/10-history.fish ~/.config/fish/conf.d/10-history.fish
  mkdir -p ~/.dotfiles/home/fish ~/.config/fish/functions ~/.config/fish/completions ~/.local/share/applications
  for f in conf.d/00-env.fish functions/hdl.fish completions/theme-set.fish; do echo "# v1" > ~/.dotfiles/home/fish/${f#*/}; ln -s ~/.dotfiles/home/fish/${f#*/} ~/.config/fish/$f; done
  printf "[Desktop Entry]\nType=Application\nName=X\nExec=webapp-launch https://x.com/\n" > ~/.dotfiles/home/webapp-x.desktop
  ln -s ~/.dotfiles/home/webapp-x.desktop ~/.local/share/applications/webapp-x.desktop
  # v1 linked its environment.d files from ~/.dotfiles, the chromium one carrying its extension flag.
  mkdir -p ~/.dotfiles/home/dot_config/environment.d ~/.config/environment.d
  for f in 60-chromium 65-ssh-agent 70-claude-presence; do
    echo "V1_$f=1" > ~/.dotfiles/home/dot_config/environment.d/$f.conf
    ln -s ~/.dotfiles/home/dot_config/environment.d/$f.conf ~/.config/environment.d/$f.conf
  done
  echo "CHROMIUM_USER_FLAGS=--load-extension=$HOME/.dotfiles/chromium/extensions/copy-url" > ~/.dotfiles/home/dot_config/environment.d/60-chromium.conf
  echo test-box > ~/.config/qshell/machine
  printf "\x89PNG\r\n\x1a\nnot really an image\n" > ~/.local/state/qshell/notes/attachments/paste-1.png
  printf -- "- cmd: ls\n  when: 1760000000\n- cmd: make\n  when: 1760000100\n- cmd: git status\n  when: 1760000200\n" > ~/.local/share/fish/test_box_history
' || { echo "FAIL: v1 fixture"; exit 1; }
put "$home/.local/state/qshell/notes/notes.json" <<EOF
{"version":2,"notes":[
{"id":"0mt0a0001-aaaa","text":"one","path":"","done":false,"updatedAt":"2026-09-01T00:00:00.000Z"},
{"id":"0mt0a0002-aaaa","text":"two","path":"","done":false,"updatedAt":"2026-09-02T00:00:00.000Z"},
{"id":"0mt0a0003-aaaa","text":"three","path":"","done":false,"updatedAt":"2026-09-03T00:00:00.000Z"},
{"id":"0mt0a0004-aaaa","text":"four","path":"","done":true,"updatedAt":"2026-09-04T00:00:00.000Z"},
{"id":"0mt0a0005-aaaa","text":"five","path":"","done":false,"updatedAt":"2026-09-05T00:00:00.000Z"},
{"id":"0mt0a0006-aaaa","text":"six","path":"","done":false,"updatedAt":"2026-09-06T00:00:00.000Z"},
{"id":"0mt0a0007-aaaa","text":"seven","path":"","done":false,"updatedAt":"2026-09-07T00:00:00.000Z"},
{"id":"0mt0a0008-aaaa","text":"eight","path":"","done":false,"updatedAt":"2026-09-08T00:00:00.000Z"},
{"id":"0mt0a0009-aaaa","text":"nine","path":"","done":false,"updatedAt":"2026-09-09T00:00:00.000Z"},
{"id":"0mt0a0010-aaaa","text":"ten","path":"","done":false,"updatedAt":"2026-09-10T00:00:00.000Z"},
{"id":"0mt0a0011-aaaa","text":"","path":"$home/.local/state/qshell/notes/attachments/paste-1.png","done":false,"updatedAt":"2026-09-11T00:00:00.000Z"},
{"id":"0mt0a0012-aaaa","text":"","path":"","done":false,"updatedAt":"2026-09-12T00:00:00.000Z","deletedAt":"2026-09-12T00:00:00.000Z"},
{"id":"0mt0a0013-aaaa","text":"","path":"","done":false,"updatedAt":"2026-09-13T00:00:00.000Z","deletedAt":"2026-09-13T00:00:00.000Z"}
]}
EOF
put "$home/.local/state/qshell/goals/goals.json" <<'EOF'
{"version":1,"goals":[
{"id":"g1","name":"Shipped app","due":"2026-09-22T00:00:00.000Z","state":"shipped","createdAt":"2026-09-10T00:00:00.000Z","updatedAt":"2026-09-26T00:00:00.000Z","shippedAt":"2026-09-26T00:00:00.000Z","tasks":[
{"id":"t1","text":"a","done":true,"updatedAt":"2026-09-20T00:00:00.000Z"},{"id":"t2","text":"b","done":true,"updatedAt":"2026-09-20T00:00:00.000Z"},
{"id":"t3","text":"c","done":true,"updatedAt":"2026-09-20T00:00:00.000Z"},{"id":"t4","text":"d","done":true,"updatedAt":"2026-09-20T00:00:00.000Z"},
{"id":"t5","text":"e","done":true,"updatedAt":"2026-09-20T00:00:00.000Z"},{"id":"t6","text":"f","done":true,"updatedAt":"2026-09-20T00:00:00.000Z"}]},
{"id":"g2","name":"Shipped theme","due":"2026-09-30T00:00:00.000Z","state":"shipped","createdAt":"2026-09-12T00:00:00.000Z","updatedAt":"2026-09-30T00:00:00.000Z","shippedAt":"2026-09-30T00:00:00.000Z","tasks":[]},
{"id":"g3","name":"Active app","due":"2026-11-01T00:00:00.000Z","state":"active","createdAt":"2026-10-01T00:00:00.000Z","updatedAt":"2026-10-02T00:00:00.000Z","tasks":[
{"id":"t7","text":"g","done":false,"updatedAt":"2026-10-02T00:00:00.000Z"},{"id":"t8","text":"h","done":true,"updatedAt":"2026-10-02T00:00:00.000Z"},
{"id":"t9","text":"i","done":false,"updatedAt":"2026-10-02T00:00:00.000Z"}]}
]}
EOF

for u in qshell.service hub-local.service pxy.service qshell-sync.timer update-all.timer imapnotify@icloud.service; do
  got=$(unit_state $u)
  check "v1's $u is enabled and active before the cutover (got '$got')" test "$got" = "enabled active"
done

echo "--- dots install on the v1 machine"
check "dots install exits 0" dots_install

echo "--- dots cutover"
out=$(as_user "Codes/dotfiles/bin/dots cutover" 2>&1)
rc=$?
echo "${out##*$'\n'}"
check "dots cutover exits 0" test $rc = 0
check "dots cutover prints notes: 11 imported · goals: 3 imported" grep -q '^notes: 11 imported · goals: 3 imported · ' <<<"${out##*$'\n'}"

store=$home/.local/share/dots
live=$(as_user "jq '[.notes[] | select(.deleted | not)] | length' $store/notes/test.json")
check "v2's notes store lists 11 live notes (got '$live')" test "$live" = 11
gone=$(as_user "jq '[.notes[] | select(.deleted)] | length' $store/notes/test.json")
check "v1's 2 deleted notes are tombstones (got '$gone')" test "$gone" = 2
sha=$(as_user "jq -r '.notes[] | select(.id == \"0mt0a0011-aaaa\") | .attachments[0].sha256' $store/notes/test.json")
check "the image note's attachment is under its sha256 name with the original bytes" \
  as_user "test \"\$(sha256sum < ~/.local/state/qshell/notes/attachments/paste-1.png | cut -d' ' -f1)\" = $sha && cmp -s ~/.local/state/qshell/notes/attachments/paste-1.png $store/notes/attachments/$sha.png"
goals=$(as_user "jq -c '[([.goals[] | select(.done)] | length), ([.goals[] | select((.done | not) and (.deleted | not))] | length), ([.goals[].tasks[]] | length)]' $store/goals/test.json")
check "2 goals are done, 1 is active, and they hold 9 tasks (got '$goals')" test "$goals" = '[2,1,9]'
entries=$(as_user "grep -c '^- cmd: ' ~/.local/share/fish/fish_history")
check "v1's fish history is in fish_history (got '$entries' entries)" test "$entries" = 3

for u in qshell.service qshell-sync.timer update-all.timer; do
  got=$(unit_state $u)
  check "v1's $u is neither enabled nor active (got '$got')" bash -c "[[ '$got' != enabled* && '$got' != *' active' ]]"
done
for u in pxy hub-local; do
  got=$(as_user "readlink -f \$(systemctl --user show -p FragmentPath --value $u.service)")
  check "$u.service runs from v2's unit (got '$got')" test "$got" = "$home/Codes/dotfiles/home/dot_config/systemd/user/$u.service"
done
got=$(unit_state pxy.service)
check "pxy.service is enabled and active (got '$got')" test "$got" = "enabled active"
got=$(as_user "readlink -f \$(systemctl --user show -p FragmentPath --value imapnotify@icloud.service)")
check "imapnotify@icloud.service loads from v2's template (got '$got')" test "$got" = "$home/Codes/dotfiles/home/dot_config/systemd/user/imapnotify@.service"
got=$(as_user "systemctl --user is-enabled imapnotify@icloud.service")
check "imapnotify@icloud.service stays enabled for the next login (got '$got')" test "$got" = enabled
got=$(as_user "find ~/.config ~/.local/share -type l -lname '*/.dotfiles/*'")
check "no link under ~/.config or ~/.local/share points into ~/.dotfiles (got '$got')" test -z "$got"
got=$(as_user "fish -c 'echo \$fish_history'")
check "fish keeps its history in the default session (got '$got')" test "$got" = default -o -z "$got"
got=$(as_user "systemctl --user is-failed hub-local.service")
check "with no local.env, hub-local.service is inactive, not failed (got '$got')" test "$got" = inactive
# A peer token is all hub local needs to serve; the file goes again before the snapshots below. A tailscale stub first on the unit's PATH says it runs, and records each serve.
put "$home/.local/bin/tailscale" <<'EOF'
#!/bin/sh
[ "$1" = status ] && { echo '{"BackendState":"Running"}'; exit 0; }
echo "$*" >> /tmp/tailscale.log
EOF
as_user "chmod 755 ~/.local/bin/tailscale"
as_user "mkdir -p ~/.config/hub && echo HUB_PEER_TOKEN=test > ~/.config/hub/local.env && systemctl --user start hub-local.service && sleep 3"
got=$(as_user "echo \$(systemctl --user is-active hub-local.service) \$(systemctl --user show -p NRestarts --value hub-local.service)")
check "with local.env present, hub-local.service is active and has not restarted (got '$got')" test "$got" = "active 0"
got=$(as_user "cat /tmp/tailscale.log 2>/dev/null")
check "hub-local's start serves tcp 8789 on the tailnet (got '$got')" test "$got" = "serve --bg --tcp 8789 tcp://localhost:8789"
as_user "systemctl --user stop hub-local.service; rm ~/.config/hub/local.env"
as_user "rm ~/.local/bin/tailscale /tmp/tailscale.log"
got=$(as_user "pgrep -cf '^/bin/sleep infinity\$'")
check "no v1 stand-in (sleep infinity) is left running (got $got)" test "$got" = 0
# A device enables its own Remote Control projects; one whose folder under ~/Codes is missing is skipped, not failed.
check "systemctl --user enable --now claude-rc@nope works on v2's template" as_user "systemctl --user enable --now claude-rc@nope.service 2>/dev/null"
got=$(unit_state claude-rc@nope.service)
check "claude-rc@nope.service is enabled, and with no ~/Codes/nope inactive (got '$got')" test "$got" = "enabled inactive"
got=$(as_user "systemctl --user is-failed claude-rc@nope.service")
check "claude-rc@nope.service is not failed (got '$got')" test "$got" = inactive
as_user "systemctl --user disable claude-rc@nope.service 2>/dev/null"
check "v1's ~/.gitconfig and 10-history.fish links are gone" as_user "test ! -e ~/.gitconfig -a ! -e ~/.config/fish/conf.d/10-history.fish"
check "~/.dotfiles stays in place" as_user "test -f ~/.dotfiles/home/dot_gitconfig"

got=$(as_user "readlink -f ~/.config/environment.d/60-chromium.conf")
check "60-chromium.conf resolves to v2's file (got '$got')" test "$got" = "$home/Codes/dotfiles/home/dot_config/environment.d/60-chromium.conf"
got=$(as_user "readlink -f ~/.config/environment.d/65-ssh-agent.conf")
check "65-ssh-agent.conf resolves to v2's file (got '$got')" test "$got" = "$home/Codes/dotfiles/home/dot_config/environment.d/65-ssh-agent.conf"
as_user "systemctl --user daemon-reload"
env=$(as_user "systemctl --user show-environment")
for flag in --ozone-platform-hint=auto --force-color-profile=srgb OverlayScrollbar AimEnabled; do
  check "show-environment has CHROMIUM_USER_FLAGS with $flag" grep -q "^CHROMIUM_USER_FLAGS=.*$flag" <<<"$env"
done
check "show-environment has no .dotfiles in CHROMIUM_USER_FLAGS" bash -c '! grep "^CHROMIUM_USER_FLAGS=" <<<"$1" | grep -q "\.dotfiles"' _ "$env"
check "show-environment has SSH_AUTH_SOCK in the user's runtime dir" grep -qx 'SSH_AUTH_SOCK=/run/user/1000/ssh-agent.socket' <<<"$env"
got=$(unit_state ssh-agent.socket)
check "ssh-agent.socket is enabled and active (got '$got')" test "$got" = "enabled active"
got=$(as_user "export \$(systemctl --user show-environment | grep ^SSH_AUTH_SOCK=); ssh-add -l >/dev/null 2>&1; echo \$?")
check "ssh-add -l exits 0 or 1 against the agent socket (got '$got')" bash -c '[[ $1 = 0 || $1 = 1 ]]' _ "$got"
got=$(as_user "ls ~/.config/environment.d")
echo "environment.d after the cutover: $(echo $got)"

echo "--- dots cutover again"
before=$(snapshot)
out=$(as_user "Codes/dotfiles/bin/dots cutover" 2>&1)
rc=$?
echo "${out##*$'\n'}"
check "the second dots cutover exits 0" test $rc = 0
check "the second run imports and stops nothing" test "${out##*$'\n'}" = 'notes: 0 imported · goals: 0 imported · history: 0 merged · v1 units: 0 stopped'
check "the second run changes no file under $home" diff <(echo "$before") <(snapshot)

exit $failed
}
