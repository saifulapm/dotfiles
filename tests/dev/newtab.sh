#!/usr/bin/env bash
# Ctrl+T in Chromium opens the theme's new-tab page: its paper, the date, a field that takes the keys typed first, and the six most visited sites.
{
source "$(dirname "$0")/lib.sh"

work=$DOTS_DEV_DIR/newtab
mkdir -p "$work/policy" "$work/site"
out=$XDG_STATE_HOME/dots/theme-out
rgb() { printf '%d %d %d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
token() { jq -r ".color.$1" "$out/shell.json"; }
near() { (($1 - $2 <= 6 && $2 - $1 <= 6)); }
# The median of a 17x17 square per channel at the centre of the page as Chromium draws it, which skips Blueprint's grid lines and Paper's grain specks.
page_centre() {
  local w h
  rm -f "$work/page.png"
  cdp shot newtab.html "$work/page.png" || return 1
  read -r w h < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=' ' "$work/page.png")
  ffmpeg -loglevel error -i "$work/page.png" -vf "crop=17:17:$((w / 2 - 8)):$((h / 2 - 8)),format=rgb24" -f image2pipe -vcodec ppm - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length), ch = [[], [], []];
    for (let i = 0; i < head[1] * head[2] * 3; i++) ch[i % 3].push(px[i]);
    console.log(ch.map((c) => c.sort((x, y) => x - y)[c.length >> 1]).join(" "));
  '
}
centre_is() { local r g b; read -r r g b < <(page_centre); read -r -a want <<<"$(rgb "$1")"; near "$r" "${want[0]}" && near "$g" "${want[1]}" && near "$b" "${want[2]}"; }

# Seven local pages to visit, so the list has one more site than it shows.
names=(Alpha Bravo Charlie Delta Echo Foxtrot Golf)
for n in "${names[@]}"; do echo "<title>$n</title><p>$n</p>" >"$work/site/${n,,}.html"; done
port=$((20000 + RANDOM % 10000))
python3 -m http.server --bind 127.0.0.1 --directory "$work/site" "$port" >/dev/null 2>&1 &
server=$!
site() { echo "http://127.0.0.1:$port/${1,,}.html"; }
dport=$((30000 + RANDOM % 10000))
cdp() { node "$repo/tests/dev/cdp.mjs" "$dport" "$@" 2>/dev/null; }
page() { cdp eval newtab.html "$1"; }

# Chromium reads the managed policy from /etc, so an empty policy dir is bound there, as on a machine the apply has cleaned; each profile is the check's own.
chromium() {
  niri msg action spawn -- bwrap --dev-bind / / --bind "$work/policy" /etc/chromium/policies/managed \
    chromium-browser --user-data-dir="$work/$1" --no-first-run --ozone-platform=wayland --remote-debugging-port="$dport" \
    --disable-features=NtpFooter "--load-extension=$out/chromium-theme,$out/chromium-newtab" "$(site Alpha)"
  until_ok 15000 cdp urls >/dev/null
  until_ok 15000 bash -c 'niri msg -j windows | jq -e "any(.[]; .app_id == \"chromium-browser\")" >/dev/null'
  # Ctrl+T before the window has the keyboard is lost, so the start page must have focus first.
  until_ok 15000 start_focused
}
start_focused() { cdp eval alpha.html 'document.readyState === "complete" && document.hasFocus()' | grep -qx true; }
chromium_gone() { ! pgrep -x chromium-browse | while read -r p; do grep -qzF "$work/" "/proc/$p/cmdline" 2>/dev/null && echo x; done | grep -q x; }
quit_chromium() {
  local id
  for id in $(niri msg -j windows | jq -r '.[] | select(.app_id == "chromium-browser") | .id'); do niri msg action close-window --id "$id"; done
  until_ok 15000 chromium_gone
}
cleanup() {
  kill "$server" 2>/dev/null
  pgrep -x chromium-browse | while read -r p; do grep -qzF "$work/" "/proc/$p/cmdline" 2>/dev/null && kill "$p"; done
}
# The page is ready once its swap is done and it has drawn its rows or its empty line.
ready() { page 'document.querySelector("main").hidden === false && document.querySelectorAll(".row, .empty").length > 0' | grep -qx true; }
newtabs() { cdp urls | grep -c 'newtab.html'; }
more_tabs() { test "$(newtabs)" -gt "$1"; }
# Ctrl+T, then the keys in $1 about 150 ms later, as a person types. A freshly started Chromium now and then never sees the Ctrl+T (no tab opens at all), so only then is it pressed again; keys lost once the page exists still fail the check.
new_tab() {
  local before try
  before=$(newtabs)
  for try in 1 2 3; do
    niri msg action focus-window --id "$(niri msg -j windows | jq -r 'first(.[] | select(.app_id == "chromium-browser") | .id)')"
    wtype -M ctrl t -m ctrl
    if [ -n "${1:-}" ]; then sleep 0.15; wtype "$1"; fi
    until_ok 3000 more_tabs "$before" && return 0
    echo "     Chromium saw no Ctrl+T, press $try"
  done
  return 1
}
close_tab() { wtype -M ctrl w -m ctrl; sleep 0.5; }
tab_at() { cdp urls | grep -qF "$1"; }
searched() { cdp urls | grep -qE '[?&]q=fedora'; }

