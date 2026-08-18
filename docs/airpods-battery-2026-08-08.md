# AirPods battery in the Bluetooth panel (2026-08-08)

The panel and the widget tooltip have always been able to draw a battery
figure — `BluetoothDevice.batteryAvailable` / `.battery`, straight from
`org.bluez.Battery1`. With AirPods connected, that flag is false and the row
stays blank. This records why, and what feeds it now.

## BlueZ can only publish a battery something hands it

`org.bluez.Battery1` has two sources:

- the device's own GATT Battery Service (0x180F), or
- a **battery provider** registered on the device's behalf through
  `org.bluez.BatteryProviderManager1`.

Neither fires for AirPods here:

- **No GATT BAS.** Enumerating the AirPods Pro's GATT tree gives eight
  services — `9bd708d7…`, `7798082b…`, `fd44` (Apple Find My), `87290102…`,
  `1804` (TX Power), `180a` (Device Information), `4715650b…`, `1801` — and no
  `180f`.
- **The provider never gets anything to forward.** PipeWire is the provider
  (`libspa-bluez5.so` carries `RegisterBatteryProvider`, "Created virtual
  battery for %s", "battery level: %u%%"); it learns the level from Apple's
  `AT+IPHONEACCEV` over HFP. AirPods never send it.

That last point is the one worth not re-deriving. With
`wpctl set-log-level 4` and the whole HFP service-level connection captured
twice — once by connecting only the Handsfree profile on the live link
(`Device1.ConnectProfile 0000111e-…`), once across a full
`Disconnect`/`Connect` — the AirPods' entire AT conversation is:

```
AT+BRSF=667 · AT+BAC=1,2,127,255,128,129,130,256 · AT+CIND=? · AT+CIND?
AT+CMER=3,0,0,1 · AT+VGS=15 · AT+VGM=3 · AT+BIA=0,1,1,1,0,0,0 · AT+NREC=0
AT+BCS=127
```

No `AT+XAPL`, no `AT+IPHONEACCEV`, either time. So the HFP path is closed by
the device, not by our configuration. Specifically **not** at fault, and
therefore left alone:

- `home/dot_config/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf`
  restricting `bluez5.auto-connect` to `[ a2dp_sink a2dp_source ]` — BlueZ's own
  `Device1.Connect()` brings HFP up regardless, and it did.
- `Experimental = true` in `/etc/bluetooth/main.conf` — bluez 5.87 logs
  "Battery Provider Manager created" at startup without it, so the provider
  interface is already there.
- PipeWire's HFP roles or codecs — the gateway works; `AT+NREC=0` drawing
  `ERROR` ("modem not available") is correct, our `+BRSF: 3584` never claimed
  EC/NR, and the AirPods carry on past it either way.

## What does work: AAP on L2CAP PSM 0x1001

Apple accessories report battery over the Apple Accessory Protocol — an L2CAP
channel on PSM 0x1001, riding the same ACL link as the audio. After a fixed
three-message handshake the device pushes a notification whenever a level
changes, **per pod plus the case**, which is more than HFP would ever have
carried.

`bin/bluetooth-battery <address>` is that reader: stock python3
`AF_BLUETOOTH`/`BTPROTO_L2CAP`, no packages added, one JSON line per change,
blocked in `recv()` the rest of the time. Measured on this desk: 0.19 s to
connect, first battery packet 0.03 s after the notification request.

Protocol credit and the one correction to the published byte strings (the
notification bitmask must be `ff ff ff ff`; librepods' `ff ff fe ff` makes the
device dump its whole state and withhold battery) are in

## Wiring

`Modules/Bar/widgets/BtBatteryService.qml` is a bar-root shared service (S2 —
one instance however many screens carry the widget). It runs one reader per
connected device, lifetime driven straight off `Bluetooth.devices`: no timer in
the file, and destroying the delegate kills the child (quickshell's `Process`
destructor kills; `setpriv --pdeathsig TERM` covers a hard shell death).

Two details that matter:

- The Instantiator model is a **latched** copy of the connected-address list
  (`readerKey` guard, the workspaces `sameIds` pattern). An array model rebuilds
  every delegate when reassigned, and `Bluetooth.devices` churns constantly
  while the panel is open and scanning — without the latch, discovery would
  tear down and re-handshake a live reader every few seconds.
- Readers are started for **every** connected device, not just recognisable
  Apple ones: quickshell exposes no vendor field, and a device without an AAP
  endpoint refuses the channel — the helper exits 3 after a bounded ladder
  (~4 s). Cheaper and more honest than guessing from a name the user can rename.

Display: `Model.batteryText()` renders `L 86% · R 86% · Case 45%`, charging
components carrying `󰂄`. AAP wins over `org.bluez.Battery1` where both exist
(per-pod beats one number); everything else falls back to the old figure, so
non-Apple headsets are unaffected.

## Verified / not verified

Verified live (AirPods Pro 2, model A2698): row reads `L 85% · R 85%` in the
panel; reader auto-starts at shell start for an already-connected device;
survives 6 s of active discovery without restarting; exits on disconnect and the
entry is dropped; respawns on reconnect; exit 3 for a non-AAP address; clean
shell log throughout.

Not verified — no way to force it from here: the **case** reading and the
**charging** flag. Both pods were in use for every capture, so the case reported
status `0x04` (out of range, level 0, correctly dropped) and nothing ever
reported charging. If either reads wrong, the suspects are in that order:
`COMPONENTS` (left/right are indistinguishable on the wire — flipping those two
entries is the whole fix) and `STATUS_CHARGING`.

## The rest of the panel (2026-08-17)

An audit against [omarchy-pods](https://github.com/thisisgm/omarchy-pods) — an
Omarchy plugin that vendors a 130-commit librepods fork to reach the same
features — found four controls we were missing. All four turned out to be
things **this daemon could already do**: `setConversationalAwareness`,
`setOneBudANCMode`, `setAdaptiveNoiseLevel` and `setEarDetectionBehavior` are
upstream methods, bound by upstream's own `Main.qml`, with their AAP packets
sitting in `airpods_packets.h`. Only the control socket had never been told
about them, so anything that was not the Qt GUI was blind to them.

So the patch grew rather than the fork: `ca:on|off`, `onebud:on|off`,
`adaptive:N`, `ear:one|both|off`, the matching fields on the status line, and a
change signal each on `subscribe`. It also now publishes `model` and
`modelNumber` off upstream's model-number map, which is what lets the panel
hide the Pro-only rows instead of drawing dead controls. `model` is `0`
(Unknown) until the metadata packet lands, and **0 is treated as permissive** —
show everything — so the panel degrades to its old behaviour rather than
hiding controls that do work.

Two things worth not re-deriving:

- **A rejected listening mode is completely silent.** The pods ignore every
  mode packet while they are out of the ears, `librepods-ctl` exits 0 anyway,
  the daemon's mode never changes, and so no status line is ever pushed. An
  optimistic highlight with nothing to correct it therefore stayed lit
  forever. `LibrePodsService` now holds a guessed value over incoming reads
  until the daemon agrees and reverts after 4 s if it never does. omarchy-pods
  measured the same rejection independently, and adds that a Pro 3 rejects
  `noise:off` always — it has no Off mode.
- **`adaptive:N` is a no-op outside adaptive mode**, guarded in the daemon, not
  by us. Hence the slider existing only in that mode.

## The control socket left /tmp (2026-08-17)

It used to be `/tmp/app_server`, and that was not a choice anyone made: Qt
resolves a `QLocalServer`/`QLocalSocket` name **without a leading slash**
against the temp dir, so `listen("app_server")` put the channel that drives the
pods somewhere any local user could open it. A name beginning with `/` is taken
as a full filesystem path instead, which makes the fix a path change rather
than a protocol change.

It is now `$XDG_RUNTIME_DIR/librepods.sock` — `/run/user/<uid>`, mode 0700.
Both binaries compute it from one shared header, `linux/ipcpath.hpp`, because
two copies of a path string drift and a drifted socket path fails as "is it
running?", which points nowhere near the cause. `socketPath()` returns empty
when `XDG_RUNTIME_DIR` is unset and **both binaries refuse to fall back** — a
fallback would quietly restore exactly what the move removes, and every context
that matters here (the graphical session, the shell drawing the panel) has a
runtime dir.

Four consumers had to move together: the daemon's `listen`, its single-instance
check and its teardown; `librepods-ctl`; `LibrePodsService.qml`; and
`bin/bluetooth-battery`. The last two carried a matching comment about Qt's
temp-dir rule, both now updated — `bluetooth-battery` used to check the runtime
dir *then* fall back to `/tmp`, and that fallback is deliberately gone.

Verified 2026-08-17: the socket lands at `/run/user/1000/librepods.sock` inside
a 0700 directory, `librepods-ctl` with `XDG_RUNTIME_DIR` unset prints a named
error instead of touching `/tmp`, nothing recreates `/tmp/app_server`, and the
shell's established connection count on the new socket tracks qshell's
lifecycle exactly (1 → 0 → 1 across a stop/start), which is what proves the
panel is really on it and not merely failing quietly.

Verified 2026-08-17 with the pods **disconnected**: `ear:one|both|off`
round-trips through `status` and pushes one `subscribe` line per change (it is
a host-side daemon setting, so it needs no hardware), the panel compiles and
draws every new row, and the empty-battery case no longer leaves a `BATTERY`
heading over nothing. The rest waited for hardware.

## Against the real pods (2026-08-18)

Everything the disconnected pass could not reach, on the A2698: `ca:on|off`,
`onebud:on|off` and `adaptive:25|75|50` all round-trip through `status`, and
the daemon reports `model 5` / `A2698`, so the Pro rows gate off real device
knowledge rather than a guess. The panel draws battery per pod with the in-ear
hint, and the adaptive slider appears only in adaptive mode as intended.

**These pods have no Off mode, and it is not a Pro 3 trait.** From ANC,
Transparency and Adaptive in turn, both pods in ear, four seconds to settle:
`noise:off` was ignored all three times, while every other mode applied in
about 1.5 s. omarchy-pods measured the same refusal and filed it under AirPods
Pro 3; this is a Pro **2**. The pattern that fits both is Adaptive — the
models that gained Adaptive Audio lost Off, and macOS shows them
Transparency/Adaptive/Noise Cancellation with no Off entry. So
`supportsNoiseOff` rides the same `5`/`6` list as `proControls`, and the Off
chip is gone on this hardware. Anything else, Unknown included, keeps Off,
which is what every pre-Adaptive model had.

This is also the first real demonstration of the settle deadline: before it,
clicking Off would have lit the cell and left it lit, because the refusal
produces no packet, no state change, and no pushed line.

Two bugs the live session turned up:

- **Clicking the switch did nothing while clicking the row worked.**
  `PanelSwitch` carries its own `TapHandler`, and `SwitchRow` had added a
  second one to make the whole row a target. Pointer handlers do not consume a
  tap the way a `MouseArea` does, so both fired: the setter ran twice, the
  second call reading the value the first had already flipped optimistically,
  and the control landed exactly where it started. The switch is now an
  indicator and the row owns the gesture. Worth remembering before wrapping
  any other component that has its own handler.
- **The widget could stay missing on a machine where the pods were plainly
  connected** (seen on the NUC). Two causes. The stream gave up after three
  flat 5 s attempts, but `librepods.service` and `qshell` are both on
  `graphical-session.target` and neither wins reliably, so a daemon slower
  than 15 s left the widget absent for the session; the backoff now runs about
  90 s. And the revival hook watched `Bluetooth.devices.values`, the list of
  *known* devices — the pods are paired, so connecting them adds and removes
  nothing and that array never changes identity. The one event the revival
  existed for was the one event it could not see. It now counts connected
  devices, so the binding depends on `device.connected` and fires on connect.

Not verified: a synthesised pointer click. niri does not implement the wlr
virtual-pointer protocol, so `wlrctl` exits 0 and does nothing; `ydotool`
(uinput, via ydotoold) does move the pointer but could not be aimed reliably
enough to trust. The toggle fix is by construction and by the symptom
matching; the confirming click was the user's.
