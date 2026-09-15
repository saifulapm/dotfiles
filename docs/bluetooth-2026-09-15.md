# Bluetooth on the Mac mini — battery, A2DP, and the HomePod's RTSP — 2026-09-15

User ask: review the Bluetooth setup; the Magic Keyboard and Trackpad show no
battery percentage, the HAVIT headset's audio "blinks" after a while, and the
HomePod sometimes stops working after pausing a video.

Four separate faults, three of them not in the same layer at all — and only
one of the four turned out to be a missing feature. The headset's headline
bug was already fixed by the kernel running on this machine, and the HomePod
is not a Bluetooth device. What follows is the evidence for each and the one
code change that came out of it.

## 1. Magic Keyboard / Trackpad battery — BlueZ never had it, UPower always did

`BluetoothDevice.battery` in the shell is `org.bluez.Battery1`, and BlueZ
publishes nothing for these two:

```
$ busctl --system get-property org.bluez /org/bluez/hci0/dev_E0_EB_40_DE_0D_4B \
      org.bluez.Battery1 Percentage
Failed to get property Percentage ...: No such interface 'org.bluez.Battery1'
```

That is not a regression and not configurable. BlueZ fills `Battery1` from two
places only: the GATT Battery Service (these accessories do not implement it)
and an external *battery provider*. PipeWire registers a provider for HFP
audio (`AT+IPHONEACCEV`) — which is why an ordinary headset shows a level and
these do not — and BlueZ's own HID provider is a build-time thing Fedora does
not carry (`strings /usr/libexec/bluetooth/bluetoothd` has no
`/sys/class/power_supply` anywhere).

The level was never missing from the machine, only from BlueZ. `hid-apple`
feeds it to the kernel, the kernel exposes it as a power supply named after
the same address, and UPower publishes that:

```
/sys/class/power_supply/hid-e0:eb:40:de:0d:4b-battery-144/uevent
POWER_SUPPLY_CAPACITY=73
POWER_SUPPLY_MODEL_NAME=Saiful Islam’s Magic Keyboard

$ upower -i /org/freedesktop/UPower/devices/battery_hid_e0oebo40odeo0do4b_battery_144
    percentage:          73%
```

So `BtBatteryService.qml` grew a second source rather than the widget growing
a second code path. It already owns "the reading for one device, in the shape
`Model.batteryText` renders", so UPower's number is folded into the same
`{single: {level, charging}}` shape and keyed by the MAC in `nativePath`
(`hid-e0:eb:40:de:0d:4b-battery-144`). The widget, the panel, the tooltip and
`BluetoothModel.js` are untouched: `batteryFor()` returns AAP first (richer —
per pod and case), UPower only fills a hole.

Read the same event-driven way AAP is: Quickshell's UPower service mirrors
`DeviceAdded`/`DeviceRemoved` plus every device's `PropertiesChanged`, so this
is a binding, not a timer. The MAC is matched anywhere in `nativePath` rather
than after a `hid-` prefix — the address is the only part whose shape is
guaranteed, and an anchor would stop matching the day a driver renames the
power supply.

Verified against the live devices, both reading 73%:

```
HID MAP: {"E0:EB:40:DE:0D:4B":{"single":{"level":73,"charging":false}},
          "BC:D0:74:B9:7B:8D":{"single":{"level":73,"charging":false}}}
```

It also covers a case nothing asked for: UPower meters Bluetooth *headsets*
too (`headset_dev_67_6D_E6_03_06_ED` is in its device list), so a headset whose
BlueZ battery is absent but whose UPower battery is present shows a level for
free.

## 2. The headset — the Asahi cause was real, and is now verified fixed

"A2DP stutters and drops out every few seconds" on BCM4377/4378/4388 is a known
Apple Silicon defect with a known cause: the chip needs Broadcom's
`HCI_BRCM_SET_ACL_PRIORITY` (`0xFC57`) vendor command for ACL links carrying
audio, or *anything that scans* costs ~10 s of audio. macOS and Android send it
automatically; BlueZ never has. The fix landed in the Asahi kernel on
2026-04-30 (`net/bluetooth/brcm.c`, gated behind `CONFIG_BT_BRCMEXT`), keyed
off `setsockopt(SO_PRIORITY)` — a call PipeWire already makes on the A2DP
transport fd (`spa/plugins/bluez5/media-sink.c`: `val = 6; setsockopt(…,
SO_PRIORITY, …)`, and `TC_PRIO_INTERACTIVE` is 6).

Both halves are on this box, checked rather than assumed:

