#!/usr/bin/env bash
# Runs `dots install` twice in a fresh fedora:44 container against this checkout's committed branch.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
branch=$(git -C "$here" symbolic-ref --short -q HEAD) || { echo "FAIL: HEAD is detached, check out a branch" >&2; exit 1; }
# A worktree's .git is a file pointing outside the checkout, so the clone source is the shared git dir.
gitdir=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)
name=dots-install-test-$$
home=/home/saiful
log=/var/log/sudo-shim.log
failed=0

# check <description> <command...>: prints PASS or FAIL for the command's status.
check() {
  local what=$1
  shift
  if "$@"; then echo "PASS: $what"; else echo "FAIL: $what"; failed=1; fi
}
as_root() { podman exec -u root "$name" bash -c "$1"; }
# shellcheck disable=SC2329 # called through check
dots_install() {
  podman exec -u saiful -w "$home" -e HOME="$home" -e PATH=/opt/shim:/usr/local/bin:/usr/bin:/bin \
    -e DOTS_REPO=/src.git -e DOTS_BRANCH="$branch" -e DOTS_MACHINE=test \
    "$name" bash /src/bin/dots install
}
snapshot() { as_root "find $home /etc \\( -type f -o -type l \\) -printf '%p %s %T@ %l\\n' | sort"; }

trap 'podman rm -f -t 0 "$name" >/dev/null 2>&1' EXIT
# label=disable lets the container read the checkout without relabelling it on the host.
podman run -d --rm --name "$name" --userns=keep-id --security-opt label=disable \
  --passwd-entry "saiful:*:1000:1000::$home:/bin/bash" \
  -v "$here:/src:ro" -v "$gitdir:/src.git:ro" \
  docker.io/library/fedora:44 sleep infinity >/dev/null || { echo "FAIL: container did not start"; exit 1; }

as_root "
  set -e
  command -v sudo >/dev/null || dnf -y -q install sudo
  mkdir -p $home && chown saiful: $home
  echo 'saiful ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/saiful
  mkdir -p /opt/shim
  printf '#!/bin/bash\necho \"\$*\" >> $log\nexec /usr/bin/sudo \"\$@\"\n' > /opt/shim/sudo
  chmod 755 /opt/shim/sudo
  install -o saiful -m 644 /dev/null $log
  # A v1 machine already has a chezmoi config, pointing at the old repo.
  install -d -o saiful $home/.config $home/.config/chezmoi
  echo 'sourceDir = \"~/.dotfiles\"' > $home/.config/chezmoi/chezmoi.toml
  chown saiful: $home/.config/chezmoi/chezmoi.toml
" || { echo "FAIL: fixture"; exit 1; }

echo "--- first run"
check "first dots install exits 0" dots_install

target=$(podman exec "$name" readlink "$home/.config/quickshell")
check "\$HOME/.config/quickshell links to $home/Sites/github/dotfiles/shell (got '$target')" \
  test "$target" = "$home/Sites/github/dotfiles/shell"

theme=$(podman exec "$name" cat "$home/.local/state/dots/theme" 2>/dev/null)
check "\$HOME/.local/state/dots/theme contains paper (got '$theme')" test "$theme" = paper

check "\$HOME/.local/state/dots/theme-out/shell.json exists" \
  podman exec "$name" test -f "$home/.local/state/dots/theme-out/shell.json"

check "\$HOME/.local/bin/dots-dshift is executable" podman exec "$name" test -x "$home/.local/bin/dots-dshift"

check "saiful is in the input group" podman exec "$name" bash -c "id -nG saiful | tr ' ' '\n' | grep -qx input"

unit=$(podman exec "$name" readlink -f "$home/.config/systemd/user/dots-dshift.service")
check "dots-dshift.service links to the repo unit (got '$unit')" \
  test "$unit" = "$home/Sites/github/dotfiles/home/dot_config/systemd/user/dots-dshift.service"
check "dots-dshift.service runs %h/.local/bin/dots-dshift" \
  podman exec "$name" grep -qx 'ExecStart=%h/.local/bin/dots-dshift' "$home/.config/systemd/user/dots-dshift.service"

clip=$(podman exec "$name" readlink -f "$home/.local/bin/dots-clip-store")
check "\$HOME/.local/bin/dots-clip-store links to the repo script (got '$clip')" \
  test "$clip" = "$home/Sites/github/dotfiles/bin/dots-clip-store"

check "gcc, wl-clipboard, cliphist and wtype are installed" podman exec "$name" rpm -q gcc wl-clipboard cliphist wtype

calls=$(podman exec "$name" cat "$log")
total=$(grep -c . <<<"$calls")
prompting=$(grep -vc '^-n' <<<"$calls")
echo "sudo calls in the first run: $total, of which can prompt: $prompting"
check "sudo log starts with -v and every later call uses -n" \
  test "$(head -n1 <<<"$calls")" = -v -a "$prompting" = 1

before=$(snapshot)
echo "--- second run"
check "second dots install exits 0" dots_install
after=$(snapshot)
check "second run changes no file under $home or /etc" diff <(echo "$before") <(echo "$after")

exit $failed
