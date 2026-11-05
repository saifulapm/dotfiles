#!/usr/bin/env bash
# Ctrl+T in Chromium opens the new-tab page: one card on the colourscheme's paper, the date, a field that takes the keys typed first, and the six most visited sites.
{
# The nested session puts a stand-in chromium-browser first on its PATH, so the real one is found before lib.sh joins it.
real_chromium=$(command -v chromium-browser) || { echo "FAIL no chromium-browser on PATH"; exit 1; }
source "$(dirname "$0")/lib.sh"

work=$DOTS_DEV_DIR/newtab
mkdir -p "$work/policy" "$work/site"
out=$XDG_STATE_HOME/dots/theme-out
rgb() { printf '%d %d %d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
token() { jq -r ".color.$1" "$out/shell.json"; }
near() { (($1 - $2 <= 6 && $2 - $1 <= 6)); }
# The median of a 17x17 square per channel at the page's left edge ("paper") or just inside the card's left edge ("card") as Chromium draws it, which skips the paper's dots.
page_median() {
  local x y
  rm -f "$work/page.png"
  cdp shot newtab.html "$work/page.png" || return 1
  IFS=, read -r x y < <(cdp eval newtab.html "(() => { const r = document.querySelector(\"main\").getBoundingClientRect(); return Math.round(r.left) + 8 + \",\" + Math.round(r.top + r.height / 2 - 8); })()" | tr -d '"')
  [ "$1" = paper ] && x=16
  ffmpeg -loglevel error -i "$work/page.png" -vf "crop=17:17:$x:$y,format=rgb24" -f image2pipe -vcodec ppm - | node -e '
    const b = require("fs").readFileSync(0);
    const head = b.toString("latin1").match(/^P6\s+(\d+)\s+(\d+)\s+(\d+)\s/);
    const px = b.subarray(head[0].length), ch = [[], [], []];
    for (let i = 0; i < head[1] * head[2] * 3; i++) ch[i % 3].push(px[i]);
    console.log(ch.map((c) => c.sort((x, y) => x - y)[c.length >> 1]).join(" "));
  '
}
# Whether the median at $1 is the colour $2.
colour_is() { local r g b; read -r r g b < <(page_median "$1"); read -r -a want <<<"$(rgb "$2")"; near "$r" "${want[0]}" && near "$g" "${want[1]}" && near "$b" "${want[2]}"; }

# Every font Chromium drew the element's text in is the family, at any weight: a 600 draws as Maple Mono SemiBold.
drawn_in() { local f; f=$(cdp fonts newtab.html "$1") && [ -n "$f" ] && ! tr ',' '\n' <<<"$f" | grep -qvE "^$2( |$)"; }

# The contrast of row 1's tile letter against its fill, or the row's when the tile has none, with row 1 focused.
tile_contrast='(() => {
  const r = document.querySelector(".row"); r.focus();
  const rgb = (c) => c.match(/[\d.]+/g).map(Number);
  const lum = (c) => { const [R, G, B] = rgb(c).slice(0, 3).map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * R + 0.7152 * G + 0.0722 * B; };
  const t = getComputedStyle(r.querySelector(".tile"));
  const behind = (rgb(t.backgroundColor)[3] ?? 1) === 0 ? getComputedStyle(r).backgroundColor : t.backgroundColor;
  const [a, b] = [lum(t.color), lum(behind)].sort((x, y) => y - x);
  const ratio = (a + 0.05) / (b + 0.05);
  document.getElementById("q").focus();
  return ratio;
})()'

# The day and date for today, as the page writes them.
date_line() { LC_ALL=C date '+%A %-d %B %Y'; }

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
# A check on the page passes only when the expression is true; eval itself succeeds whatever it returns.
is() { page "$1" | grep -qx true; }

