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
