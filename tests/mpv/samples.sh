#!/usr/bin/env bash
# Makes the 60 s 4K60 samples tests/mpv/run.sh plays, one per codec, skipping a file that exists.
set -uo pipefail
{
dir=~/.cache/dots-mpv-samples
mkdir -p "$dir"
src=(-f lavfi -i "testsrc2=size=3840x2160:rate=60" -t 60)
declare -A enc=(
  [h264.mp4]="-c:v libx264 -preset veryfast -bf 3 -b:v 40M -maxrate 50M -bufsize 80M -pix_fmt yuv420p"
  [hevc10.mp4]="-c:v libx265 -preset ultrafast -pix_fmt yuv420p10le -profile:v main10 -b:v 25M -tag:v hvc1"
  [vp9.webm]="-c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -b:v 25M -pix_fmt yuv420p"
  [av1.mkv]="-c:v libsvtav1 -preset 12 -b:v 20M -pix_fmt yuv420p"
)
for f in h264.mp4 hevc10.mp4 vp9.webm av1.mkv; do
  [ -e "$dir/$f" ] && continue
  echo "encoding $f" >&2
  # The .part name hides the container from ffmpeg, so it is named here.
  fmt=${f##*.}
  [ "$fmt" = mkv ] && fmt=matroska
  # A 4K encode takes gigabytes, so it runs in its own capped scope and never in the session's.
  # shellcheck disable=SC2086
  if ! systemd-run --user --quiet --scope -p MemoryMax=3G -- timeout 3600 \
    ffmpeg -hide_banner -loglevel error -y "${src[@]}" ${enc[$f]} -f "$fmt" "$dir/$f.part"; then
    echo "could not encode $f" >&2
    exit 1
  fi
  mv "$dir/$f.part" "$dir/$f"
done
exit
}
