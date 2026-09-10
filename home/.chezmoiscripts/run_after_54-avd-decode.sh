#!/usr/bin/env bash
# Apple Video Decoder (AVD) — hardware H.264/HEVC/VP9 decode on the two Macs.
#
# The kernel already HAS the driver: CONFIG_VIDEO_APPLE_AVD=m, apple_avd
# autoloads and autoprobes. What Fedora ships no package for is the firmware,
# so every boot ended in:
#
#   avd 287080000.avd: Direct firmware load for apple/avd-fw-v3-t1.bin failed with error -2
#   avd 287080000.avd: probe with driver avd failed with error -2
#
# ...no /dev/video0, and every frame decoded on the CPU. Two pieces fix it and
# neither exists as a Fedora package (`dnf provides '*avd-fw*'` is empty,
# checked 2026-09-10):
#
#   1. avd-fw — Asahi's own clean MIT firmware (NOT extracted from macOS).
#      A Cortex-M3 blob that installs interrupt handlers and applies each
#      variant's tunables; the kernel and userspace do all the parsing.
#      Janne Grunau (Asahi upstream) maintains a Fedora spec for it, and there
#      is a succeeded fedora-44-aarch64 build in copr:jannau/test-builds —
#      deliberately NOT used, because that COPR's own description reads
#      "test builds do not use". Six blobs, ~390 KB total, kernel-independent
#      (Cortex-M3 code), so a kernel upgrade never invalidates them.
#
#   2. libva-v4l2_request (sofus13's fork) — AVD is a STATELESS decoder, which
#      almost nothing on the desktop speaks; ffmpeg's v4l2m2m decoders are
#      stateful and never negotiate with it. This is the VA-API bridge.
#      Fedora's own libva-v4l2-request is the abandoned 2019 Bootlin original
#      without the AVD fixes — a different package, not an upgrade path.
#      Installed as asahi_drv_video.so as well: libva derives the driver name
#      from the DRM render node, which is "asahi" here, so mpv/Chromium/ffmpeg
#      find it with NO environment variable. Mesa ships no asahi VA driver, so
#      nothing collides.
#
# Measured on the Mac mini M2 Pro 2026-09-10, 10 s of 4K30, ffmpeg decode with
# frames kept in VAAPI surfaces (the path playback actually uses):
#
#            H.264 8-bit   sw 4.96 s CPU  ->  AVD 0.28 s   (-94%)
#            HEVC 10-bit   sw 10.19 s CPU ->  AVD 0.26 s   (-97%)
#
# and 300/300 frames bit-exact against the software decoder (framemd5). The
# wall-clock is 3.8x realtime H.264 / 6.8x HEVC, so throughput is ample for
# playback even though software decode is FASTER in wall-clock on a 10-core
# M2 Pro — the win here is CPU, not speed. HEVC 10-bit comes out as P010
# directly, so none of the NV15 conversion pain the fork's README describes on
# Rockchip applies. docs/avd-decode-2026-09-10.md has the full working.
#
# Caveat carried deliberately: Firefox needs MOZ_DISABLE_RDD_SANDBOX=1 to use
# this, because its RDD sandbox blocks /dev/video* and /dev/media*. That
# weakens the media sandbox, so it is NOT set anywhere here — Chromium and mpv
# need nothing.
#
# No udev rule, no group edit: systemd-logind's uaccess tag already ACLs
# /dev/video0 and /dev/media0 to the seated user (verified 2026-09-10), the
# same way [[pkg]] ddcutil's i2c access works.
set -uo pipefail

warn() { echo "avd-decode: $*" >&2; }

# Apple Silicon only. Every device-tree machine has a compatible file, so it
# has to NAME Apple — a bare aarch64 test would try this on any ARM box.
[ "$(uname -m)" = aarch64 ] || exit 0
grep -Faiq 'apple,' /proc/device-tree/compatible 2>/dev/null || exit 0

fw_dir=/usr/lib/firmware/updates/apple
dri_dir=/usr/lib64/dri
drv="$dri_dir/v4l2_request_drv_video.so"
alias_so="$dri_dir/asahi_drv_video.so"

AVD_FW_VER=0.1
AVD_FW_SHA=2e131244275cb15c94243e41eec8a2a665ec895cfe3a818181549db991e62c67
VA_VER=1.3
VA_SHA=3670a1712f9f0a5a61bd44a781eba81dd9b2e0fd8271417ca8a9fbbed9dccfe9

# The VA driver entry point is VERSIONED (__vaDriverInit_1_<minor>) and libva
# refuses a driver whose symbol does not match its own minor. So "installed"
# is not enough — a Fedora libva bump silently breaks the driver until it is
# rebuilt, and this is the check that catches it rather than a user noticing
# playback got hot again.
va_abi_ok() {
  local want
  want="__vaDriverInit_$(pkg-config --modversion libva 2>/dev/null | cut -d. -f1,2)"
  [ "$want" = "__vaDriverInit_" ] && return 1
  nm -D --defined-only "$drv" 2>/dev/null | grep -q " T $want\$"
}

fw_ok() { [ -f "$fw_dir/avd-fw-v3-t1.bin" ] && [ -f "$fw_dir/avd-fw-v5-t1.bin" ]; }
drv_ok() { [ -f "$drv" ] && [ -L "$alias_so" ] && va_abi_ok; }

fw_ok && drv_ok && exit 0

for dep in meson ninja gcc nm curl; do
  command -v "$dep" >/dev/null 2>&1 ||
    { warn "$dep missing — skipping (rerun after 00-install-packages lands)"; exit 0; }
done

# Root by whichever route this run can reach (same ladder as 18-no-suspend).
run_root() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    echo "avd-decode: asking for authorization on screen…" >&2
    timeout 300 pkexec "$@"
  else
    return 1
  fi
}

