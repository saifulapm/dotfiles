import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// AirPods state for the bar — the librepods daemon's subscribe stream, in the
// shape of BtBatteryService (one instance at the bar root however many screens
// carry the widget, S2).
//
// The daemon (librepods.service, [[tool]] librepods, running --no-ui) owns
// the AirPods' AAP channel and is the ONLY process that can: everything here
// arrives over its local control socket, which quickshell's own Socket type
// speaks directly — no relay process, no polling. One "subscribe" write and
// the daemon pushes a JSON line per state change (our patch, see
// packages/librepods-status-ipc.patch): battery per pod, ear detection,
// noise mode, connection.
//
// Reconnection is event-driven, not polled: a lost stream retries a few
// times on a short timer (covers the daemon's own Restart=on-failure window
// and the login race with qshell), then parks. Parked is not dead — every
// BlueZ device-list change nudges one reconnect attempt, so the AirPods
// reconnecting (or the daemon being built and started for the first time,
// then the pods touched) revives the stream without a shell reload. On a
// machine that never built librepods the socket never exists: three failed
// connects at startup and the occasional BlueZ nudge, each one cheap.
QtObject {
    id: root

    readonly property string ctl: Quickshell.env("HOME") + "/.local/bin/librepods-ctl"

    // ---------------------------------------------------------------- state
    property string address: ""
    property bool connected: false
    // { left|right|case|single: { level, charging } } — same shape
    // BtBatteryService holds, replaced wholesale so bindings fire.
    property var battery: ({})
    property var ear: ({})
    property int noise: 0

    readonly property var noiseNames: ["Off", "ANC", "Transparency", "Adaptive"]
    readonly property string noiseName: noiseNames[noise] || "Off"

    readonly property bool leftInEar: ear.primaryInEar === true
    readonly property bool rightInEar: ear.secondaryInEar === true

    // ------------------------------------------------------------- control
    // One-shot ctl spawn, not the stream socket: a command and a subscription
    // must not share a connection (the daemon replies down the writer).
    // Optimistic: the cell highlights now, the device's ack arrives on the
    // stream and re-confirms (or corrects) it a beat later.
    function setNoise(mode) {
        const commands = ["noise:off", "noise:anc", "noise:transparency", "noise:adaptive"];
        if (mode < 0 || mode >= commands.length)
            return;
        root.noise = mode;
        Quickshell.execDetached([root.ctl, commands[mode]]);
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
        if (!parsed || typeof parsed.address !== "string")
            return;
        root.address = parsed.address.toUpperCase();
        root.connected = parsed.connected === true;
        root.battery = parsed.battery || {};
        root.ear = parsed.ear || {};
        if (typeof parsed.noise === "number")
            root.noise = parsed.noise;
    }

    // ------------------------------------------------------------ lifetime
    property int attempts: 0

    // Qt's QLocalServer puts relative names in the temp dir (measured
    // /tmp/app_server even with XDG_RUNTIME_DIR set — same note in
    // bin/bluetooth-battery, which checks both paths).
    property Socket stream: Socket {
        path: "/tmp/app_server"
        parser: SplitParser {
            onRead: line => root.applyLine(line)
        }
        onConnectionStateChanged: {
            if (connected) {
                root.attempts = 0;
                write("subscribe");
                flush();
            } else {
                root.connected = false;
                if (++root.attempts <= 3)
                    retry.restart();
            }
        }
        onError: {
            root.connected = false;
            if (++root.attempts <= 3)
                retry.restart();
        }
    }

    // Not `connected: true` on the Socket: declarative property order is
    // unspecified, and a connect that fires before `path` applies is
    // silently ignored — no error signal, no retry, a dead stream (measured
    // 2026-08-11). Kicking it after construction is deterministic.
    Component.onCompleted: stream.connected = true

    property Timer retry: Timer {
        interval: 5000
        onTriggered: root.stream.connected = true
    }

    // The event-driven revival: BlueZ device changes (the AirPods
    // connecting, mostly) grant one fresh attempt after the retries parked.
    readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
    onBtDevicesChanged: {
        if (!root.stream.connected && !retry.running) {
            root.attempts = 0;
            root.stream.connected = true;
        }
    }
}