```
$ grep CONFIG_BT_BRCMEXT /boot/config-$(uname -r)     -> CONFIG_BT_BRCMEXT=y
$ strings …/bluetooth.ko | grep brcm_set_high_priority -> brcm_set_high_priority
$ rpm -q --changelog kernel-16k-core | grep -i broadcom
- redhat/configs: Enable Broadcom Bluetooth extensions
- Bluetooth: Add Broadcom channel priority commands
```

and the userspace half was *provably* firing (no `SO_PRIORITY failed` anywhere in
the journals — that log is what a failing vendor command produces), but that is
only an absence of errors: `brcm_set_high_priority()` returns 0 *silently* when
the driver never marked the chip, so a missing command looks identical from
userspace. It was settled on the wire instead, with `btmon` reading a
disconnect/reconnect:

```
17:04:47.261709 < HCI Command: Broadcom Write High Priority Connection (0x3f|0x0057) plen 3
      Handle: 19 (BR-ACL) Address: 67:6D:E6:03:06:ED
      Priority: High (0x01)
17:04:47.263518 > HCI Event: Command Complete (0x0e) plen 4
      Broadcom Write High Priority Connection (0x3f|0x0057) ncmd 1
        Status: Success (0x00)
```

Sent exactly once per connection, right after the new ACL came up and the A2DP
transport was acquired. The documented Asahi stutter cause is closed on this
machine — and note it can only ever be captured across a *fresh* connection:
the command fires on the transition of the transport socket's `SO_PRIORITY`
from 0 to 6, and `sink-keepalive.conf` keeps the transport alive across pause,
so a mid-playback capture contains nothing to trigger it.

### What is still there: 230 ms dropouts, 31 s apart

Three ~90 s captures of the same music. Two of them — the connection that was
already up — are metronomic: 4219 and 4218 A2DP packets, median interval
21.30 ms (one AAC frame at 48 kHz), RTP sequence numbers contiguous, and
**zero** L2CAP frame latencies over 300 ms. The third capture, taken across a
disconnect/reconnect, shows the fault, on the new connection only:

```
17:05:24.72   latency 359 -> 387 -> 351 -> 330 -> 317 -> 296 -> 72 -> 34 -> 21 ms
17:05:55.68   latency 366 -> 438 -> 425 -> 404 -> 392 -> 371 -> 357 -> 118 -> 31 ms
17:06:26.69   latency 358 -> 409 -> 400 -> 379 -> 368 -> 347 -> 335 -> 104 -> 43 ms
```

Each is ~400 ms of A2DP frames backing up and then draining almost at once,
which is a ~230 ms hole in the audio. They are **31.0 s apart** — the interval
between the three is 30.96 s and 31.01 s — and there are 40 `Latency: [3-9]xx`
lines in that capture against **0** in either of the other two.

What it is not:

- not the audio path. The TX stream is gapless apart from those three holes,
  there is no `Failure in Bluetooth audio transport`, no disconnect, no
  hardware error, and no flow-control stall.
- not CPU or PipeWire. `pw-top` reports `ERR 0` and `B/Q 0.02`.
- not an HCI event *at* the stall — but widen the window by half a second and
  the cause is sitting there.

### The cause: the Apple HID battery poll, and the sniff transition it forces

The stall lands 0.36–0.38 s behind an `Exit Sniff Mode` on the **trackpad's**
link — never the headset's, and consistent to 20 ms across all three:

```
17:05:24.338306 < HCI Command: Exit Sniff Mode (0x02|0x0004) plen 2   Handle: 13
17:05:55.310230 < HCI Command: Exit Sniff Mode (0x02|0x0004) plen 2   Handle: 13
17:06:26.325743 < HCI Command: Exit Sniff Mode (0x02|0x0004) plen 2   Handle: 13
```

and those three are themselves 30.97 s and 31.02 s apart. Every one of the 23
`Exit Sniff Mode` commands in the capture has a host→device packet on handle 12
(keyboard) or 13 (trackpad) in the **same millisecond** — the kernel exits sniff
because it has something to send to the HID device. What it has to send is two
bytes, and they are not incidental:

```
< ACL: Handle 13 flags 0x00 dlen 6                    #5562 [hci0] 17:05:24.338303
      Channel: 72 len 2 [PSM 0 mode Basic (0x00)]
        41 90                                            A.
< HCI Command: Exit Sniff Mode (0x02|0x0004) plen 2   #5563 [hci0] 17:05:24.338306
      Handle: 13
```

`41 90` is `GET_REPORT` for report id `0x90` — the Apple battery poll, the same
fetch the BlueZ input profile is known to loop on for a Magic Trackpad, and the
same one `hid-apple` drives from its own timer. So:

1. the Apple HID battery poll fires for the trackpad (and the keyboard, about a
   second later) roughly every 31 s;
2. the link is in sniff mode, so the host must take it out of sniff first — same
   millisecond;
