import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Apple-accessory battery levels for the Bluetooth widget and panel — ours, in
// the shape of DevServicesService (CREDITS.md): one instance at the bar root
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

    // What the widget and the panel ask: the readings for one device, or null.
    function batteryFor(address) {
        if (!address)
            return null;
        return root.byAddress[String(address).toUpperCase()] || null;
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
