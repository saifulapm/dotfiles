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
# The committed bin/dots goes in on stdin, as the curl one-liner sends it, so an edit to the checkout cannot reach a run.
dots_install() {
  git -C "$here" show "$branch:bin/dots" |
    podman exec -i -u saiful -w "$home" -e HOME="$home" -e PATH=/opt/shim:/usr/local/bin:/usr/bin:/bin \
      -e DOTS_REPO=/src.git -e DOTS_BRANCH="$branch" -e DOTS_MACHINE=test \
      "$name" bash -s install
}
as_user() {
  podman exec -u saiful -w "$home" -e HOME="$home" -e PATH="/opt/shim:$home/.local/bin:/usr/local/bin:/usr/bin:/bin" "$name" bash -c "$1"
}
# committed <file>: the file as the branch under test has it.
committed() { git -C "$here" show "$branch:$1"; }
# One "name<TAB>version<TAB>check" line per versions.toml pin that has a check command.
pins() {
  committed versions.toml | awk -F' = ' '
    function flush() { if (n != "" && c != "") print n "\t" v "\t" c }
    /^\[\[pin\]\]/ { flush(); n = v = c = ""; next }
    $1 == "name" { n = $2 } $1 == "version" { v = $2 } $1 == "check" { c = $2 }
    END { flush() }' | tr -d '"'
}
# Every packages.toml name for the container's arch.
packages() {
  local arch
  arch=$(podman exec "$name" uname -m)
  committed packages.toml | awk -v arch="$arch" -F' = ' '
    function flush() { if (n != "" && (a == "all" || a == arch)) print n }
    /^\[\[package\]\]/ { flush(); n = a = ""; next }
    { gsub(/"/, "", $2) }
    $1 == "name" { n = $2 } $1 == "arch" { a = $2 }
    END { flush() }'
}
snapshot() { as_root "find $home /etc \\( -type f -o -type l \\) -printf '%p %s %T@ %l\\n' | sort"; }

trap 'podman rm -f -t 0 "$name" >/dev/null 2>&1' EXIT
# label=disable lets the container read the checkout without relabelling it on the host.
podman run -d --rm --name "$name" --userns=keep-id --security-opt label=disable \
  --passwd-entry "saiful:*:1000:1000::$home:/bin/bash" \
  -v "$here:/src:ro" -v "$gitdir:/src.git:ro" -v dots-install-dnf-cache:/var/cache/libdnf5 \
  docker.io/library/fedora:44 sleep infinity >/dev/null || { echo "FAIL: container did not start"; exit 1; }

as_root "
  set -e
  # Downloaded rpms stay in the cache volume, so the next run fetches only what changed.
  echo keepcache=True >> /etc/dnf/dnf.conf
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

# The lock authenticates through dots-lock, and PAM's other service denies every password, so a missing file would lock the user out.
check "/etc/pam.d/dots-lock includes system-auth" podman exec "$name" grep -qx 'auth include system-auth' /etc/pam.d/dots-lock
check "logind leaves the lid to niri" podman exec "$name" grep -qx 'HandleLidSwitch=ignore' /etc/systemd/logind.conf.d/dots-lid.conf

check "gcc, wl-clipboard, cliphist and wtype are installed" podman exec "$name" rpm -q gcc wl-clipboard cliphist wtype

# shellcheck disable=SC2046 # one word per package
check "every packages.toml entry for this arch is installed" podman exec "$name" rpm -q --quiet $(packages)
while IFS=$'\t' read -r pin version cmd; do
  out=$(as_user "$cmd" 2>&1)
  check "$pin: '$cmd' prints $version (got '${out%%$'\n'*}')" grep -qF -- "$version" <<<"$out"
done < <(pins)
for font in 'Maple Mono' 'Symbols Nerd Font Mono'; do
  got=$(as_user "fc-match -f '%{family[0]}' '$font'")
  check "fontconfig finds $font (got '$got')" test "$got" = "$font"
done

check "tty1 logs saiful straight in" podman exec "$name" grep -q -- '--autologin saiful' /etc/systemd/system/getty@tty1.service.d/autologin.conf
shell=$(podman exec "$name" getent passwd saiful | cut -d: -f7)
check "fish is saiful's login shell (got '$shell')" test "$shell" = /usr/bin/fish
check "foot reads its config" as_user "foot --check-config"
check "tmux reads its config" as_user "tmux -L check start-server \\; kill-server"
# yazi reads the terminal's size before its config, so it needs a tty.
check "yazi reads its config" podman exec -t -u saiful -e HOME="$home" "$name" "$home/.local/bin/yazi" --debug

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

echo "--- dots update with nothing new"
as_root ": > $log"
out=$(as_user "Sites/github/dotfiles/bin/dots update" 2>&1)
rc=$?
echo "${out##*$'\n'}"
check "dots update exits 0" test $rc = 0
check "dots update ends with dnf: N upgraded · pins: 0 changed" grep -qE '^dnf: [0-9]+ upgraded · pins: 0 changed$' <<<"${out##*$'\n'}"
calls=$(podman exec "$name" cat "$log")
check "dots update's sudo log starts with -v and every later call uses -n" \
  test "$(head -n1 <<<"$calls")" = -v -a "$(grep -vc '^-n' <<<"$calls")" = 1

echo "--- dots update after a pin moved"
# The repo's working copy takes the older yazi release, as a pulled bump would bring a newer one.
as_user "cd ~/Sites/github/dotfiles && sed -i -e 's/^version = \"26.9.1\"/version = \"26.8.15\"/' \\
  -e 's/02807f08d6b589b65b7516a4e259d83f5995d7a23bb12b3a155141385b370b3a/f5a85771f06bb0e8c488136ae0aedaec8d341a7cee995549df391d7d852fe8d1/' \\
  -e 's/a02fe91d3304294048c681f010f1100856872a4e98ecf6927328e888d40a6ad2/cc67eb7991550c2f9407cda52d3f5af0937627aa6884e7de99a04fcf059807e0/' versions.toml"
out=$(as_user "Sites/github/dotfiles/bin/dots update" 2>&1)
check "dots update reinstalls only yazi" test "$(grep -c '^dots: pin ' <<<"$out")" = 1 -a "$(grep -c '^dots: pin yazi 26.8.15$' <<<"$out")" = 1
check "dots update ends with pins: 1 changed (got '${out##*$'\n'}')" grep -qE '^dnf: [0-9]+ upgraded · pins: 1 changed$' <<<"${out##*$'\n'}"
check "yazi is now 26.8.15" as_user "yazi --version | grep -q 26.8.15"

echo "--- dots install with a tampered pin"
as_user "cd ~/Sites/github/dotfiles && sed -i 's/f5a85771f06bb0e8c488136ae0aedaec8d341a7cee995549df391d7d852fe8d1/$(printf '0%.0s' {1..64})/; s/cc67eb7991550c2f9407cda52d3f5af0937627aa6884e7de99a04fcf059807e0/$(printf '0%.0s' {1..64})/' versions.toml"
out=$(dots_install 2>&1)
rc=$?
check "dots install refuses the tampered pin (exit $rc)" test $rc != 0
check "the refusal names the pin" grep -q 'pin yazi: sha256' <<<"$out"
check "yazi stays 26.8.15" as_user "yazi --version | grep -q 26.8.15"

exit $failed
