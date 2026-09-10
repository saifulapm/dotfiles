# AVD hardware video decode on the Macs — 2026-09-10

Both Macs have had a hardware video decoder sitting idle since the day they
were installed. The kernel ships the driver — `CONFIG_VIDEO_APPLE_AVD=m`,
`apple_avd` autoloads and autoprobes — and then gives up every boot:

```
avd 287080000.avd: Direct firmware load for apple/avd-fw-v3-t1.bin failed with error -2
avd 287080000.avd: failed to load firmware: -2
avd 287080000.avd: probe with driver avd failed with error -2
```

No `/dev/video0`, no decoder, every frame on the CPU. `/lib/firmware/apple/`
did not exist and `dnf provides '*avd-fw*'` is empty: **Fedora Asahi Remix
ships no AVD firmware**, which Asahi's own 7.2 progress report says is
deliberate — the desktop integration is not finished upstream.

Found by auditing this repo against `omacom/omarchy-mac`, whose
`install/hardware/apple/video-decode.sh` installs the same two pieces from
their private aarch64 repo. It was the only Apple-Silicon thing in that repo
this fleet did not already have; §6 lists everything else that was checked and
rejected.

## 1. The two pieces

**Firmware** — [`AsahiLinux/avd-fw`](https://github.com/AsahiLinux/avd-fw)
v0.1, MIT. Asahi wrote their own rather than extracting Apple's: AVD is
"a secret third thing", neither RTKit nor EPIC, essentially a Cortex-M3
driving fixed-function blocks. The replacement firmware is deliberately dumb —
it installs interrupt handlers and applies each variant's tunables, and the
kernel and userspace parse all the video — precisely so VA-API and Vulkan
Video are easier to build on later. Six blobs, ~390 KB total; this M2 Pro
wants `avd-fw-v3-t1.bin`.

**VA-API bridge** — [`sofus13/libva-v4l2_request`](https://github.com/sofus13/libva-v4l2_request)
1.3. AVD is a *stateless* decoder, which almost nothing on the desktop speaks;
ffmpeg's `v4l2m2m` decoders are stateful and never negotiate with it. sofus13
forked megi's (abandoned Bootlin) VA-API-to-V4L2-stateless translation layer
and carries the AVD fixes. Installed as `asahi_drv_video.so` as well, because
libva derives the driver name from the DRM render node — `asahi` here — so
mpv, ffmpeg and Chromium find it with **no environment variable**. Mesa ships
no asahi VA driver, so nothing collides.

`run_after_54-avd-decode.sh` builds and installs both, pinned by tarball
sha256. The libva hash matches the one the Arch PKGBUILD pins, arrived at
independently.

## 1a. The decoder alone changes nothing — mpv defaults to `hwdec=no`

Easy to declare victory at `/dev/video0` and ship a decoder no player ever
asks for. `hwdec` appeared **nowhere** in this repo, and mpv's built-in
default is `no`, so every measurement below would have been true of a machine
still decoding 4K HEVC on the CPU. `home/dot_config/mpv/mpv.conf` now sets
`hwdec=vaapi`, and because dekho runs mpv as a child process that single line
covers the whole video path here: dekho, the yt-dlp extension's completion
toast, `bin/music`, `bin/youtube`.

`vaapi` rather than the more idiomatic `auto-safe` on purpose. `auto-safe`
does reach VA-API, but only after trying `h264-vulkan` and `h264-vulkan-copy`
first — and Vulkan Video does not exist on Apple GPUs, so both fail with
"Failed setup for format vulkan: hwaccel initialisation returned error" on
every file before it falls through. Naming `vaapi` skips two guaranteed
failures per playback. Not `vaapi-copy` either: plain `vaapi` keeps frames in
VAAPI surfaces the whole way (`VO: [gpu-next] 1920x1080 vaapi[nv12]`), and the
copy variant is the 2.32 s row in the table below rather than the 0.28 s one.

## 2. What it is worth

Measured on the Mac mini M2 Pro, 10 s of 4K30, `ffmpeg` decode. The first
table is `-f null` **without** `-hwaccel_output_format vaapi`, which downloads
every frame back to system memory — that is not what playback does, and it
hides most of the win:

| 4K30 H.264 | wall | CPU time |
|---|---|---|
| software | 0.77 s | 4.96 s |
| AVD, frames downloaded | 2.67 s | 2.32 s |
| **AVD, frames left in VAAPI surfaces** | 2.64 s | **0.28 s** |

The real comparison, both codecs, frames kept on the GPU:

| Stream | software CPU | AVD CPU | saved |
|---|---|---|---|
| 4K30 H.264 8-bit | 4.96 s | 0.28 s | **94%** |
| 4K30 HEVC 10-bit | 10.19 s | 0.26 s | **97%** |

omarchy quotes ~84%; kept on the GPU it is better than that. HEVC 10-bit is
the case that mattered — a full core sustained, gone.

**Software decode is still FASTER in wall-clock** on a 10-core M2 Pro: 12.9x
realtime against AVD's 3.8x for H.264. That is not a defect and not a reason
to skip this. Playback needs 1x; the AVD path delivers 3.8x–6.8x while using
a twentieth of the CPU, and the CPU is what the rest of the desk is competing
for. On the MacBook it is battery.

10-bit HEVC comes out as **P010 directly**, so none of the NV15-to-NV12
conversion pain the fork's README describes on Rockchip applies here.

## 3. It is correct, not just fast

300 frames of 4K H.264 decoded both ways to `yuv420p` and compared with
`-f framemd5`: **all 300 bit-exact**. A fast decoder that is subtly wrong
would be worse than none, and "it played and looked fine" does not detect
that.

Codecs exercised on this M2 Pro: H.264 (`decoding h264 via /dev/video0
[avd]`, NV12), HEVC 10-bit (P010), VP9 (NV12). mpv reports `Using hardware
decoding (vaapi-copy).` All six codecs compile in — the set is decided by
configure-time checks against the kernel uapi headers — but AV1 is M3-and-later
hardware and MPEG-2/VP8 were not tested.

## 4. No reboot, and no udev rule

omarchy's note says "the decoder only probes at boot, so nothing here rebinds
it: the reboot that follows setup is what brings it up." That is not true, and
the script does better. The failed probe leaves the platform device *unbound*,
so a manual bind re-runs it:

```sh
echo 287080000.avd | sudo tee /sys/bus/platform/drivers/avd/bind
```

`avd 287080000.avd: booting hw version: 30010`, and `/dev/video0` and
`/dev/media0` appear within two seconds. The script does this only when the
firmware landed on that run; every later boot probes by itself.

Nothing privileged is installed for the feature — no udev rule, no group edit.
systemd-logind's `uaccess` tag already ACLs `/dev/video0` and `/dev/media0` to
the seated user (`user:saiful:rw-`), the same way [[pkg]] `ddcutil`'s i2c
access works.

## 5. What was rejected

- **`copr:jannau/test-builds`** — has a *succeeded* `fedora-44-aarch64`
  `avd-fw` 0.1-1 build, from an Asahi upstream developer, and would have
  removed the 1.4 GB cross toolchain from the manifest entirely. Its own
  description reads "test builds do not use". Enabling a COPR that disclaims
  itself, fleet-wide, to save disk on a machine with 154 GB free is the wrong
  trade. His [`jannau/avd-fw-spec`](https://github.com/jannau/avd-fw-spec) is
  still what proved the Fedora build works — it is where the
  `arm-none-eabi-gcc-cs` + `meson` dependency set came from.
- **Committing the prebuilt blobs** — 390 KB, MIT, and it would end the
  toolchain question. Rejected: this repo is public and carries no other
  unauditable binary. If the 1.4 GB ever bites, the honest swap is `vendor/`
  carrying the avd-fw *source* and a hand-run build, which is what `vendor/`
  is for.
- **Fedora's `libva-v4l2-request`** (1.0.0-18.20190517git) — the abandoned
  2019 Bootlin original, no AVD support. A different package, not an older
  version of the one installed.
- **Vulkan Video** — mpv lists `h264-vulkan`/`hevc-vulkan`/`av1-vulkan`
  hwdecs and Honeykrisp is a conformant Vulkan 1.4 driver, so this looked like
  it might skip the VA-API layer entirely. It cannot: Mesa has no video-decode
  implementation for Apple GPUs, and Asahi lists direct scanout and Vulkan
  Video as still in development.
- **Firefox** — works, but only with `MOZ_DISABLE_RDD_SANDBOX=1`, because the
  RDD sandbox blocks `/dev/video*` and `/dev/media*`. Weakening a media
  sandbox is not worth a browser this fleet does not default to, so it is set
  nowhere. Chromium and mpv need nothing.

## 5a. Chromium cannot use it, and no flag will change that

`chrome://gpu` reports `Video Decode: Software only. Hardware acceleration
disabled` / `Disabled Features: video_decode`, with an empty **Video
Acceleration Information** table.

The first read of this was wrong and is worth recording, because the two
obvious pieces of evidence both mislead. `strings` finds `VaapiVideoDecoder`
in the binary, and `ldd` shows `libva.so.2`, `libva-drm.so.2` and
`libva-x11.so.2` resolved — which together look exactly like a build with
VA-API compiled in and merely gated off. Neither means what it looks like:

- The feature *name* survives in the feature-list table even when the
  implementation is compiled out.
- Chromium has 57 `NEEDED` entries and **none of them is libva**. The
  libraries `ldd` showed come in transitively through `libavcodec.so.62` and
  `libavutil.so.60`, i.e. ffmpeg's own VA-API support, not Chromium's.

The decisive checks: `nm -D --undefined-only` imports **zero** libva symbols
(the one `va*` hit is glibc's `vasprintf`), and nothing under
`/usr/lib64/chromium-browser/` contains the string `libva.so.2`, so it is not
dlopened either. **Fedora's aarch64 Chromium is built without VA-API.**

Confirmed empirically before concluding it: a throwaway-profile instance with
`--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiVideoDecoder
--ignore-gpu-blocklist --vmodule='*vaapi*=3'` never printed the
`libva-v4l2request:` banner our driver emits on every init, headless or
windowed. `kAcceleratedVideoDecodeLinuxGL` is the right feature name for the
Linux/GL gate; there is simply nothing behind it in this build.

So video played *inside* a Chromium tab — YouTube, the web apps, Zoom —
stays on the CPU. That matters less here than it would elsewhere, because
this desk already routes video out of the browser: the yt-dlp extension and
`bin/youtube` hand the URL to `chromium-ytdlp-host`, which downloads and
opens the file in **mpv**, and `bin/music` and dekho are mpv too. Every one
of those paths is hardware-decoded now.

Firefox is the only other route (it would need `MOZ_DISABLE_RDD_SANDBOX=1`)
and is not installed. Rebuilding Chromium with `use_vaapi=true` is not worth
considering for this.

## 6. What else the audit checked, and found nothing to do

Against `omacom/omarchy-mac` (Arch/Hyprland on Apple Silicon — a different
distro and compositor, so only its hardware layer transfers):

- **rtkit / pipewire-pulse / asahi-audio / speakersafetyd** — all present.
  PipeWire's `data-loop.0` threads are SCHED_RR prio 60 here, so the realtime
  path that [[pkg]] `rtkit` exists to protect is healthy.
- **`vulkan-asahi` / Honeykrisp** — `asahi_icd` present. Mesa 26.1.8 from
  Fedora *updates* is ahead of the Asahi COPR's 26.0.6, so the COPR is
  correctly just a fallback.
- **brcmfmac WPA-offload fix** — x86_64-gated upstream on purpose; it breaks
  Apple Silicon, where the offload is the half that works.
- **`omarchy-wifi-resume-fix`** — needs suspend, and `run_after_18-no-suspend`
  masks `sleep.target` fleet-wide. Also this mini is BCM4388, which omarchy
  excludes anyway.
- **`show_notch`** — the MacBook Pro 13-inch M2 (J493) has no notch. N/A
  fleet-wide, not just here.
- **`electron-gl`, hibernation setup, T2 fixes, SPI keyboard, NVMe suspend** —
  all no-ops on this hardware or this distro.
- **Asahi mic stereo remap** — their `omarchy-asahi-mic.service` builds a null
  sink and links the beamformed AUX0 capture into it. `bin/voxtype-mic-gate`
  already answers the problem that actually bit us (a source muted at rest),
  and answers it better: the mute stays the privacy posture.
- **HID boot race** (their one Apple-specific doc: trackpad dead for a whole
  session) — mostly cannot happen on Fedora. `dracut-asahi`'s
  `91kernel-modules-asahi` already puts `dockchannel-hid`/`spi-hid-apple` in
  the initramfs, and **`hid_magicmouse` is builtin** on the Asahi kernel, so
  the trackpad binds correctly on first registration. Only `hid_apple` is
  still a module; `run_after_55-apple-hid-initramfs.sh` forces it into the
  initramfs on the MacBook as cheap insurance. Nothing in this fleet's logs
  has shown the symptom.

Against `joshuaswarren/mlx-omarchy` and `ml-explore/mlx`: **nothing to adopt.**
mlx-omarchy is a Vulkan/ANE MLX backend for Apple Silicon on Linux, and
`docs/compatibility.md` says "M2, M3, and M4 Omarchy Linux work is deferred" —
it is M1-only, and assumes Arch/Omarchy plus Python 3.14 wheels. Both Macs
here are M2. Upstream MLX is Metal-on-macOS, CUDA-or-CPU on Linux; there *is*
a `manylinux_2_35_aarch64` wheel so `pip install mlx` would work on these
Macs, but CPU-only — NumPy-with-autograd, no GPU, and llama.cpp/whisper.cpp
already cover local inference better. Revisit when mlx-omarchy reaches M2.

## 7. Verify

```sh
ls /dev/video0 /dev/media0
journalctl -k -b | grep avd            # expect "booting hw version"
LIBVA_MESSAGING_LEVEL=2 ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
  -hwaccel_output_format vaapi -i FILE -f null -   # expect "via /dev/video0 [avd]"
mpv FILE                               # config alone must give
                                       #   "Using hardware decoding (vaapi)."
                                       #   "VO: [gpu-next] ... vaapi[nv12]"
```

The mpv line is the one that actually matters — the three above it can all
pass on a machine where no player is configured to ask.

## 8. The one thing that will break this

The VA driver's entry point is versioned — it exports `__vaDriverInit_1_23`
against libva 2.23 — and libva refuses a driver whose minor does not match.
A Fedora libva bump therefore *silently* disables hardware decode; nothing
errors, playback just gets hot again. `run_after_54`'s `va_abi_ok` compares
the exported symbol against `pkg-config --modversion libva` on every apply and
rebuilds on a mismatch, so `update-all` repairs it without anyone noticing it
broke. That check, not the install, is the part of the script worth keeping.
