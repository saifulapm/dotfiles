#!/usr/bin/env bash
# Plays a 60 s 4K60 sample per codec on the repo's mpv.conf and checks drops, hwdec, hardware decode PSNR and resume.
set -uo pipefail
{
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
samples=~/.cache/dots-mpv-samples
fails=0

check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}

# The far side: $1 is the machine id, $2 a folder holding mpv.conf and probe.lua.
if [ "${1:-}" = --play ]; then
  machine=$2 conf=$3
  # An ssh login has no compositor env, so it comes from the user manager niri-session filled, as ssh-desktop.fish does.
  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    WAYLAND_DISPLAY=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p')
    export WAYLAND_DISPLAY XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  fi
  [ -n "$WAYLAND_DISPLAY" ] || { echo "FAIL no live Wayland session to play on"; exit 1; }

  # A dark or locked output sends no frame callbacks, so mpv would see no drops whatever happened.
  now_ms() { echo $(($(date +%s%N) / 1000000)); }
  grim_ms() { local t0; t0=$(now_ms); grim -s 0.1 -t ppm - >/dev/null 2>&1; echo $(($(now_ms) - t0)); }
  grim_ms >/dev/null
  if (($(grim_ms) > 500 && $(grim_ms) > 500)); then
    echo "FAIL the output draws about once a second: is the session locked, or its output off?"
    exit 1
  fi

  # A nested niri check at the same time would steal frames, so playing waits for the lock that check takes.
  exec 9>"${XDG_RUNTIME_DIR:-/tmp}/dots-dev-check.lock"
  flock -w 900 9 || { echo "FAIL another nested check held the lock for 15 min"; exit 1; }

  scratch=$(mktemp -d)
  trap 'rm -rf "$scratch"' EXIT
  # $1 names the run; its JSON lands in $scratch/$1.json. Each run gets its own watch-later dir unless it passes one.
  play() {
    local name=$1
    shift
    mkdir -p "$scratch/$name.wl"
    # shellcheck disable=SC2086
    mpv --config-dir="$conf" ${DOTS_MPV_OPTS:-} --no-audio --watch-later-dir="$scratch/$name.wl" \
      --script="$conf/probe.lua" --script-opts="probe-out=$scratch/$name.json" "$@" >"$scratch/$name.log" 2>&1
  }
  get() { jq -r ".$2 // \"none\"" "$scratch/$1.json" 2>/dev/null || echo none; }
  expect_hwdec() { if [[ $machine == mac* ]]; then [ "$1" = hevc10.mp4 ] && echo vaapi-copy || echo no; else echo vaapi; fi; }

  for f in h264.mp4 hevc10.mp4 vp9.webm av1.mkv; do
    play "$f" --fullscreen --length=60 "$samples/$f"
    fd=$(get "$f" frame_drops) dd=$(get "$f" decoder_drops) hw=$(get "$f" hwdec)
    check "$f drops no frame in 60 s (vo $fd, decoder $dd, delayed $(get "$f" delayed))" [ "$fd/$dd" = 0/0 ]
    check "$f decodes with hwdec $hw (want $(expect_hwdec "$f"))" [ "$hw" = "$(expect_hwdec "$f")" ]
  done

  for f in h264.mp4 hevc10.mp4 vp9.webm av1.mkv; do
    [ "$(expect_hwdec "$f")" = no ] && continue
    play "$f.hw" --start=1.5 --pause --script-opts-append=probe-mode=shot --script-opts-append="probe-shot=$scratch/hw.png" "$samples/$f"
    play "$f.sw" --start=1.5 --pause --hwdec=no --script-opts-append=probe-mode=shot --script-opts-append="probe-shot=$scratch/sw.png" "$samples/$f"
    avg=$(ffmpeg -hide_banner -i "$scratch/hw.png" -i "$scratch/sw.png" -lavfi psnr -f null - 2>&1 | sed -n 's/.*average:\([0-9.inf]*\).*/\1/p')
    # A shot that fell back to software would match software exactly, so the hardware shot must name its decoder.
    hw=$(get "$f.hw" hwdec)
    check "$f frame at 1.5 s through hwdec $hw matches software at ${avg:-no} dB (want $(expect_hwdec "$f"), >= 40)" \
      awk -v a="${avg:-0}" -v hw="$hw" -v want="$(expect_hwdec "$f")" 'BEGIN { exit !(hw == want && (a == "inf" || a + 0 >= 40)) }'
    rm -f "$scratch/hw.png" "$scratch/sw.png"
  done

  # Both resume runs share one watch-later dir: the first saves its place on quit, the second starts there.
  mkdir -p "$scratch/resume.wl"
  play quit --watch-later-dir="$scratch/resume.wl" --script-opts-append=probe-mode=quit-at "$samples/h264.mp4"
  play resume --watch-later-dir="$scratch/resume.wl" --pause --script-opts-append=probe-mode=read-pos "$samples/h264.mp4"
  at=$(get resume start)
  check "h264.mp4 quit at $(get quit pos) s resumes at $at s (want 9 to 11)" \
    awk -v a="$at" 'BEGIN { exit !(a != "none" && a >= 9 && a <= 11) }'
  exit $((fails > 0))