# A goal in the store, which the margins show and the page must not.
store="$DOTS_DEV_DIR/data/dots/goals/dev.json"
mkdir -p "$(dirname "$store")"
node --input-type=module -e "const G = await import('$repo/shell/lib/goals.mjs'); console.log(JSON.stringify(G.addGoal(G.emptyStore(), 'Ship the new tab', Date.now() + 86400000, Date.now(), 'g0')))" >"$store"

# A fresh profile has no history, so its list reads one empty line and draws no row.
"$repo/bin/dots" theme paper
chromium fresh
new_tab
until_ok 10000 ready
check "a fresh profile's list reads $(page 'document.querySelector(".empty")?.textContent') on one line, with no row" \
  page '!document.querySelector(".row") && document.querySelector(".empty").textContent === "NOTHING VISITED YET" && document.querySelector(".empty").getClientRects().length === 1 && document.querySelector(".empty").offsetHeight < 40'
quit_chromium

# Seven sites visited 7, 6, 5 ... 1 times from the address bar, so the list reads Alpha to Foxtrot in that order.
chromium seeded
for i in "${!names[@]}"; do
  for ((v = 0; v < 7 - i; v++)); do cdp visit "$(site "${names[$i]}")?v=$v"; done
done
# Chromium refreshes its top sites on a timer and keeps them in its profile, so the seeding run waits until they list all seven before it quits.
seeded_seven() { cdp eval newtab.html 'new Promise((r) => chrome.topSites.get((s) => r(s.length >= 7)))' | grep -qx true; }
cdp open chrome://newtab/
until_ok 10000 ready
until_ok 60000 seeded_seven || echo "     the top sites never listed all seven"
echo "     top sites after seeding: $(cdp eval newtab.html 'new Promise((r) => chrome.topSites.get((s) => r(s.map((x) => x.title).join(", "))))')"
sleep 12
quit_chromium

for theme in paper blueprint artboard; do
  "$repo/bin/dots" theme "$theme"
  chromium seeded
  # The keys typed after Ctrl+T must reach the page's field, not the address bar.
  new_tab fedora
  until_ok 10000 ready || { echo "     not ready: $(cdp urls | tr '\n' ' ')"; grim -s 1 "${DOTS_CHECK_SHOTS:-/tmp}/newtab-$theme-notready.png"; }
  until_ok 3000 centre_is "$(token paper)"
  check "$theme: Ctrl+T draws $theme's paper $(token paper) at the page's centre ($(page_centre))" centre_is "$(token paper)"
  check "$theme: the keys typed after Ctrl+T are in the page's field ($(page 'document.getElementById("q").value'))" page 'document.getElementById("q").value === "fedora" && document.activeElement.id === "q" && document.hasFocus()'
  check "$theme: the list reads the six most visited sites, numbered ($(page '[...document.querySelectorAll(".row")].map((r) => r.querySelector(".n").textContent + " " + r.querySelector(".title").textContent).join(", ")'))" \
    page '[...document.querySelectorAll(".row")].map((r) => r.querySelector(".n").textContent + " " + r.querySelector(".title").textContent).join(", ") === "1 Alpha, 2 Bravo, 3 Charlie, 4 Delta, 5 Echo, 6 Foxtrot"'
  check "$theme: no text on the page names the goal" page '!/goal|ship the new tab/i.test(document.body.innerText)'
  wtype -k Return
  until_ok 10000 searched
  check "$theme: Enter searches the default engine for fedora ($(cdp urls | grep -m1 'q=fedora' | cut -c1-60))" until_ok 3000 searched
  quit_chromium
done

# The address and the digit keys, once, in the last theme.
chromium seeded
new_tab
until_ok 10000 ready
wtype github.com
wtype -k Return
until_ok 10000 tab_at https://github.com/
check "github.com then Enter opens https://github.com ($(cdp urls | tr '\n' ' '))" tab_at https://github.com/
new_tab
until_ok 10000 ready
wtype 2
until_ok 3000 tab_at "$(site Bravo)" || { echo "     2 did not open: field $(page 'JSON.stringify([document.getElementById("q").value, document.activeElement.className || document.activeElement.id, document.querySelectorAll(".row").length, document.querySelector("#sites").innerText.slice(0, 80)])')"; wtype 2; until_ok 3000 tab_at "$(site Bravo)"; }
check "with the field empty, 2 opens the second site, Bravo ($(cdp urls | tr '\n' ' '))" tab_at "$(site Bravo)"
quit_chromium

((fails > 0)) && grim -s 1 "${DOTS_CHECK_SHOTS:-/tmp}/newtab-fail.png" 2>/dev/null
exit $((fails > 0))
}
