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

    // The three Pro controls and the ear-detection policy, all of which the
    // daemon has always been able to drive — they reached the control socket
    // in the same patch that added `status`/`subscribe`.
    property bool conversationalAwareness: false
    property bool oneBudANC: false
    property int adaptiveNoise: 50
    // 0 pause when one is out, 1 pause when both are, 2 never.
    property int earDetectionBehavior: 0
    // Upstream's AirPodsModel enum, off its model-number map.
    property int model: 0
    property string modelNumber: ""

    readonly property var noiseNames: ["Off", "ANC", "Transparency", "Adaptive"]
    readonly property string noiseName: noiseNames[noise] || "Off"

    readonly property var earBehaviorNames: ["Pause when one is out", "Pause when both are out", "Never pause"]
    readonly property string earBehaviorName: earBehaviorNames[earDetectionBehavior] || "Unknown"

    // 5 and 6 are the Pro 2 pair (Lightning, USB-C) — the generation adaptive
    // mode, conversational awareness and one-bud ANC arrived with, and the
    // only one verified here (A2698). 0 is Unknown, the value before the
    // metadata packet lands, and is deliberately permissive: better to offer
    // a control that turns out to do nothing than to hide one that works.
    // Coarse on purpose — refine it per model when there is a device to test.
    readonly property bool proControls: model === 0 || model === 5 || model === 6

    // Off is not a listening mode these pods have. Measured 2026-08-18 on the
    // A2698 in this repo (model 5), both pods in ear, from ANC, Transparency
    // and Adaptive in turn with 4 s to settle: `noise:off` was ignored all
    // three times while every other mode applied in about 1.5 s. ctl exits 0
    // and the daemon counts the attempt, so nothing reports the refusal —
    // which is precisely what the settle deadline above exists to survive.
    //
    // omarchy-pods measured the same refusal but recorded it as an AirPods
    // Pro 3 trait. It is not: this is a Pro 2. The pattern that actually fits
    // both is Adaptive — the models that gained Adaptive Audio lost Off, and
    // macOS shows Transparency/Adaptive/Noise Cancellation for them with no
    // Off entry. So the same 5/6 list drives both, and anything else
    // (including Unknown) keeps Off, which is what every pre-Adaptive model
    // had.
    readonly property bool supportsNoiseOff: model !== 5 && model !== 6

    readonly property bool leftInEar: ear.primaryInEar === true
    readonly property bool rightInEar: ear.secondaryInEar === true

    // ------------------------------------------------------------- control
    // One-shot ctl spawn, not the stream socket: a command and a subscription
    // must not share a connection (the daemon replies down the writer).
    // Optimistic: the cell highlights now, the device's ack arrives on the
    // stream and re-confirms (or corrects) it a beat later.
    //
    // "or corrects" needs a deadline, because a rejected mode is silent. The
    // pods ignore every listening-mode packet while they are out of the ears,
    // and a Pro 3 ignores noise:off always — in both cases ctl exits 0, the
    // daemon's mode never changes, so no status line is ever pushed and
    // nothing would have taken the optimistic highlight back off. Hold the
    // guessed value over incoming reads until the daemon agrees, and give up
    // after settleMs.
    readonly property int settleMs: 4000
    // The last values the daemon actually reported — where a guess that never
    // lands has to fall back to. Mutated in place rather than reassigned:
    // nothing binds to it, only the settle timer reads it.
    property var reported: ({
            noise: 0,
            conversationalAwareness: false,
            oneBudANC: false,
            adaptiveNoise: 50,
            earDetectionBehavior: 0
        })
    // One slot, not one per control: a second command while a guess is still
    // in flight abandons the first, whose value the next push then corrects
    // anyway. Two controls are never mid-flight in a way the user can see.
    property string pendingField: ""
    property var pendingValue: null

    function send(verb, field, value) {
        root[field] = value;
        root.pendingField = field;
        root.pendingValue = value;
        settle.restart();
        Quickshell.execDetached([root.ctl, verb]);
    }

    function clearPending() {
        root.pendingField = "";
        root.pendingValue = null;
        settle.stop();
    }

    // Hold a guess over incoming reads until the daemon agrees with it; every
    // other field on the same line applies immediately.
    function adopt(parsed, key, field) {
        if (parsed[key] === undefined)
            return;
        const value = parsed[key];
        root.reported[field] = value;
        if (root.pendingField !== field)
            root[field] = value;
        else if (value === root.pendingValue)
            root.clearPending();
    }

    function setNoise(mode) {
        const commands = ["noise:off", "noise:anc", "noise:transparency", "noise:adaptive"];
        if (mode < 0 || mode >= commands.length)
            return;
        root.send(commands[mode], "noise", mode);
    }

    function setConversationalAwareness(enabled) {
        root.send(enabled ? "ca:on" : "ca:off", "conversationalAwareness", enabled === true);
    }

    function setOneBudANC(enabled) {
        root.send(enabled ? "onebud:on" : "onebud:off", "oneBudANC", enabled === true);
    }

    // The daemon clamps too, but clamping here keeps the optimistic value and
    // the value sent identical — otherwise a drag past the end would show 105.
    function setAdaptiveNoise(level) {
        const clamped = Math.max(0, Math.min(100, Math.round(level)));
        root.send("adaptive:" + clamped, "adaptiveNoise", clamped);
    }

    function setEarDetectionBehavior(behavior) {
        const verbs = ["ear:one", "ear:both", "ear:off"];
        if (behavior < 0 || behavior >= verbs.length)
            return;
        root.send(verbs[behavior], "earDetectionBehavior", behavior);
    }

    function cycleEarDetection() {
        root.setEarDetectionBehavior((root.earDetectionBehavior + 1) % 3);
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
        // Every line carries the whole state, so an unrelated change (battery,
        // ear) would otherwise stomp a guess still in flight.
        root.adopt(parsed, "noise", "noise");
        root.adopt(parsed, "conversationalAwareness", "conversationalAwareness");
        root.adopt(parsed, "oneBudANC", "oneBudANC");
        root.adopt(parsed, "adaptiveNoise", "adaptiveNoise");
        root.adopt(parsed, "earDetectionBehavior", "earDetectionBehavior");
        // Not optimistic: the device reports these, nothing here sets them.
        if (typeof parsed.model === "number")
            root.model = parsed.model;
        if (typeof parsed.modelNumber === "string")
            root.modelNumber = parsed.modelNumber;
    }

    // ------------------------------------------------------------ lifetime
    property int attempts: 0

    // $XDG_RUNTIME_DIR/librepods.sock — /run/user/<uid>, mode 0700. It used
    // to be /tmp/app_server, because Qt resolves a QLocalServer name without
    // a leading slash under the temp dir, which left the channel that drives
    // the pods open to any local user. The daemon computes the same path in
    // linux/ipcpath.hpp (our patch) and refuses to fall back to /tmp, so an
    // empty runtime dir means no socket rather than an insecure one.
    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/librepods.sock"

    property Socket stream: Socket {
        path: root.socketPath
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
                root.scheduleRetry();
            }
        }
        onError: {
            root.connected = false;
            root.scheduleRetry();
        }
    }

    // 2s, 4s, 8s, 16s, 30s, 30s — about 90 seconds of trying, against the
    // 15 the three flat 5s attempts used to give. That window was the bug:
    // librepods.service and qshell are both on graphical-session.target, so
    // which one wins the race is undefined, and a daemon that took longer
    // than 15s to come up left the stream parked for the rest of the session
    // with the widget simply absent. Backing off rather than lengthening the
    // interval keeps the common case — daemon already up, socket there on the
    // first or second try — as fast as it was.
    readonly property int maxAttempts: 6
    function scheduleRetry() {
        if (++root.attempts > root.maxAttempts)
            return;
        retry.interval = Math.min(30000, 2000 * Math.pow(2, root.attempts - 1));
        retry.restart();
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

    // The deadline on an optimistic value: the device never acked, so put the
    // daemon's own figure back rather than leave a control showing a state the
    // pods are not in.
    property Timer settle: Timer {
        interval: root.settleMs
        onTriggered: {
            if (root.pendingField !== "")
                root[root.pendingField] = root.reported[root.pendingField];
            root.clearPending();
        }
    }

    // The event-driven revival: a BlueZ change grants a fresh set of attempts
    // after the backoff parked.
    //
    // This used to watch `Bluetooth.devices.values` alone, which is the list
    // of KNOWN devices — and the AirPods are paired, so connecting them adds
    // and removes nothing and that array never changes identity. The one
    // event the revival existed for was the one event it could not see, which
    // is why the widget could stay missing on a machine where the pods were
    // plainly connected. Counting the connected ones instead reads
    // `d.connected` per device, so the binding depends on that property and
    // re-runs when any of them connects or drops.
    readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property int btConnectedCount: {
        let count = 0;
        for (const device of root.btDevices)
            if (device && device.connected)
                count++;
        return count;
    }

    function reviveStream() {
        if (root.stream.connected || retry.running)
            return;
        root.attempts = 0;
        root.stream.connected = true;
    }

    onBtDevicesChanged: root.reviveStream()
    onBtConnectedCountChanged: root.reviveStream()
}