fi

# Usage: run.sh [--dry-run] [mini|nuc]. DOTS_MPV_OPTS adds mpv options to every run of the conf under test.
dry=
[ "${1:-}" = --dry-run ] && { dry="echo"; shift; }
host=${1:-}
case $host in
  '') machine=$(sed -n 's/^ *machine *= *"\(.*\)"/\1/p' ~/.config/chezmoi/chezmoi.toml) ;;
  mini) machine=mac-mini-m2 ;;
  nuc) machine=nuc ;;
  *) echo "FAIL unknown host $host: use mini or nuc" >&2; exit 1 ;;
esac

# Rendered as tests/home/mpv.test.mjs renders it, minus the theme include, which does not change playback.
conf=$(mktemp -d)
trap 'rm -rf "$conf"' EXIT
printf '[data]\nmachine = "%s"\n' "$machine" >"$conf/chezmoi.toml"
HOME=$conf chezmoi --config "$conf/chezmoi.toml" --source "$here/../.." execute-template \
  <"$here/../../home/dot_config/mpv/mpv.conf.tmpl" | grep -v '^include=' >"$conf/mpv.conf" ||
  { echo "FAIL could not render mpv.conf for $machine"; exit 1; }
rm "$conf/chezmoi.toml"
cp "$here/probe.lua" "$here/run.sh" "$conf/"

$dry "$here/samples.sh" || { echo "FAIL could not make the samples"; exit 1; }
if [ -z "$host" ]; then
  $dry "$conf/run.sh" --play "$machine" "$conf"
  exit
fi

# The host's own ~/.config/mpv stays as it is: everything lands under ~/.cache.
work=.cache/dots-mpv-test
$dry ssh -o BatchMode=yes "$host" "mkdir -p ~/$work ~/.cache/dots-mpv-samples" || { echo "FAIL cannot reach $host"; exit 1; }
$dry rsync -q --size-only "$samples"/{h264.mp4,hevc10.mp4,vp9.webm,av1.mkv} "$host:.cache/dots-mpv-samples/" ||
  { echo "FAIL could not copy the samples to $host"; exit 1; }
$dry rsync -q "$conf"/{mpv.conf,probe.lua,run.sh} "$host:$work/" || { echo "FAIL could not copy the conf to $host"; exit 1; }
# ssh lands in the host's login shell, which may be fish, so the far side runs as `bash file`.
$dry ssh -o BatchMode=yes "$host" "DOTS_MPV_OPTS='${DOTS_MPV_OPTS:-}' bash ~/$work/run.sh --play $machine ~/$work"
exit
}
