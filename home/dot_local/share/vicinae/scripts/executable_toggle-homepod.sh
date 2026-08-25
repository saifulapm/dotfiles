#!/usr/bin/env bash
# @vicinae.schemaVersion 1
# @vicinae.title Audio: Toggle HomePod / Speakers
# @vicinae.mode silent
# @vicinae.icon 🔈
# @vicinae.packageName Toggles
# @vicinae.keywords ["homepod", "airplay", "output", "sink", "speakers"]
# Flip the default audio output between the HomePod (the static RAOP sink
# in pipewire.conf.d/99-homepod-raop.conf) and the built-in speakers. The
# audio panel can do this too — this is the no-panel path.
set -uo pipefail
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$PATH"

dump="$(pw-dump 2>/dev/null)" || { notify-send -a qshell "🔈 Audio" "pipewire not answering"; exit 1; }
homepod="$(jq -r '.[] | select((.info.props["media.class"]//"") == "Audio/Sink")
    | select((.info.props["node.description"]//"") | test("HomePod")) | .id' <<<"$dump" | head -1)"
# "Speakers" first: on Asahi the built-in speakers are the DSP chain's
# virtual sink (audio_effect.*-convolver, "MacBook Pro J493 Speakers"),
# and the plain Headphones sink is refused as default with no jack in.
builtin="$(jq -r '.[] | select((.info.props["media.class"]//"") == "Audio/Sink")
    | select((.info.props["node.description"]//"") | test("Speakers")) | .id' <<<"$dump" | head -1)"
[[ -n $builtin ]] || builtin="$(jq -r '.[] | select((.info.props["media.class"]//"") == "Audio/Sink")
    | select((.info.props["node.description"]//"") | test("HomePod") | not) | .id' <<<"$dump" | head -1)"
[[ -n $homepod ]] || { notify-send -a qshell "🔈 Audio" "HomePod sink not present — is it awake?"; exit 0; }
[[ -n $builtin ]] || { notify-send -a qshell "🔈 Audio" "No built-in sink found"; exit 1; }

current="$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk 'NR==1 {gsub(",", "", $2); print $2}')"
if [[ $current == "$homepod" ]]; then
    wpctl set-default "$builtin" && notify-send -a qshell "🔈 Audio" "Output: built-in speakers"
else
    wpctl set-default "$homepod" && notify-send -a qshell "🔈 Audio" "Output: HomePod (Office)"
fi