# Chromium reads the managed policy from /etc, so an empty policy dir is bound there, as on a machine the apply has cleaned; each profile is the check's own. Any address after the profile is the tab it starts on.
launch() {
  local profile=$1
  shift
  niri msg action spawn -- bwrap --dev-bind / / --bind "$work/policy" /etc/chromium/policies/managed \
    "$real_chromium" --user-data-dir="$work/$profile" --no-first-run --ozone-platform=wayland --remote-debugging-port="$dport" \
    --disable-features=NtpFooter "--load-extension=$out/chromium-theme,$out/chromium-newtab" "$@"
  until_ok 15000 cdp urls >/dev/null
}
chromium() {
  launch "$1" 'data:text/html,<title>start</title><input id="k" autofocus>'
  until_ok 15000 bash -c 'niri msg -j windows | jq -e "any(.[]; .app_id == \"chromium-browser\")" >/dev/null'
  # For some seconds after it starts, Chromium drops the keys it is sent, so the start page's field must take a typed key before any check types.
  until_ok 20000 keys_reach
  cdp eval data: 'document.getElementById("k").value = ""' >/dev/null
}
keys_reach() {
  wtype k
  until_ok 1000 bash -c "node '$repo/tests/dev/cdp.mjs' $dport eval data: 'document.getElementById(\"k\").value.includes(\"k\")' 2>/dev/null | grep -qx true"
}
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
  grim -s 1 "${DOTS_CHECK_SHOTS:-/tmp}/newtab-no-ctrl-t.png"
  return 1
}
close_tab() { wtype -M ctrl w -m ctrl; sleep 0.5; }
tab_at() { cdp urls | grep -qF "$1"; }
visible() { cdp eval "$1" 'document.visibilityState' | grep -qx '"visible"'; }
searched() { cdp urls | grep -qE '[?&]q=fedora'; }

# A goal in the store, which the margins show and the page must not.
store="$DOTS_DEV_DIR/data/dots/goals/dev.json"
mkdir -p "$(dirname "$store")"
node --input-type=module -e "const G = await import('$repo/shell/lib/goals.mjs'); console.log(JSON.stringify(G.addGoal(G.emptyStore(), 'Ship the new tab', Date.now() + 86400000, Date.now(), 'g0')))" >"$store"

# A fresh profile has no history, so its list reads one empty line and draws no row.
chromium fresh
new_tab
until_ok 10000 ready
check "a fresh profile's list reads $(page 'document.querySelector(".empty")?.textContent') on one line, with no row" \
  is '!document.querySelector(".row") && document.querySelector(".empty").textContent === "Nothing visited yet" && document.querySelector(".empty").getClientRects().length === 1 && document.querySelector(".empty").offsetHeight < 40'
quit_chromium

# Seven sites visited 7, 6, 5 ... 1 times from the address bar, so the list reads Alpha to Foxtrot in that order.
chromium seeded
for i in "${!names[@]}"; do
  for ((v = 0; v < 7 - i; v++)); do cdp visit "$(site "${names[$i]}")?v=$v"; done
done
# Chromium refreshes its top sites on a timer and keeps them in its profile, so the seeding run waits until they list all seven before it quits.
forged_listed() { cdp eval newtab.html 'new Promise((r) => chrome.topSites.get((s) => r(s.some((x) => x.url.includes("forged")) && s.some((x) => x.url.includes("untitled")))))' | grep -qx true; }
seeded_seven() { cdp eval newtab.html 'new Promise((r) => chrome.topSites.get((s) => r(s.length >= 7)))' | grep -qx true; }
cdp open chrome://newtab/
until_ok 10000 ready
until_ok 60000 seeded_seven || echo "     the top sites never listed all seven"
echo "     top sites after seeding: $(cdp eval newtab.html 'new Promise((r) => chrome.topSites.get((s) => r(s.map((x) => x.title).join(", "))))')"
sleep 12
quit_chromium

chromium seeded
# The keys typed after Ctrl+T must reach the page's field, not the address bar.
new_tab fedora
until_ok 10000 ready || { echo "     not ready: $(cdp urls | tr '\n' ' ')"; grim -s 1 "${DOTS_CHECK_SHOTS:-/tmp}/newtab-notready.png"; }
until_ok 3000 colour_is paper "$(token paper)"
check "Ctrl+T draws the paper $(token paper) at the page's edge ($(page_median paper))" colour_is paper "$(token paper)"
check "and the card's surface $(token surface) just inside the card ($(page_median card))" colour_is card "$(token surface)"
check "the card is rounded 14 px with no shadow, and the rows and key chips are rounded" \
  is 'getComputedStyle(document.querySelector("main")).borderRadius === "14px" && getComputedStyle(document.querySelector("main")).boxShadow === "none" && getComputedStyle(document.querySelector(".row")).borderRadius === "10px" && getComputedStyle(document.querySelector(".keys span")).borderRadius === "6px"'
