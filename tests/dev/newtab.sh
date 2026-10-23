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

# Every font Chromium drew the element's text in is the family, at any weight: Artboard's 600 draws as Maple Mono SemiBold.
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

# The day and date each voice writes for today, as the boards draw them.
date_line() {
  case $1 in
    paper) LC_ALL=C date '+%A %-d %B %Y' | sed 's/^[A-Za-z]*/\U&/' ;;
    blueprint) LC_ALL=C date '+%A %Y-%m-%d' | sed 's/^[A-Za-z]*/\U&/' ;;
    artboard) LC_ALL=C date '+%A %-d %B %Y' ;;
  esac
}

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

# Chromium reads the managed policy from /etc, so an empty policy dir is bound there, as on a machine the apply has cleaned; each profile is the check's own.
chromium() {
  niri msg action spawn -- bwrap --dev-bind / / --bind "$work/policy" /etc/chromium/policies/managed \
    chromium-browser --user-data-dir="$work/$1" --no-first-run --ozone-platform=wayland --remote-debugging-port="$dport" \
    --disable-features=NtpFooter "--load-extension=$out/chromium-theme,$out/chromium-newtab" 'data:text/html,<title>start</title><input id="k" autofocus>'
  until_ok 15000 cdp urls >/dev/null
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
"$repo/bin/dots" theme paper
chromium fresh
new_tab
until_ok 10000 ready
check "a fresh profile's list reads $(page 'document.querySelector(".empty")?.textContent') on one line, with no row" \
  is '!document.querySelector(".row") && document.querySelector(".empty").textContent === "NOTHING VISITED YET" && document.querySelector(".empty").getClientRects().length === 1 && document.querySelector(".empty").offsetHeight < 40'
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

for theme in paper blueprint artboard; do
  "$repo/bin/dots" theme "$theme"
  chromium seeded
  # The keys typed after Ctrl+T must reach the page's field, not the address bar.
  new_tab fedora
  until_ok 10000 ready || { echo "     not ready: $(cdp urls | tr '\n' ' ')"; grim -s 1 "${DOTS_CHECK_SHOTS:-/tmp}/newtab-$theme-notready.png"; }
  until_ok 3000 centre_is "$(token paper)"
  check "$theme: Ctrl+T draws $theme's paper $(token paper) at the page's centre ($(page_centre))" centre_is "$(token paper)"
  check "$theme: the keys typed after Ctrl+T are in the page's field ($(page 'document.getElementById("q").value'))" is 'document.getElementById("q").value === "fedora" && document.activeElement.id === "q" && document.hasFocus()'
  check "$theme: the list reads the six most visited sites, numbered ($(page '[...document.querySelectorAll(".row")].map((r) => r.querySelector(".n").textContent + " " + r.querySelector(".title").textContent).join(", ")'))" \
    is '[...document.querySelectorAll(".row")].map((r) => r.querySelector(".n").textContent + " " + r.querySelector(".title").textContent).join(", ") === "1 Alpha, 2 Bravo, 3 Charlie, 4 Delta, 5 Echo, 6 Foxtrot"'
  check "$theme: the date reads $(page '[document.getElementById("day").textContent, document.getElementById("date").textContent].join(" ")') in $theme's voice" \
    is "[document.getElementById('day').textContent, document.getElementById('date').textContent].join(' ') === '$(date_line "$theme")'"
  check "$theme: Chromium draws the date in $theme's $(jq -r .type.display "$out/shell.json") ($(cdp fonts newtab.html '#date'))" drawn_in '#date' "$(jq -r .type.display "$out/shell.json")"
  # A focused row turns its colours over, and its tile's letter must still read: at least 3:1 against what is behind it.
  check "$theme: the focused row's tile letter reads ($(page "$tile_contrast" | cut -c1-5):1)" is "$tile_contrast >= 3"
  check "$theme: no text on the page names the goal" is '!/goal|ship the new tab/i.test(document.body.innerText)'
  wtype -k Return
  until_ok 10000 searched
  check "$theme: Enter searches the default engine for fedora ($(cdp urls | grep -m1 'q=fedora' | cut -c1-60))" until_ok 3000 searched
  quit_chromium
done

# A switch takes effect at Chromium's next start: Artboard's Chromium quits, dots theme paper, and the next start draws Paper.
"$repo/bin/dots" theme paper
chromium seeded
new_tab
until_ok 10000 ready
until_ok 3000 centre_is "$(token paper)"
check "after dots theme paper and a restart, Ctrl+T draws Paper's paper ($(page_centre))" centre_is "$(token paper)"
check "and Paper's date, $(date_line paper), in $(cdp fonts newtab.html '#date')" \
  is "document.documentElement.dataset.theme === 'paper' && [document.getElementById('day').textContent, document.getElementById('date').textContent].join(' ') === '$(date_line paper)'"
check "and its date face is Instrument Serif as drawn ($(cdp fonts newtab.html '#date'))" drawn_in '#date' "Instrument Serif"
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