3. the sniff → active transition occupies the shared BCM4388 radio for ~360 ms,
   during which the A2DP link is not served: ~400 ms of frames back up and then
   drain, ~230 ms of it audible;
4. repeat every 31 s.

The irony worth recording: this is the cost of §1. The battery percentage the
shell now shows is published by that same poll — `APPLE_RDESC_BATTERY` and the
delayed-work battery fetch exist precisely so the level can be noticed at all,
because over Bluetooth these devices send no unsolicited updates. The feature
that fills the tooltip is what empties the music for a fifth of a second every
half minute.

What this rules out: the codec (AAC through FDK is fine, and SBC at ~229–328 kbps
against AAC's ~240 would not have helped), the audio path, PipeWire and
scheduling, and the headset's multipoint (confirmed off — only this machine).
Two of the three captures looking perfect is explained too: both were taken while
the HID links were busy and not yet parked in sniff.

No clean knob removes either half: the poll is a device-table quirk with no
runtime switch, and the sniff entry is the device's own power management, so the
host can only pay for the exit. It is recorded as a measured trade-off rather
than "fixed", and the test that would confirm it end to end is to disconnect the
trackpad for a few minutes and listen.

Separate from the stalls, and much rarer, the transport does occasionally die
outright — ~1–3 a day since 2026-09-07, two of the seven logged being shutdown
artefacts that land on the same second as `Stopping homepod-sink`:

```
spa.bluez5.sink.media: connection (…/dev_67_6D_E6_03_06_ED/sep2/fd0) terminated unexpectedly
pw.node: (bluez_output.67_6D_E6_03_06_ED.1-93) running -> error (Received error event)
spa.bluez5: Failure in Bluetooth audio transport …/sep2/fd0
```

That is the *remote* closing its end of the transport, which is device-side and
the same category as the AVRCP wedge: this headset is abnormal enough to need a
guard of its own.

### The buttons, and why `havit-guard` did not save them

The headset's buttons were dead for the whole session before that reconnect:
`org.bluez.MediaControl1 Connected` was `false` and no `HAVIT LITE NC01H
(AVRCP)` uinput device existed, which is the connect-time AVRCP wedge
`bin/havit-guard` was written for. It declined to act three times in a row —
`AVRCP down but a stream is live — standing down` at 16:43:12, :24, :36 —
because audio started inside its 12 s settle window, and its rule is that a
live stream always wins. Powering the headset on and pressing play is exactly
that pattern, so the wedge survived every session; one manual disconnect and
reconnect fixed it, and the buttons have worked since.

Both halves of the button path are then fine, and both are visible in the
BlueZ + PipeWire monitors:

```
17:04:52 DBUS path=…/sep2/fd0 member=PropertiesChanged   -> string "Volume"
17:04:52 PWVOL 0.031244
17:04:53 DBUS … "Volume"                                 -> PWVOL 0.053990
17:04:55 DBUS … "Volume"                                 -> PWVOL 0.031244
```

The headset's absolute-volume commands reach the BlueZ transport, and PipeWire
follows them into the sink volume the OSD binds to (`Services/Audio.qml` →
`audio.volume`). Nothing needed fixing there — what needed fixing was the
connection, so `bin/havit-guard` no longer lets a live stream outrank the wedge:
as of 2026-09-15 it cycles the connection at connect time whether audio is
playing or not, at the cost of a ~2 s gap, with the once-per-5-minute cooldown
left in place as the thing that actually prevents a loop.

## 3. The HomePod is not a Bluetooth device

`HomePod (Office)` is our own RAOP sink — a standalone PipeWire instance
(`bin/homepod-sink`) talking AirPlay to 192.168.68.50 over the office Wi-Fi.
BlueZ is not involved, which is why nothing about it appears in a Bluetooth
review until now; the pause/resume failure is in PipeWire's
`module-raop-sink`, and the interesting part is what it does when the sink
goes idle.

A silent two-play test (`pw-play` of 2 s of silence, twice, 30 s apart)
captured at `log.level = 3` shows the whole lifecycle. Idle → suspend sends a
TEARDOWN:

```
14:01:37 mod.raop-sink: cannot close connection yet - timer is still running
14:01:37 pw.node: (raop_sink.…-41) running -> idle
14:01:42 pw.node: (raop_sink.…-41) idle -> suspended
14:01:42 sent: TEARDOWN … / teardown status: 200
```

and the next playback re-negotiates on the same RTSP connection, without even
re-sending OPTIONS, because `impl->connected` is still true:

```
14:02:07 sent: ANNOUNCE … / announce status: 200
14:02:07 sent: SETUP …    / setup status: 200
14:02:07 sent: RECORD …   / record status: 200
```

The happy path is sound, which is the point: on this box the pause/resume
cycle works, and what the journal can say about the times it does not is
almost nothing. Every line that would name the failing request —
`record status`, `announce status`, `setup status`, `teardown status` — is
`pw_log_info`, while the child has always run at `log.level = 2` (warn). The
only RAOP line level 2 has ever produced here is the transport error, which is
also what a benign broken pipe prints:

```
mod.raop-sink: error -32            # EPIPE; ~6-12 min apart, all day Sep 9-10
```

Reading `rtsp-client.c` against that line is what makes it benign rather than
suspicious: its `error:` path emits `error` and *then* calls
`pw_rtsp_client_disconnect`, which emits `disconnected` — and the module's
`rtsp_disconnected` clears `connected` and runs `connection_cleanup`. So a
dead RTSP connection leaves the module in a clean, reconnectable state, and
the next resume starts a new session (new random id, hence a new
`rtsp://<ip>/<id>` URL) from OPTIONS. No zombie.

Two paths remain that would produce a sink which is present but idle:

- a non-200 reply to `rtsp_record_reply` calls
  `pw_impl_module_schedule_destroy()` — the module *deletes itself* and the
  sink disappears from the graph. `bin/homepod-sink` is the only thing that
  catches it, and only after two consecutive misses of a 60 s poll, so that
  recovery costs up to two minutes;
- a resume whose ANNOUNCE/RECORD the HomePod simply refuses or ignores, while
  every status it does answer is 200. Nothing local can see that at level 2,
  and nothing local logs a missing RTP flow at all.

Neither has been observed here: `homepod-sink` has never printed
`sink vanished from the daemon` nor `pipewire child exited`, in the whole
journal (which starts 2026-09-07), so the module has never destroyed itself on
this machine. That is why nothing was "fixed" in §3 beyond making the next
occurrence visible — the first two candidate causes point at opposite fixes
(shrink the watchdog, or stop the HomePod refusing a session), and guessing
between them is how the earlier `audio-heal` timer came to be the interruption
rather than the cure.

`bin/homepod-sink` now takes its child's log level from `RAOP_LOG_LEVEL`
(default 2, unchanged), so the next occurrence can be captured without editing
a file:

```sh
systemctl --user set-environment RAOP_LOG_LEVEL=3
systemctl --user restart homepod-sink      # reproduce, then read the journal
systemctl --user unset-environment RAOP_LOG_LEVEL
systemctl --user restart homepod-sink      # level 3 logs a line per
                                           # /feedback POST, every 2 s playing
```

Deliberately NOT changed: the recovery watchdog, and the
`sess.latency.msec 250 … should be an integer multiple of rtp.ptime 7.981859`
warning. The warning is benign — `rtp_stream_new()` rounds `target_buffer`
down to a whole ptime, so the sink actually runs at 247.4 ms rather than 250,
which is exactly why its own node property reads `node.latency = 10912/44100`
and not a round figure. It is a cosmetic complaint about a value the user
never chose.

## 4. Audited and left alone

- `hci0: Failed to read codec capabilities (-22)`, ×10 at boot. Broadcom LE
  Audio codec capabilities; nothing here uses LE Audio.
- `hci0: Bad flag given (0x1) vs supported (0xe)` and bluetoothd's
  `set_wake_allowed_complete() … Invalid Parameters`. BlueZ 5.87's `WakeAllowed`
  device flag against a kernel that does not implement it. Suspend is disabled
  fleet-wide (`packages/manifest.toml`), so the feature it would enable is moot.
- `quickshell.service.upower: sent removal signal for … which is not
  registered`, once per boot. A UPower D-Bus race at session start, pre-existing
  and self-correcting; the same race once logged a `GetAll` failure for the
  keyboard's battery device, which is why the new binding guards on `ready`.
- `/etc/bluetooth/main.conf` and `input.conf` are stock Fedora (every setting
  commented out). Nothing in the current symptoms points at anything in them,
  and the repo rule is that a setting earns its place with a reason.

## 5. Notes for the next capture

`btmon` needs root (`Failed to bind channel: Operation not permitted`), but it
can *write* the trace as root and the trace can be *read* unprivileged —
`btmon -r file.btsnoop` with no privileges at all. Two traps found the hard way:

- `btmon -r` prints no timestamps by default; without `-t` the decoded text has
  no clock, so nothing can be correlated with a journal or with the user's "it
  blinked at about 5:05". Use `btmon -r file -t -N -c never -C 200`.
- btmon 5.87 labels audio ACL packets `< BR-ACL:` once it has seen the
  connection come up, and plain `< ACL:` for links that were already established
  when the capture started. A `grep '^< ACL: Handle'` therefore silently reads
  only part of a capture; match both.
