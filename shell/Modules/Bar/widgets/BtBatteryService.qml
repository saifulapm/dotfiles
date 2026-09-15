import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.UPower

// Apple-accessory battery levels for the Bluetooth widget and panel — ours, in
// the shape of DevServicesService: one instance at the bar root
// however many screens carry the widget (S2), state observed rather than
// polled, and every child wrapped in `setpriv --pdeathsig TERM`.
//
// Why it exists: `BluetoothDevice.battery` comes from `org.bluez.Battery1`,
// which for a headset is published by PipeWire's HFP gateway when the device
// sends Apple's `AT+IPHONEACCEV`. AirPods never send it — the full HFP
// service-level connection completes without a single Apple command (verified
// on this desk with spa.bluez5.native debug logging). They report battery over
// AAP on L2CAP PSM 0x1001 instead, one reading per pod plus the case, which is
// what bin/bluetooth-battery reads.
//
// The event source is the device itself: each reader blocks in recv() and
// prints a JSON line only when a level changes. There is no timer in this
// file. Lifetime rides BlueZ's connect/disconnect events straight from the
// Bluetooth service — a reader exists exactly while its device is connected,
// and destroying the delegate kills the child (Process's destructor kills).
//
// Readers are started for every connected device, not just recognisable Apple
// ones: BlueZ exposes no vendor field through quickshell, and a device without
// an AAP endpoint refuses the channel and the helper exits 3 within a few
// seconds. That is cheaper and more honest than guessing from a name the user
// can rename.
//
// When the librepods daemon runs (librepods.service, [[tool]] librepods) it
// owns the AAP channel, and the helper transparently relays that daemon's
// subscribe stream instead of opening AAP itself — same JSON, same lifetime,
// nothing here changes. See bin/bluetooth-battery's docstring.
//
// THE SECOND SOURCE, added 2026-09-15 for the Magic Keyboard and Magic
// Trackpad. Those two are HID accessories, not audio devices, so no AAP reader
// is started for them and `BluetoothDevice.battery` is empty too — BlueZ
// publishes `org.bluez.Battery1` from the GATT Battery Service (which they do
// not implement) or from an external battery provider (which PipeWire only
// registers for HFP audio), and its own HID provider is build-dependent and
// absent here: `busctl get-property org.bluez /org/bluez/hci0/dev_…
// org.bluez.Battery1 Percentage` answers "No such interface". The level is not
// missing from the machine, only from BlueZ: hid-apple feeds it to the kernel,
// which exposes it as `/sys/class/power_supply/hid-<addr>-battery-*`, and
// UPower already publishes exactly that — `upower -i
// /org/freedesktop/UPower/devices/battery_hid_e0oebo40odeo0do4b_battery_144`
// reads 73% while BlueZ reads nothing.
//
// So UPower is the second source, and it is read the same event-driven way:
// Quickshell's UPower service mirrors DeviceAdded/DeviceRemoved plus the
// PropertiesChanged of every device, so this is a binding, not a timer. The
// MAC inside `nativePath` is what joins the two worlds — the kernel names the
// power supply after the same address BlueZ knows the device by.
//
// AAP wins wherever both exist: it is the richer reading (per pod and case).
// UPower only ever fills a hole, and a hole is what the widget shows today.
QtObject {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.dotfiles/bin/bluetooth-battery"

    // Uppercase address -> { left|right|case|single: { level, charging } }.
    // Replaced wholesale, never mutated, so bindings on it fire.
    property var byAddress: ({})

    // Addresses BlueZ currently reports connected, recomputed on every device
    // change — including the discovery churn while the panel is open.
    readonly property var connectedAddresses: {
        const list = [];
        const devices = Bluetooth.devices ? Bluetooth.devices.values : [];
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i];
            if (device && device.connected && device.address)
                list.push(String(device.address).toUpperCase());
        }
        list.sort();
        return list;
    }

    // An array model rebuilds every delegate when it is reassigned, so the
    // Instantiator reads this latched copy instead: discovery reporting a new
    // neighbour must not tear down and re-handshake a live reader. Same
    // same-contents guard the workspaces model uses (S3).
    property string readerKey: ""
    property var readerAddresses: []

    onConnectedAddressesChanged: {
        const key = root.connectedAddresses.join(",");
        if (key === root.readerKey)
            return;
        root.readerKey = key;
        root.readerAddresses = root.connectedAddresses;
        root.dropDisconnected();
    }

    // A level is only true while its device is connected; a disconnected pod
    // must not leave a figure behind for the next session to believe.
    function dropDisconnected() {
        const next = {};
        let changed = false;
        for (const address in root.byAddress) {
            if (root.connectedAddresses.indexOf(address) !== -1)
                next[address] = root.byAddress[address];
            else
                changed = true;
        }
        if (changed)
            root.byAddress = next;
    }

    // A MAC anywhere in UPower's nativePath, whatever the prefix: this box
    // gets `hid-e0:eb:40:de:0d:4b-battery-144` from hid-apple, but the address
    // is the only part whose shape is guaranteed across drivers, and anchoring
    // on a prefix would silently stop matching the day it changes.
    readonly property var hidAddressPattern: /([0-9a-f]{2}(?::[0-9a-f]{2}){5})/i

    // Same reading shape the AAP path emits, so Model.batteryText renders both
    // through one code path and neither caller learns a second format. Keyed
    // by address like byAddress, and rebuilt wholesale so bindings fire.
    readonly property var hidByAddress: {
        const out = {};
        const devices = UPower.devices ? UPower.devices.values : [];
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i];
            if (!device || !device.isPresent || !device.ready)
                continue;
            const match = root.hidAddressPattern.exec(String(device.nativePath || ""));
            if (!match)
                continue;
            // UPower's Percentage is 0..1 (Services/Battery.qml scales it the
            // same way); level is a whole percent on the AAP side.
            out[match[1].toUpperCase()] = {
                "single": {
                    "level": Math.round((device.percentage || 0) * 100),
                    "charging": device.state === UPowerDeviceState.Charging
                }
            };
        }
        return out;
    }

    // What the widget and the panel ask: the readings for one device, or null.
    // AAP first — see the header for why UPower is only ever the fallback.
    function batteryFor(address) {
        if (!address)
            return null;
        const key = String(address).toUpperCase();
        return root.byAddress[key] || root.hidByAddress[key] || null;
    }

    function applyLine(line) {
        const text = String(line || "").trim();
        if (text === "")
            return;

        let parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!parsed || !parsed.address || !parsed.battery)
            return;

        const next = {};
        for (const address in root.byAddress)
            next[address] = root.byAddress[address];
        next[String(parsed.address).toUpperCase()] = parsed.battery;
        root.byAddress = next;
    }

    readonly property Instantiator readers: Instantiator {
        model: root.readerAddresses

        delegate: QtObject {
            required property string modelData

            readonly property Process reader: Process {
                running: true
                command: ["setpriv", "--pdeathsig", "TERM", "--", root.helper, modelData]
                stdout: SplitParser {
                    onRead: line => root.applyLine(line)
                }
            }
        }
    }
}
