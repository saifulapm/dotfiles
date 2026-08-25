#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Monitor: Switch Input (DDC)
# @vicinae.mode silent
# @vicinae.icon 🖵
# @vicinae.packageName System
# @vicinae.keywords ["ddc", "benq", "hdmi", "displayport", "input", "source"]
# Switch an external monitor's input source over DDC/CI (VCP feature 60) —
# the BenQ on the mini shares its inputs with other machines. Options come
# from the monitor's own capabilities report (cached: the report costs ~2s);
# the pick goes through vicinae dmenu via menu-select. On a machine with no
# DDC display (the MacBook panel) this just says so.
set -uo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"

command -v ddcutil >/dev/null 2>&1 || { notify-send -a qshell "🖵 Input" "ddcutil is not installed"; exit 0; }

cache="${XDG_RUNTIME_DIR:-/tmp}/qshell-ddc-input-caps"
if [[ ! -s $cache ]]; then
    # "Feature: 60 (Input Source)" then indented "Values:" lines like
    # "0f: DisplayPort-1". Keep only "code<TAB>name" rows.
    caps="$(ddcutil capabilities 2>/dev/null)" || caps=""
    awk '/Feature: 60/{grab=1; next} grab && /^[[:space:]]+[0-9a-f]+:/ {
            code=$1; sub(":", "", code); $1=""; sub(/^ /, "");
            printf "%s\t%s\n", code, $0; next
        } grab && /Feature: [0-9a-fA-F]+/{grab=0}' <<<"$caps" >"$cache" || true
fi
if [[ ! -s $cache ]]; then
    rm -f "$cache"
    notify-send -a qshell "🖵 Input" "No DDC-capable display found"
    exit 0
fi

current="$(ddcutil getvcp 60 --brief 2>/dev/null | awk '{print $4}' | sed 's/^x//')"
options=()
while IFS=$'\t' read -r code name; do
    marker=""
    [[ ${code,,} == "${current,,}" ]] && marker=" (current)"
    options+=("$name$marker")
done <"$cache"

pick="$(printf '%s\n' "${options[@]}" | menu-select "Monitor input")" || exit 0
pick="${pick% (current)}"
code="$(awk -F'\t' -v n="$pick" '$2 == n {print $1; exit}' "$cache")"
[[ -n $code ]] || exit 1
if ddcutil setvcp 60 "0x$code" 2>/dev/null; then
    notify-send -a qshell "🖵 Input" "Switched to $pick"
else
    notify-send -a qshell "🖵 Input" "DDC write failed — is the monitor on this input?"
fi