check "the page's stylesheets name no box-shadow" \
  is '![...document.styleSheets].some((s) => [...s.cssRules].some((r) => /box-shadow/.test(r.cssText)))'
check "the keys typed after Ctrl+T are in the page's field ($(page 'document.getElementById("q").value'))" is 'document.getElementById("q").value === "fedora" && document.activeElement.id === "q" && document.hasFocus()'
check "the list reads the six most visited sites, numbered ($(page '[...document.querySelectorAll(".row")].map((r) => r.querySelector(".n").textContent + " " + r.querySelector(".title").textContent).join(", ")'))" \
  is '[...document.querySelectorAll(".row")].map((r) => r.querySelector(".n").textContent + " " + r.querySelector(".title").textContent).join(", ") === "1 Alpha, 2 Bravo, 3 Charlie, 4 Delta, 5 Echo, 6 Foxtrot"'
check "the date reads $(page '[document.getElementById("day").textContent, document.getElementById("date").textContent].join(" ")')" \
  is "[document.getElementById('day').textContent, document.getElementById('date').textContent].join(' ') === '$(date_line)'"
check "Chromium draws the date in $(jq -r .type.display "$out/shell.json") ($(cdp fonts newtab.html '#date'))" drawn_in '#date' "$(jq -r .type.display "$out/shell.json")"
# A focused row turns its colours over, and its tile's letter must still read: at least 3:1 against what is behind it.
check "the focused row's tile letter reads ($(page "$tile_contrast" | cut -c1-5):1)" is "$tile_contrast >= 3"
check "no text on the page names the goal" is '!/goal|ship the new tab/i.test(document.body.innerText)'
check "the keys read as lower-case chips ($(page 'document.querySelector(".keys").innerText'))" is '/↵/.test(document.querySelector(".keys").innerText) && !/[[\]]/.test(document.body.innerText)'
wtype -k Return
until_ok 10000 searched
check "Enter searches the default engine for fedora ($(cdp urls | grep -m1 'q=fedora' | cut -c1-60))" until_ok 3000 searched
quit_chromium

# A switch takes effect at Chromium's next start: the switch to a dark scheme, and the next start draws its paper and surface.
"$repo/bin/dots" colorscheme catppuccin-mocha >/dev/null
until_ok 8000 bash -c 'timeout 0.5 qs ipc call shell status | jq -e ".theme == \"catppuccin-mocha\" and .transition == \"\"" >/dev/null'
chromium seeded
new_tab
until_ok 10000 ready
until_ok 3000 colour_is paper "$(token paper)"
check "after a switch to catppuccin-mocha and a restart, Ctrl+T draws its paper $(token paper) ($(page_median paper))" colour_is paper "$(token paper)"
check "and its surface $(token surface) inside the card ($(page_median card))" colour_is card "$(token surface)"
check "and the page names the scheme ($(page 'document.documentElement.dataset.theme'))" is "document.documentElement.dataset.theme === 'catppuccin-mocha'"
quit_chromium
"$repo/bin/dots" colorscheme artboard >/dev/null
until_ok 8000 bash -c 'timeout 0.5 qs ipc call shell status | jq -e ".theme == \"artboard\" and .transition == \"\"" >/dev/null'

# Started with no address, as a person opens it, Chromium makes its first tab its own new-tab page even with the extension installed; the extension's worker sends that tab to the theme's page.
launch seeded
start_themed() { [ "$(cdp urls | wc -l)" = 1 ] && cdp eval newtab.html location.href | grep -q '^"chrome-extension://aakconifmcmaooplokgfeaepglecbmaf/newtab.html'; }
until_ok 5000 start_themed
check "started with no address, Chromium's one tab is the theme's page ($(cdp urls | tr '\n' ' '))" start_themed
quit_chromium

