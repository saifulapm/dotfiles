#!/usr/bin/env bash
# Runs `dots install` twice in a fresh fedora:44 container against this checkout's committed branch.
set -uo pipefail
# bash reads a script as it runs it, so the whole body sits in one block it parses before the first command; an edit mid-run cannot reach it.
{
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
branch=$(git -C "$here" symbolic-ref --short -q HEAD) || { echo "FAIL: HEAD is detached, check out a branch" >&2; exit 1; }
# A worktree's .git is a file pointing outside the checkout, so the clone source is the shared git dir.
gitdir=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)
# The branch as it is now, so a commit made during the run reaches neither the clone nor dots update's pull.
snap=$(mktemp -d)
git clone -q --bare --single-branch --branch "$branch" "$gitdir" "$snap/src.git" || { echo "FAIL: could not snapshot $branch"; exit 1; }
name=dots-install-test-$$
home=/home/saiful
log=/var/log/sudo-shim.log
curl_log=/var/log/curl-shim.log
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
  git -C "$snap/src.git" show "$branch:bin/dots" |
    podman exec -i -u saiful -w "$home" -e HOME="$home" -e PATH=/opt/shim:/usr/local/bin:/usr/bin:/bin \
      -e DOTS_REPO=/src.git -e DOTS_BRANCH="$branch" -e DOTS_MACHINE=test \
      "$name" bash -s install
}
as_user() {
  podman exec -u saiful -w "$home" -e HOME="$home" -e LANG=C.UTF-8 -e PATH="/opt/shim:$home/.local/bin:/usr/local/bin:/usr/bin:/bin" "$name" bash -c "$1"
}
# committed <file>: the file as the branch under test has it.
committed() { git -C "$snap/src.git" show "$branch:$1"; }
# One "name<TAB>version<TAB>check" line per versions.toml pin that has a check command.
pins() {
  committed versions.toml | awk -F' = ' '
    function flush() { if (n != "" && c != "") print n "\t" v "\t" c }
    /^\[\[pin\]\]/ { flush(); n = v = c = ""; next }
    $1 == "name" { n = $2 } $1 == "version" { v = $2 } $1 == "check" { c = $2 }
    END { flush() }' | tr -d '"'
}
# One "name<TAB>command" line per pin whose runs command only has to exit 0.
runs() {
  committed versions.toml | awk -F' = ' '
    /^\[\[pin\]\]/ { n = ""; next }
    $1 == "name" { n = $2 } $1 == "runs" { print n "\t" $2 }' | tr -d '"'
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

trap 'podman rm -f -t 0 "$name" >/dev/null 2>&1; rm -rf "$snap"' EXIT
# label=disable lets the container read the checkout without relabelling it on the host.
podman run -d --rm --name "$name" --userns=keep-id --security-opt label=disable \
  --passwd-entry "saiful:*:1000:1000::$home:/bin/bash" \
  -v "$snap/src.git:/src.git:ro" -v dots-install-dnf-cache:/var/cache/libdnf5 -v dots-install-cargo-cache:$home/.cargo:U -v dots-install-rustup-cache:$home/.rustup:U \
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
  printf '#!/bin/bash\necho \"\$*\" >> $curl_log\nexec /usr/bin/curl \"\$@\"\n' > /opt/shim/curl
  chmod 755 /opt/shim/curl
  install -o saiful -m 644 /dev/null $curl_log
  # v1 capped the journal at 200M.
  mkdir -p /etc/systemd/journald.conf.d
  printf '[Journal]\nSystemMaxUse=200M\n' > /etc/systemd/journald.conf.d/50-size-cap.conf
  # A v1 machine already has a chezmoi config, pointing at the old repo.
  install -d -o saiful $home/.config $home/.config/chezmoi
  echo 'sourceDir = \"~/.dotfiles\"' > $home/.config/chezmoi/chezmoi.toml
  chown saiful: $home/.config/chezmoi/chezmoi.toml
" || { echo "FAIL: fixture"; exit 1; }

echo "--- first run"
check "first dots install exits 0" dots_install
installs=$(podman exec "$name" grep -c 'claude.ai/install.sh' "$curl_log")
check "first run runs the Claude installer once (got $installs)" test "$installs" = 1

target=$(podman exec "$name" readlink "$home/.config/quickshell")
check "\$HOME/.config/quickshell links to $home/Codes/dotfiles/shell (got '$target')" \
  test "$target" = "$home/Codes/dotfiles/shell"

theme=$(podman exec "$name" cat "$home/.local/state/dots/theme" 2>/dev/null)
check "\$HOME/.local/state/dots/theme contains paper (got '$theme')" test "$theme" = paper
mode=$(podman exec "$name" stat -c %a "$home/.local/state/dots")
check "\$HOME/.local/state/dots is private to the user (got $mode)" test "$mode" = 700

check "\$HOME/.local/state/dots/theme-out/shell.json exists" \
  podman exec "$name" test -f "$home/.local/state/dots/theme-out/shell.json"

check "\$HOME/.local/bin/dots-dshift is executable" podman exec "$name" test -x "$home/.local/bin/dots-dshift"

check "saiful is in the input group" podman exec "$name" bash -c "id -nG saiful | tr ' ' '\n' | grep -qx input"

unit=$(podman exec "$name" readlink -f "$home/.config/systemd/user/dots-dshift.service")
check "dots-dshift.service links to the repo unit (got '$unit')" \
  test "$unit" = "$home/Codes/dotfiles/home/dot_config/systemd/user/dots-dshift.service"
check "dots-dshift.service runs %h/.local/bin/dots-dshift" \
  podman exec "$name" grep -qx 'ExecStart=%h/.local/bin/dots-dshift' "$home/.config/systemd/user/dots-dshift.service"

clip=$(podman exec "$name" readlink -f "$home/.local/bin/dots-clip-store")
check "\$HOME/.local/bin/dots-clip-store links to the repo script (got '$clip')" \
  test "$clip" = "$home/Codes/dotfiles/bin/dots-clip-store"

# The lock authenticates through dots-lock, and PAM's other service denies every password, so a missing file would lock the user out.
check "/etc/pam.d/dots-lock includes system-auth" podman exec "$name" grep -qx 'auth include system-auth' /etc/pam.d/dots-lock
check "logind leaves the lid to niri" podman exec "$name" grep -qx 'HandleLidSwitch=ignore' /etc/systemd/logind.conf.d/dots-lid.conf
check "logind leaves the power key to niri" podman exec "$name" grep -qx 'HandlePowerKey=ignore' /etc/systemd/logind.conf.d/dots-lid.conf
check "sysctl sets BBR over fq" podman exec "$name" bash -c "grep -qx 'net.ipv4.tcp_congestion_control = bbr' /etc/sysctl.d/99-tcp-bbr.conf && grep -qx 'net.core.default_qdisc = fq' /etc/sysctl.d/99-tcp-bbr.conf"
check "tcp_bbr and sch_fq load at boot" podman exec "$name" bash -c "grep -qx tcp_bbr /etc/modules-load.d/tcp-bbr.conf && grep -qx sch_fq /etc/modules-load.d/tcp-bbr.conf"

check "gcc, wl-clipboard, cliphist and wtype are installed" podman exec "$name" rpm -q gcc wl-clipboard cliphist wtype

# shellcheck disable=SC2046 # one word per package
check "every packages.toml entry for this arch is installed" podman exec "$name" rpm -q --quiet $(packages)
# rpm -q matches by name, so ffmpeg-free cannot pass for RPM Fusion's ffmpeg.
out=$(podman exec "$name" rpm -q chromium tailscale wf-recorder ffmpeg)
rc=$?
check "rpm -q chromium tailscale wf-recorder ffmpeg prints 4 versions (exit $rc, got '$out')" test "$rc" = 0 -a "$(grep -c . <<<"$out")" = 4
# The NUC's wifi firmware, VA driver and vainfo are for x86_64 alone.
out=$(podman exec "$name" rpm -q iwlwifi-mvm-firmware intel-media-driver libva-utils)
rc=$?
if [ "$(uname -m)" = x86_64 ]; then
  check "rpm -q iwlwifi-mvm-firmware intel-media-driver libva-utils prints 3 versions (exit $rc, got '$out')" test "$rc" = 0 -a "$(grep -vc 'not installed' <<<"$out")" = 3
else
  check "none of iwlwifi-mvm-firmware, intel-media-driver and libva-utils is installed on $(uname -m) (got '$out')" test "$(grep -c 'is not installed' <<<"$out")" = 3
fi
while IFS=$'\t' read -r pin version cmd; do
  out=$(as_user "$cmd" 2>&1)
  check "$pin: '$cmd' prints $version (got '${out%%$'\n'*}')" grep -qF -- "$version" <<<"$out"
done < <(pins)
while IFS=$'\t' read -r pin cmd; do
  check "$pin: '$cmd' exits 0" as_user "$cmd >/dev/null"
done < <(runs)
claude=$(as_user "claude --version" 2>&1)
check "claude --version prints a version (got '$claude')" grep -qE '^[0-9]+\.[0-9]+\.[0-9]+' <<<"$claude"
pi=$(as_user "fish -c 'pi --version'" 2>&1)
# sort -V puts any word after a number, so the output must be a version before it is compared.
check "pi --version prints 1.3.0 or newer (got '$pi')" bash -c "[[ \$1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\$ && \$(printf '%s\n' 1.3.0 \"\$1\" | sort -V | head -n1) == 1.3.0 ]]" _ "$pi"
check "mise lists node 24.21.0 as installed" as_user "mise ls --installed node | grep -qw 24.21.0"
shopify=$(as_user "mise exec -- shopify version" 2>&1 | tail -n 1)
check "shopify version prints 4.9.4 or newer (got '$shopify')" bash -c "[[ \$1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\$ && \$(printf '%s\n' 4.9.4 \"\$1\" | sort -V | head -n1) == 4.9.4 ]]" _ "$shopify"
for tool in "pnpm --version" "cloudflared --version" "goimapnotify -h"; do
  check "'$tool' runs through mise" as_user "mise exec -- $tool >/dev/null 2>&1"
done
for tool in "delta --version" "difft --version" "tree --version" "yq --version" "glow --version" "gum --version" "tokei --version" "trash-put --version" "shellcheck --version" "gm version" "dig -v" "uv --version"; do
  check "'$tool' exits 0" as_user "$tool >/dev/null 2>&1"
done
for tool in "sd --version" "tv --version" "hurl --version" "sg --version" "usql --version" "bun --version"; do
  check "'$tool' exits 0 through mise" as_user "mise exec -- $tool >/dev/null 2>&1"
done
check "rustup --version exits 0" as_user "~/.cargo/bin/rustup --version >/dev/null 2>&1"
rustc=$(as_user "fish -c 'command -v rustc'" 2>&1)
check "fish finds rustup's rustc first (got '$rustc')" test "$rustc" = "$home/.cargo/bin/rustc"
check "Fedora's rustc stays for the pins" as_user "test -x /usr/bin/rustc"
docker=$(as_user "docker --version" 2>&1)
check "docker --version names podman (got '$docker')" grep -q podman <<<"$docker"
check "eza is not installed" as_user "! command -v eza"
check "goimapnotify has the shim imapnotify@ runs" as_user "test -x ~/.local/share/mise/shims/goimapnotify"
# kakfeed is private, so elfeed-kak waits for the gh login dots secrets writes.
check "elfeed-kak waits for dots secrets" as_user "test ! -e ~/.local/bin/elfeed-kak"
check "the AVD firmware is left to the Macs' hosts" podman exec "$name" bash -c "! ls /usr/lib/firmware/updates/apple/avd-fw-* >/dev/null 2>&1"
check "the input group may open /dev/uinput" podman exec "$name" grep -q 'KERNEL=="uinput", GROUP="input"' /etc/udev/rules.d/60-uinput-input-group.rules
check "ydotoold starts with the user manager" as_user "test -L ~/.config/systemd/user/default.target.wants/ydotoold.service"
# The container runs no user manager, so systemctl reads the unit files offline.
enabled=$(as_user "systemctl --user --root=/ is-enabled ydotoold" 2>&1)
check "systemctl --user is-enabled ydotoold prints enabled (got '$enabled')" test "$enabled" = enabled
check "dots-taildrop starts with the user manager" as_user "test -L ~/.config/systemd/user/default.target.wants/dots-taildrop.service"
enabled=$(as_user "systemctl --user --root=/ is-enabled dots-taildrop" 2>&1)
check "systemctl --user is-enabled dots-taildrop prints enabled (got '$enabled')" test "$enabled" = enabled
# The unit runs the receiver from ~/.local/bin with the user manager's PATH, which reaches /usr/bin's node and not mise's.
check "the Taildrop receiver is linked into ~/.local/bin and its node is /usr/bin's" as_user "test -x ~/.local/bin/dots-taildrop && test -x /usr/bin/node"
tools=$(as_user "command -v grim slurp wlrctl ydotool tesseract wtype" 2>&1)
check "the desktop skill's six tools are on PATH (got $(wc -l <<<"$tools"): $(tr '\n' ' ' <<<"$tools"))" test "$(grep -c '^/' <<<"$tools")" = 6
oomd=$(podman exec "$name" systemctl is-enabled systemd-oomd.service systemd-oomd.socket 2>&1)
check "systemd-oomd.service and .socket are masked (got '$(tr '\n' ' ' <<<"$oomd")')" test "$oomd" = $'masked\nmasked'
check "no journald drop-in caps the journal at 200M" podman exec "$name" bash -c "! grep -rqx 'SystemMaxUse=200M' /etc/systemd/journald.conf.d"
check "the container has no Wi-Fi power-save file" podman exec "$name" test ! -e /etc/NetworkManager/conf.d/wifi-powersave-off.conf
check "the container has no HDA power-save option" podman exec "$name" test ! -e /etc/modprobe.d/hda-power-save.conf
if podman exec "$name" test -d /sys/module/snd_hda_intel; then
  check "with snd_hda_intel loaded, the wireplumber keepalive is installed" as_user "grep -q 'dither.noise = 2' ~/.config/wireplumber/wireplumber.conf.d/sink-keepalive.conf"
else
  check "without snd_hda_intel, there is no wireplumber keepalive" as_user "test ! -e ~/.config/wireplumber/wireplumber.conf.d/sink-keepalive.conf"
fi
check "zswap compresses with zstd from boot" podman exec "$name" bash -c "grep -qx zstd /etc/modules-load.d/zstd.conf && grep -q 'zswap/parameters/compressor - - - - zstd' /etc/tmpfiles.d/zswap.conf"
check "gpg-agent caches a passphrase for 400 days" as_user "grep -qx 'default-cache-ttl 34560000' ~/.gnupg/gpg-agent.conf && grep -qx 'max-cache-ttl 34560000' ~/.gnupg/gpg-agent.conf"
check "imapnotify@icloud starts with the session" as_user "test -L ~/.config/systemd/user/graphical-session.target.wants/imapnotify@icloud.service"
check "the mailto handler is mail-open" as_user "grep -qx 'x-scheme-handler/mailto=mail-open.desktop' ~/.config/mimeapps.list && test -f ~/.local/share/applications/mail-open.desktop"
cx=$(as_user "fish -i -c 'functions cx'" 2>&1)
check "fish's cx runs claude --allow-dangerously-skip-permissions" grep -qF 'claude --allow-dangerously-skip-permissions' <<<"$cx"
check "the repo is at ~/Codes/dotfiles" as_user "test -x ~/Codes/dotfiles/bin/dots"
dirt=$(as_user "git -C ~/Codes/dotfiles status --porcelain")
check "the apply leaves the repo clean (got '$dirt')" test -z "$dirt"
for font in 'Maple Mono' 'Symbols Nerd Font Mono'; do
  got=$(as_user "fc-match -f '%{family[0]}' '$font'")
  check "fontconfig finds $font (got '$got')" test "$got" = "$font"
done

err=$(as_user "fish -c 'echo ok'" 2>&1 >/dev/null)
out=$(as_user "fish -c 'echo ok'" 2>/dev/null)
check "fish -c 'echo ok' prints ok and nothing else (got '$out', stderr '$err')" test "$out" = ok -a -z "$err"
excludes=$(as_user "git config --get-all --path core.excludesFile")
check "git has one excludes file, under ~/.config/git (got '$excludes')" test "$excludes" = "$home/.config/git/ignore"
pager=$(as_user "git config --global core.pager")
check "git pages through delta (got '$pager')" test "$pager" = delta
check "git dft diffs two commits" as_user "rm -rf /tmp/dft && git init -q /tmp/dft && cd /tmp/dft && echo a > a && git add a && git -c user.name=t -c user.email=t@t commit -qm 1 && echo b >> a && git -c user.name=t -c user.email=t@t commit -qam 2 && git dft HEAD~1 | grep -q 'a --- Text'"
check "claude's settings render with its hooks" as_user "jq -e .hooks ~/.claude/settings.json >/dev/null"
for s in mem plan orchestrate grill tdd diagnose dogfood amx playwright-cli desktop; do
  check "\$HOME/.claude/skills/$s/SKILL.md exists" as_user "test -f ~/.claude/skills/$s/SKILL.md"
done
for a in implementer reviewer scout dogfooder code-reviewer security-reviewer desktop-operator browser-operator; do
  check "\$HOME/.claude/agents/$a.md exists" as_user "test -f ~/.claude/agents/$a.md"
done
for e in amx.ts amx-subagent.ts mem.ts pxy.ts; do
  check "\$HOME/.pi/agent/extensions/$e exists" as_user "test -f ~/.pi/agent/extensions/$e"
done
check "pi's pxy extension has every placeholder filled" as_user "grep -q 127.0.0.1:4100/v1 ~/.pi/agent/extensions/pxy.ts && ! grep -q __PXY_ ~/.pi/agent/extensions/pxy.ts"
# The machine has no gh login before dots secrets, so the private skills repo is not cloned and the apply still finishes.
check "the skills repo waits for dots secrets" as_user "test ! -e ~/.local/src/skills"
pw=$(as_user "mise exec -- bash -c 'command -v playwright-cli'" 2>&1)
check "mise's PATH finds the playwright-cli wrapper first (got '$pw')" test "$pw" = "$home/Codes/dotfiles/bin/playwright-cli"
pwv=$(as_user "mise exec -- playwright-cli --version" 2>&1)
check "playwright-cli --version prints a version (got '$pwv')" grep -qE '^[0-9]+\.[0-9]+\.[0-9]+' <<<"$pwv"
v1=$(as_user "find ~/.claude ~/.pi ~/.agents ~/.config/playwright ~/.config/playwright-cli -type l -lname '*/.dotfiles/*'" 2>&1)
check "nothing Claude Code or pi loads links into v1 (got '$v1')" test -z "$v1"
# A skill comes from the dotfiles, the skills repo, amx setup, playwright-cli, or workflow install, the one writer of real folders into both skill folders.
stray=$(as_user 'for e in ~/.claude/skills/*; do n=${e##*/}; t=$(readlink -f "$e/SKILL.md"); case $t in "$HOME"/Codes/dotfiles/* | "$HOME"/.local/src/skills/*) continue ;; esac; [[ $n == amx || $n == playwright-cli ]] && continue; [[ ! -L $e && -d ~/.agents/skills/$n && ! -L ~/.agents/skills/$n ]] && continue; echo "$n"; done')
check "every skill in \$HOME/.claude/skills comes from one of the five sources (got strays '$stray')" test -z "$stray"
dropped=$(as_user "find ~/.config -path ~/.config/composer/vendor -prune -o \( -iname '*herdr*' -o -iname '*kitty*' -o -iname '*vicinae*' \) -print")
check "nothing for herdr, kitty or vicinae under ~/.config (got '$dropped')" test -z "$dropped"

check "caddy accepts its Caddyfile" as_user "caddy validate --config ~/.config/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1"
check "the system trusts caddy's .test CA" podman exec "$name" bash -c "trust list | grep -q 'Caddy Local Authority'"
phpv=$(as_user "php -r 'echo PHP_MAJOR_VERSION.\".\".PHP_MINOR_VERSION;'" 2>&1)
check "php is Fedora's 8.5 (got '$phpv')" test "$phpv" = 8.5
remi=$(podman exec "$name" rpm -qa 'php8[234]-*' 'remi-release')
check "nothing from Remi is installed (got '$remi')" test -z "$remi"
check "php loads phpredis, Laravel's default Redis client" as_user "php -r 'exit(extension_loaded(\"redis\") ? 0 : 1);'"
check "php-fpm reads the .test pool" as_user "/usr/sbin/php-fpm -t --fpm-config ~/.config/php-fpm/dev.conf 2>/dev/null"
check "composer installed the laravel installer and Pint" as_user "~/.config/composer/vendor/bin/laravel --version && ~/.config/composer/vendor/bin/pint --version"
check "laravel new makes an app in ~/Codes whose tests pass" as_user "~/.config/composer/vendor/bin/laravel new ~/Codes/demo --no-interaction >/dev/null 2>&1 && cd ~/Codes/demo && php artisan test >/dev/null 2>&1"
check "*.test resolves through dnsmasq" podman exec "$name" grep -qx 'address=/test/127.0.0.1' /etc/dnsmasq.d/test-domains.conf
check "the dev quadlets generate units" as_user "/usr/lib/systemd/user-generators/podman-user-generator --dryrun >/dev/null 2>&1"
check "the dev sockets are enabled" as_user "test -f ~/.config/systemd/user/sockets.target.wants/mysql84-proxy.socket -a -f ~/.config/systemd/user/sockets.target.wants/caddy-dev-https.socket -a -f ~/.config/systemd/user/sockets.target.wants/php-fpm-proxy.socket"

check "kak opens with the carried config" as_user "kak -ui dummy -e 'eval -buffer *debug* %{ write /tmp/kak-debug }; quit!' && ! grep -Eiq 'error|could not load' /tmp/kak-debug"
check "hop-kak --version exits 0 through mise" as_user "mise exec -- hop-kak --version >/dev/null"
check "kak-ansi-filter strips an ANSI colour" as_user "printf '\\033[31mred\\033[0m\\n' | kak-ansi-filter | grep -qx red"
check "kak finds the helix grammars" as_user "fish -c 'test -d \$HELIX_RUNTIME/grammars'"
check "mail-sync.timer waits for ~/.mbsyncrc, which a keyless install does not write" \
  as_user "grep -qx 'ConditionPathExists=%h/.mbsyncrc' ~/.config/systemd/user/mail-sync.timer && test ! -e ~/.mbsyncrc"

check "tty1 logs saiful straight in" podman exec "$name" grep -q -- '--autologin saiful' /etc/systemd/system/getty@tty1.service.d/autologin.conf
shell=$(podman exec "$name" getent passwd saiful | cut -d: -f7)
check "fish is saiful's login shell (got '$shell')" test "$shell" = /usr/bin/fish
out=$(as_user "foot --check-config" 2>&1)
check "foot reads its config without a warning (got '$out')" test -z "$out"
check "tmux reads its config" as_user "tmux -L check start-server \\; kill-server"
# yazi reads its config only as a TUI, so it runs under a pty (-t) with a fixed size, since the pty has no window to measure. On a config error it prints "Failed to parse ..." and waits for a key, so the title it sets once it is up is the proof. timeout stops it either way.
out=$(podman exec -t -u saiful -w "$home" -e HOME="$home" -e LANG=C.UTF-8 -e LINES=24 -e COLUMNS=80 -e PATH="$home/.local/bin:/usr/bin:/bin" "$name" timeout --foreground -k 2 5 yazi 2>&1)
check "yazi starts with the shipped config (got '$(grep -ao 'Failed to parse config "[^"]*"' <<<"$out")')" grep -aq 'Yazi: ' <<<"$out"

calls=$(podman exec "$name" cat "$log")
total=$(grep -c . <<<"$calls")
prompting=$(grep -vc '^-n' <<<"$calls")
echo "sudo calls in the first run: $total, of which can prompt: $prompting"
check "sudo log starts with -v and every later call uses -n" \
  test "$(head -n1 <<<"$calls")" = -v -a "$prompting" = 1

before=$(snapshot)
echo "--- second run"
as_root ": > $curl_log"
check "second dots install exits 0" dots_install
installs=$(podman exec "$name" grep -c 'claude.ai/install.sh' "$curl_log")
check "second run runs the Claude installer 0 times (got $installs)" test "$installs" = 0
after=$(snapshot)
check "second run changes no file under $home or /etc" diff <(echo "$before") <(echo "$after")

echo "--- dots update with nothing new"
as_root ": > $log"
out=$(as_user "Codes/dotfiles/bin/dots update" 2>&1)
rc=$?
echo "${out##*$'\n'}"
check "dots update exits 0" test $rc = 0
check "dots update ends with dnf: N upgraded · pins: 0 changed" grep -qE '^dnf: [0-9]+ upgraded · pins: 0 changed$' <<<"${out##*$'\n'}"
calls=$(podman exec "$name" cat "$log")
# sudo -k only drops the timestamp, so it never prompts and ends the log.
check "dots update's sudo log starts with -v, ends with -k and every call between uses -n" \
  test "$(head -n1 <<<"$calls")" = -v -a "$(tail -n1 <<<"$calls")" = -k -a "$(grep -vc '^-n' <<<"$calls")" = 2

echo "--- dots update after a pin moved"
# The repo's working copy takes the older yazi release, as a pulled bump would bring a newer one.
as_user "cd ~/Codes/dotfiles && sed -i -e 's/^version = \"26.9.1\"/version = \"26.8.15\"/' \\
  -e 's/02807f08d6b589b65b7516a4e259d83f5995d7a23bb12b3a155141385b370b3a/f5a85771f06bb0e8c488136ae0aedaec8d341a7cee995549df391d7d852fe8d1/' \\
  -e 's/a02fe91d3304294048c681f010f1100856872a4e98ecf6927328e888d40a6ad2/cc67eb7991550c2f9407cda52d3f5af0937627aa6884e7de99a04fcf059807e0/' versions.toml"
out=$(as_user "Codes/dotfiles/bin/dots update" 2>&1)
check "dots update reinstalls only yazi" test "$(grep -c '^dots: pin ' <<<"$out")" = 1 -a "$(grep -c '^dots: pin yazi 26.8.15$' <<<"$out")" = 1
check "dots update ends with pins: 1 changed (got '${out##*$'\n'}')" grep -qE '^dnf: [0-9]+ upgraded · pins: 1 changed$' <<<"${out##*$'\n'}"
check "yazi is now 26.8.15" as_user "yazi --version | grep -q 26.8.15"

echo "--- dots install with a tampered pin"
as_user "cd ~/Codes/dotfiles && sed -i 's/f5a85771f06bb0e8c488136ae0aedaec8d341a7cee995549df391d7d852fe8d1/$(printf '0%.0s' {1..64})/; s/cc67eb7991550c2f9407cda52d3f5af0937627aa6884e7de99a04fcf059807e0/$(printf '0%.0s' {1..64})/' versions.toml"
out=$(dots_install 2>&1)
rc=$?
check "dots install refuses the tampered pin (exit $rc)" test $rc != 0
check "the refusal names the pin" grep -q 'pin yazi: sha256' <<<"$out"
check "yazi stays 26.8.15" as_user "yazi --version | grep -q 26.8.15"

exit $failed
}