src="$HOME/.local/src"
mkdir -p "$src" || { warn "cannot create $src"; exit 0; }

# Pinned tarball + sha256 rather than a git clone: both of these are firmware
# and a decoder in the media path, and the hashes are the only thing standing
# between a retag upstream and a silent change to what runs on the SoC. The
# libva hash is the same one the Arch PKGBUILD pins, checked independently.
fetch() {
  local url=$1 out=$2 want=$3 got
  if [ -f "$out" ]; then
    got=$(sha256sum "$out" | cut -d' ' -f1)
    [ "$got" = "$want" ] && return 0
    rm -f "$out"
  fi
  curl -fsSL "$url" -o "$out" || { warn "download failed: $url"; return 1; }
  got=$(sha256sum "$out" | cut -d' ' -f1)
  [ "$got" = "$want" ] || { warn "sha256 mismatch for $out (got $got)"; rm -f "$out"; return 1; }
}

# ---------------------------------------------------------------- firmware
if ! fw_ok; then
  # The cross toolchain is only needed HERE, on a machine that has never built
  # the blobs. arm-none-eabi-gcc-cs is 1.4 GB installed for six 64 KB outputs;
  # the manifest carries it aarch64-only so the NUC never pays for it.
  if ! command -v arm-none-eabi-gcc >/dev/null 2>&1; then
    warn "arm-none-eabi-gcc missing — skipping firmware (rerun after 00-install-packages lands)"
  else
    t="$src/avd-fw-$AVD_FW_VER.tar.gz"
    if fetch "https://github.com/AsahiLinux/avd-fw/archive/v$AVD_FW_VER/avd-fw-$AVD_FW_VER.tar.gz" \
             "$t" "$AVD_FW_SHA"; then
      d="$src/avd-fw-$AVD_FW_VER"
      rm -rf "$d" && tar xzf "$t" -C "$src" || warn "extract failed"
      # firmwaredir=firmware/updates under prefix=/usr puts the blobs in
      # /usr/lib/firmware/updates/apple — the FIRST path the kernel's firmware
      # loader searches, so these win over anything linux-firmware ever ships.
      # --cross-file is mandatory: meson.build errors out on a native build.
      if [ -d "$d" ] &&
         meson setup "$d/build" "$d" --prefix=/usr --libdir=lib \
           -Dfirmwaredir=firmware/updates \
           --cross-file="$d/arm-none-eabi-gcc.ini" >/dev/null 2>&1 &&
         meson compile -C "$d/build" >/dev/null 2>&1; then
        echo "avd-decode: installing AVD firmware"
        run_root meson install -C "$d/build" >/dev/null 2>&1 ||
          warn "firmware install failed"
      else
        warn "firmware build failed — try by hand in $d"
      fi
    fi
  fi
fi

# ------------------------------------------------------------- VA-API bridge
if ! drv_ok; then
  if ! pkg-config --exists libva 2>/dev/null; then
    warn "libva-devel missing — skipping VA driver (rerun after 00-install-packages lands)"
  else
    t="$src/libva-v4l2_request-$VA_VER.tar.gz"
    if fetch "https://github.com/sofus13/libva-v4l2_request/archive/refs/tags/$VA_VER.tar.gz" \
             "$t" "$VA_SHA"; then
      d="$src/libva-v4l2_request-$VA_VER"
      rm -rf "$d" && tar xzf "$t" -C "$src" || warn "extract failed"
      # driverdir is left unset so meson takes it from libva's own pkg-config
      # (/usr/lib64/dri here). The codec set is decided by configure-time
      # checks against the kernel uapi headers — all six (MPEG-2/H.264/HEVC/
      # VP8/VP9/AV1) compiled in on 7.1.13, though the M2's AVD only does
      # H.264, HEVC and VP9; AV1 is M3-and-later hardware.
      if [ -d "$d" ] &&
         meson setup "$d/build" "$d" --prefix=/usr --buildtype=plain \
           --wrap-mode=nodownload >/dev/null 2>&1 &&
         meson compile -C "$d/build" >/dev/null 2>&1; then
        echo "avd-decode: installing VA-API driver"
        if run_root meson install -C "$d/build" >/dev/null 2>&1; then
          run_root ln -sfn v4l2_request_drv_video.so "$alias_so" ||
            warn "asahi_drv_video.so symlink failed — set LIBVA_DRIVER_NAME=v4l2_request by hand"
        else
          warn "VA driver install failed"
        fi
      else
        warn "VA driver build failed — try by hand in $d"
      fi
    fi
  fi
fi

# ------------------------------------------------------------------- bring up
# The driver's probe already FAILED at boot, so the device sits unbound and no
# amount of new firmware moves it on its own. omarchy's note says a reboot is
# the only way; it is not — a manual bind re-runs probe and the decoder comes
# up live (verified 2026-09-10: "avd 287080000.avd: booting hw version: 30010",
# /dev/video0 and /dev/media0 appear within two seconds). Only worth doing when
# the firmware landed this run; on every later boot it probes by itself.
if fw_ok && [ ! -e /dev/video0 ]; then
  dev=$(ls /sys/bus/platform/devices/ 2>/dev/null | grep -m1 '\.avd$') || dev=""
  if [ -n "$dev" ] && [ ! -e "/sys/bus/platform/devices/$dev/driver" ]; then
    echo "avd-decode: binding the decoder (no reboot needed)"
    run_root sh -c "echo '$dev' > /sys/bus/platform/drivers/avd/bind" 2>/dev/null ||
      warn "bind failed — the decoder will come up on the next reboot"
  fi
fi

exit 0