# A title is whatever a page sets: controls, a bidi override and 300 characters must draw on one elided line, and a page with no title or icon still gets a letter tile.
forged=$'x\ny\x1bz\x07q\u0085w\u202ev\u200eu'
cat >"$work/site/forged.html" <<HTML
<meta charset="utf-8"><script>document.title = $(jq -n --arg t "$forged" '$t + ("A" * 300)')</script>
HTML
echo "<p>untitled</p>" >"$work/site/untitled.html"
chromium forged
for v in 1 2 3; do cdp visit "http://127.0.0.1:$port/forged.html?v=$v"; done
for v in 1 2; do cdp visit "http://localhost:$port/untitled.html?v=$v"; done
cdp open chrome://newtab/
until_ok 10000 ready
until_ok 60000 forged_listed || echo "     the top sites never listed the forged pages"
quit_chromium
chromium forged
new_tab
until_ok 10000 ready
row() { page "(() => { const r = [...document.querySelectorAll('.row')].find((r) => r.href.includes('$1')); return r && $2; })()"; }
row_is() { row "$1" "$2" | grep -qx true; }
# Chromium turns the newline, ESC and BEL into spaces itself; U+0085, U+202E and U+200E reach the page as they are.
check "the forged title reaches Chromium's top sites with its U+0085, U+202E and U+200E" \
  is 'new Promise((r) => chrome.topSites.get((s) => r(s.some((x) => /\u0085.*\u202e.*\u200e/s.test(x.title)))))'
echo "     forged row: $(row forged.html 'JSON.stringify(r.querySelector(".title").textContent.slice(0, 40))')"
check "the forged title draws on one line ($(row forged.html 'r.querySelector(".title").getClientRects().length + " box, " + r.offsetHeight + " px"'))" \
  row_is forged.html 'r.querySelector(".title").getClientRects().length === 1 && r.offsetHeight < 60'
check "the forged title is elided, with no control or bidi character" \
  row_is forged.html 'r.querySelector(".title").scrollWidth > r.querySelector(".title").clientWidth && getComputedStyle(r.querySelector(".title")).textOverflow === "ellipsis" && !/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/.test(r.querySelector(".title").textContent + r.querySelector(".address").textContent)'
check "the forged row still draws its letter tile ($(row forged.html 'r.querySelector(".tile").textContent'))" row_is forged.html 'r.querySelector(".tile").textContent === "x"'
check "a page with no title or icon shows its address and the host's letter ($(row untitled.html 'r.querySelector(".tile").textContent + " " + r.querySelector(".title").textContent'))" \
  row_is untitled.html 'r.querySelector(".tile").textContent === "l" && r.querySelector(".title").textContent.startsWith("localhost:")'
# At 390 px, a phone's width, a long address gives way: every title stays at least as wide as its address.
widths='[...document.querySelectorAll(".row")].map((r) => r.querySelector(".title").clientWidth + "/" + r.querySelector(".address").clientWidth).join(" ")'
check "at 390 px no title is narrower than its address (title/address: $(cdp narrow newtab.html 390 "$widths"))" \
  bash -c "node '$repo/tests/dev/cdp.mjs' $dport narrow newtab.html 390 '[...document.querySelectorAll(\".row\")].every((r) => r.querySelector(\".title\").clientWidth >= r.querySelector(\".address\").clientWidth)' | grep -qx true"
quit_chromium

# The address and the digit keys, once.
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
until_ok 5000 tab_at "$(site Bravo)"
check "with the field empty, 2 opens the second site, Bravo ($(cdp urls | tr '\n' ' '))" tab_at "$(site Bravo)"
quit_chromium

# Ctrl+T then Ctrl+W goes back to the tab Ctrl+T was pressed on, as on Chromium's own new tab, however many tabs are open.
chromium seeded
cdp open "$(site Charlie)" >/dev/null
cdp open "$(site Delta)" >/dev/null
until_ok 5000 tab_at "$(site Delta)"
cdp activate data: && until_ok 3000 visible data:
new_tab
until_ok 10000 ready
wtype -M ctrl w -m ctrl
until_ok 3000 bash -c "! node '$repo/tests/dev/cdp.mjs' $dport urls | grep -q newtab.html"
check "Ctrl+T then Ctrl+W on the first of three tabs returns to it ($(for u in data: charlie delta; do echo -n "$u $(cdp eval "$u" document.visibilityState) "; done))" until_ok 3000 visible data:
quit_chromium

((fails > 0)) && grim -s 1 "${DOTS_CHECK_SHOTS:-/tmp}/newtab-fail.png" 2>/dev/null
exit $((fails > 0))
}
