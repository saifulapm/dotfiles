import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "../components"
import "BluetoothModel.js" as Model

// Bluetooth panel — full port of omarchy's bluetooth plugin Panel.qml in our
// tokens: a hero of state glyph, title and rotating phrase with the on/off
// switch on its trailing edge, a CONNECTED list above a scrolling
// PAIRED/AVAILABLE list, per-row connect/disconnect/forget with a pending-
// action map that keeps rows honest while BlueZ catches up, and the audio
// output auto-switch that moves the default PipeWire sink onto a Bluetooth
// audio device the moment it finishes connecting.
//
// Their single cursor model comes with it: mouse and keyboard move one
// highlight, j/k (and the arrows) walk header → connected → paired →
// available across section boundaries, l/h focus and leave the row's forget
// button, Enter activates, Delete (or x) forgets, b toggles the adapter, and
// the first arrow press only reveals the cursor. Devices move between
// sections as they connect and pair, so the cursor follows the focused
// device's BlueZ address across list churn instead of trusting a row index.
//
// Deviations, all marked in place: the cross-monitor half of their discovery
// ownership asks the bar whether any surface still has this panel open,
// rather than passing the debt between sibling widget objects (we have no
// equivalent of their moduleWidgets, and an open panel re-incurs the debt on
// its own), their omarchy-audio-output-set-default persistence helper is not
// ported, and the ListView scrolls bare (this
// shell does not use QtQuick.Controls, so their ScrollBar attachment has no
// counterpart).
BarPanel {
    id: panel

    panelTitle: ""
    cardWidth: theme.space(95)

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"

    // The shared Apple-accessory battery reader, handed over by the widget.
    // Nullable: the panel renders the same without it, minus the per-pod line.
    property BtBatteryService btbattery: null

    // ------------------------------------------------------------- sources
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []

    // Address -> "connecting" | "disconnecting" | "forgetting". The actual
    // Bluetooth sequencing lives in bin/bluetooth-device; this map only keeps
    // the panel responsive while BlueZ catches up.
    property var pendingActions: ({})

    property var pendingAudioOutputDevice: null
    property int pendingAudioOutputAttempts: 0

    readonly property var deviceGroups: Model.deviceLists(panel.devices)
    readonly property var connectedDevices: deviceGroups.connected || []
    readonly property var knownDevices: deviceGroups.known || []
    readonly property var discoveredDevices: deviceGroups.discovered || []

    readonly property string icon: {
        if (!panel.adapter)
            return "";
        if (!panel.adapter.enabled)
            return "󰂲";
        if (panel.connectedDevices.length > 0)
            return "󰂱";
        return "󰂯";
    }

    // ------------------------------------------------------------- phrases
    property int phraseIndex: 0
    readonly property var activePhrases: ["Untangling wires", "Streaming vikings", "Pairing mysteries", "Herding headsets", "Taming radios", "Summoning speakers", "Wrangling codecs", "Polishing packets"]
    readonly property bool rotatingPhrases: panel.adapter !== null && panel.adapter.enabled
    readonly property string heroStatusText: {
        if (!panel.adapter)
            return "No adapter";
        if (!panel.adapter.enabled)
            return "Turned Off";
        return activePhrases[phraseIndex % activePhrases.length];
    }

    // -------------------------------------------------------------- cursor
    // Sections: "header" (virtual, the hero switch — it never appears in
    // visibleSections so the adapter stays togglable by keyboard even when it
    // is off and no device rows exist), then "connected", "known" and
    // "discovered". Visuals come from this model alone, never from
    // containsMouse, so the highlight stays unique across mouse + keyboard.
    property string focusSection: "connected"
    property int selectedIndex: 0
    property bool actionFocused: false
    property bool cursorActive: false

    // Stable identity for the focused device across section churn.
    property string focusedDeviceAddress: ""

    readonly property bool headerHasCursor: cursorActive && focusSection === "header"
    readonly property string toggleHint: panel.adapter && panel.adapter.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"

    function sectionCount(section) {
        if (section === "connected")
            return panel.connectedDevices.length;
        if (section === "known")
            return panel.knownDevices.length;
        if (section === "discovered")
            return panel.discoveredDevices.length;
        return 0;
    }

    function sectionVisible(section) {
        if (section === "connected")
            return panel.connectedDevices.length > 0;
        if (section === "known")
            return panel.knownDevices.length > 0;
        if (section === "discovered")
            return panel.adapter !== null && panel.adapter.discovering && panel.discoveredDevices.length > 0;
        return false;
    }

    readonly property var visibleSections: Model.visibleSections(panel.deviceGroups, panel.adapter !== null && panel.adapter.discovering)

    function devicesForSection(section) {
        return Model.sectionDevices(panel.deviceGroups, section);
    }

    // The scrollable half of the panel — remembered devices, then whatever
    // the scan turned up — flattened into one model so a ListView can own the
    // viewport. Each entry carries the section it came from, which is what
    // lets the delegate and the cursor keep working in section-relative
    // terms.
    readonly property var scrollRows: {
        const rows = [];
        for (let k = 0; k < panel.knownDevices.length; k++)
            rows.push({
                dev: Model.deviceRow(panel.knownDevices[k]),
                section: "known",
                indexInSection: k
            });
        if (panel.sectionVisible("discovered"))
            for (let d = 0; d < panel.discoveredDevices.length; d++)
                rows.push({
                    dev: Model.deviceRow(panel.discoveredDevices[d]),
                    section: "discovered",
                    indexInSection: d
                });
        return rows;
    }

    // Connected devices render above the scroll area; same primitives-only
    // projection so those delegates never hold Device QObject wrappers
    // either. Reading each device's properties here keeps the binding live:
    // any change (battery, state) rebuilds the rows.
    readonly property var connectedRows: {
        const rows = [];
        for (let i = 0; i < panel.connectedDevices.length; i++)
            rows.push(Model.deviceRow(panel.connectedDevices[i]));
        return rows;
    }

    // Live BlueZ device behind a row. Rows carry primitives only, so click
    // actions resolve the backend object here at action time rather than
    // holding a wrapper that can dangle mid-incubation; a vanished device
    // resolves to null and the action no-ops.
    function deviceFor(row) {
        if (!row || !row.dev || !row.dev.address)
            return null;
        const devs = panel.devices;
        for (let i = 0; i < devs.length; i++) {
            if (devs[i] && devs[i].address === row.dev.address)
                return devs[i];
        }
        return null;
    }

    // Flat position of the keyboard cursor, or -1 while it sits on the hero
    // or in the connected list (both live outside the scroll area).
    readonly property int scrollRowIndex: {
        if (panel.focusSection !== "known" && panel.focusSection !== "discovered")
            return -1;
        for (let i = 0; i < panel.scrollRows.length; i++)
            if (panel.scrollRows[i].section === panel.focusSection && panel.scrollRows[i].indexInSection === panel.selectedIndex)
                return i;
        return -1;
    }

    // A row opens a section when it is the first of its kind in the flat
    // list.
    function scrollSectionTitle(index) {
        const rows = panel.scrollRows;
        if (index < 0 || index >= rows.length)
            return "";
        if (index > 0 && rows[index - 1].section === rows[index].section)
            return "";
        return rows[index].section === "known" ? "PAIRED" : "AVAILABLE";
    }

    // -------------------------------------------------- audio auto-switch
    // When a Bluetooth audio device finishes connecting, its sink node
    // surfaces in PipeWire a beat later — schedule the default-sink move and
    // retry on a short timer until the node exists (bounded, so a
    // keyboard-only device stops looking after a few seconds).
    //
    // asahi-audio's DSP chain publishes nodes of its own (effect_output.*,
    // audio_effect.*) — the default sink on this Mac among them. They can
    // never be a Bluetooth device's sink and quickshell logs channel-map
    // complaints for as long as anything tracks the convolver, so they stay
    // out of the candidate list entirely.
    readonly property var candidateSinks: panel.pipewireNodes.filter(n => {
        if (!n || !n.isSink || n.isStream)
            return false;
        const name = String(n.name || "");
        return name.indexOf("effect_output.") !== 0 && name.indexOf("audio_effect.") !== 0 && name.indexOf("omarchy_speaker_tuning") !== 0;
    })

    // Matching reads node.properties (api.bluez5.address), which is inert
    // until a tracker binds the node — held only while a switch is pending.
    PwObjectTracker {
        objects: panel.pendingAudioOutputDevice !== null ? panel.candidateSinks : []
    }

    function bluetoothAudioSink(device) {
        const sinks = panel.candidateSinks;
        for (let i = 0; i < sinks.length; i++) {
            if (Model.bluetoothSinkMatchesDevice(sinks[i], device))
                return sinks[i];
        }
        return null;
    }

    // Their setDefaultAudioSink also shells out to
    // omarchy-audio-output-set-default so their audio service can restore the
    // choice; this shell has no such persistence layer, so the PipeWire
    // preference write is the whole move.
    function setDefaultAudioSink(sink) {
        if (!sink)
            return;
        Pipewire.preferredDefaultAudioSink = sink;
    }

    function scheduleAudioOutputSwitch(device) {
        panel.pendingAudioOutputDevice = {
            address: device && device.address ? device.address : "",
            name: device && device.name ? device.name : "",
            deviceName: device && device.deviceName ? device.deviceName : ""
        };
        panel.pendingAudioOutputAttempts = 0;
        audioSwitchTimer.restart();
    }

    function switchPendingAudioOutput() {
        if (!panel.pendingAudioOutputDevice)
            return;

        const sink = panel.bluetoothAudioSink(panel.pendingAudioOutputDevice);
        if (sink) {
            panel.setDefaultAudioSink(sink);
            panel.pendingAudioOutputDevice = null;
            audioSwitchTimer.stop();
            return;
        }

        panel.pendingAudioOutputAttempts += 1;
        if (panel.pendingAudioOutputAttempts >= 8) {
            panel.pendingAudioOutputDevice = null;
            return;
        }
        audioSwitchTimer.restart();
    }

    // ------------------------------------------------------------- actions
    function deviceAt(section, index) {
        const list = panel.devicesForSection(section);
        return index >= 0 && index < list.length ? list[index] : null;
    }

    function pendingAction(address) {
        return Model.pendingAction(panel.pendingActions, address);
    }

    function setPendingAction(address, action) {
        if (!address)
            return;
        panel.pendingActions = Model.withPendingAction(panel.pendingActions, address, action);
        if (action)
            pendingTimeout.restart();
    }

    function runDeviceAction(device, action, pending) {
        if (!device || !device.address)
            return;
        panel.setPendingAction(device.address, pending);
        Quickshell.execDetached([panel.binDir + "bluetooth-device", action, device.address]);
    }

    function connectDevice(device) {
        if (!device || device.connected)
            return;
        if (device.paired || device.bonded || device.trusted)
            panel.runDeviceAction(device, "connect", "connecting");
        else
            panel.runDeviceAction(device, "pair", "connecting");
    }

    function disconnectDevice(device) {
        if (!device || !device.address)
            return;
        if (!device.connected)
            return;
        panel.setPendingAction(device.address, "disconnecting");
        if (device.disconnect)
            device.disconnect();
        Quickshell.execDetached([panel.binDir + "bluetooth-device", "disconnect", device.address]);
    }

    // For connected devices this first disconnects, then removes the BlueZ
    // pairing record (bin/bluetooth-device sequences both).
    function forgetDevice(device) {
        if (!device || !device.address)
            return;
        panel.runDeviceAction(device, "forget", "forgetting");
    }

    // Reconcile the pending map when reality lands: a "connecting" device
    // that now reports connected is done (and, being freshly connected,
    // schedules the audio output switch), and so on for the other verbs.
    function syncPendingActions() {
        const next = Model.cloneMap(panel.pendingActions);
        let changed = false;

        for (const address in next) {
            const action = next[address];
            let found = null;

            for (let i = 0; i < panel.devices.length; i++) {
                const d = panel.devices[i];
                if (d && d.address === address) {
                    found = d;
                    break;
                }
            }

            const finishedConnecting = action === "connecting" && found && found.connected;
            if (finishedConnecting || (action === "disconnecting" && found && !found.connected) || (action === "forgetting" && (!found || (!found.paired && !found.bonded && !found.trusted)))) {
                if (finishedConnecting)
                    panel.scheduleAudioOutputSwitch(found);
                delete next[address];
                changed = true;
            }
        }

        if (changed)
            panel.pendingActions = next;
    }

    // Not adapter.enabled: that writes BlueZ's Powered, which nothing persists,
    // so the adapter came back on at the next boot. bin/bluetooth-power moves
    // the rfkill soft block instead, which systemd-rfkill restores across
    // reboots. Powered still follows the block, so the switch and icon read it
    // as before.
    //
    // Asking for a direction rather than a toggle: the helper runs detached and
    // the switch only moves once BlueZ catches up, so a second click inside
    // that window would re-read the old state and undo the first.
    function toggleBluetooth() {
        if (!panel.adapter)
            return;
        Quickshell.execDetached([panel.binDir + "bluetooth-power", panel.adapter.enabled ? "off" : "on"]);
    }

    // ----------------------------------------------------- cursor movement
    // j/k navigates the hero toggle ("header") and the device sections
    // row-by-row.
    function moveCursor(delta) {
        const sections = panel.visibleSections;
        if (panel.focusSection === "header") {
            if (delta > 0 && sections && sections.length > 0) {
                panel.focusSection = sections[0];
                panel.selectedIndex = 0;
                panel.actionFocused = false;
            }
            return;
        }
        if (!sections || sections.length === 0) {
            panel.focusSection = "header";
            panel.actionFocused = false;
            return;
        }
        const sIdx = sections.indexOf(panel.focusSection);
        if (sIdx < 0) {
            panel.focusSection = sections[0];
            panel.selectedIndex = 0;
            panel.actionFocused = false;
            return;
        }

        const idx = panel.selectedIndex;
        const max = panel.sectionCount(panel.focusSection) - 1;

        if (delta > 0) {
            if (idx < max) {
                panel.selectedIndex = idx + 1;
                panel.actionFocused = false;
                return;
            }
            if (sIdx < sections.length - 1) {
                panel.focusSection = sections[sIdx + 1];
                panel.selectedIndex = 0;
                panel.actionFocused = false;
            }
        } else {
            if (idx > 0) {
                panel.selectedIndex = idx - 1;
                panel.actionFocused = false;
                return;
            }
            if (sIdx > 0) {
                panel.focusSection = sections[sIdx - 1];
                panel.selectedIndex = panel.sectionCount(panel.focusSection) - 1;
                panel.actionFocused = false;
            } else {
                panel.focusSection = "header";
                panel.actionFocused = false;
            }
        }
    }

    function setHeaderCursor() {
        panel.cursorActive = true;
        panel.focusSection = "header";
        panel.actionFocused = false;
    }

    // l walks onto the row's forget button, h walks back off it.
    function moveCursorH(delta) {
        if (panel.focusSection !== "known" && panel.focusSection !== "connected")
            return;
        const dev = panel.deviceAt(panel.focusSection, panel.selectedIndex);
        if (!dev || !dev.address)
            return;
        if (delta > 0)
            panel.actionFocused = true;
        else if (delta < 0)
            panel.actionFocused = false;
    }

    function activateCursor() {
        if (panel.focusSection === "header") {
            panel.toggleBluetooth();
            return;
        }
        if (panel.actionFocused) {
            panel.deleteSelected();
            return;
        }

        if (panel.focusSection === "connected" || panel.focusSection === "known") {
            const dev = panel.deviceAt(panel.focusSection, panel.selectedIndex);
            if (!dev)
                return;
            if (dev.connected)
                panel.disconnectDevice(dev);
            else
                panel.connectDevice(dev);
            return;
        }
        if (panel.focusSection === "discovered") {
            const d = panel.discoveredDevices[panel.selectedIndex];
            if (!d)
                return;
            panel.connectDevice(d);
        }
    }

    // Delete (or x) forgets remembered devices; discovered ones have no
    // pairing record to remove.
    function deleteSelected() {
        if (panel.focusSection !== "known" && panel.focusSection !== "connected")
            return;
        const dev = panel.deviceAt(panel.focusSection, panel.selectedIndex);
        if (!dev)
            return;
        panel.forgetDevice(dev);
    }

    function updateFocusedAddress() {
        const d = panel.deviceAt(panel.focusSection, panel.selectedIndex);
        panel.focusedDeviceAddress = d ? (d.address || "") : "";
    }

    function reselectFocusedDevice() {
        if (panel.focusedDeviceAddress === "") {
            panel.clampCursor();
            return;
        }

        const sections = ["connected", "known", "discovered"];
        for (let s = 0; s < sections.length; s++) {
            const section = sections[s];
            if (!panel.sectionVisible(section))
                continue;
            const list = panel.devicesForSection(section);
            for (let i = 0; i < list.length; i++) {
                if (list[i] && list[i].address === panel.focusedDeviceAddress) {
                    panel.focusSection = section;
                    panel.selectedIndex = i;
                    panel.clampCursor();
                    return;
                }
            }
        }

        panel.clampCursor();
    }

    function clampCursor() {
        const sections = panel.visibleSections;
        // "header" is virtual and never appears in visibleSections, so it has
        // to be let through: toggling the adapter empties and refills the
        // device lists, and clamping would knock the cursor off the hero
        // switch every time it is used.
        if (panel.focusSection === "header")
            return;
        if (!sections || !sections.length) {
            panel.selectedIndex = 0;
            return;
        }
        if (sections.indexOf(panel.focusSection) < 0) {
            panel.focusSection = sections[0];
            panel.selectedIndex = 0;
            return;
        }
        const count = panel.sectionCount(panel.focusSection);
        if (count === 0) {
            // Section emptied out — bounce to the previous visible one.
            const sIdx = sections.indexOf(panel.focusSection);
            panel.focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0];
            panel.selectedIndex = Math.max(0, panel.sectionCount(panel.focusSection) - 1);
            return;
        }
        if (panel.selectedIndex > count - 1)
            panel.selectedIndex = count - 1;
        if (panel.selectedIndex < 0)
            panel.selectedIndex = 0;
    }

    onSelectedIndexChanged: panel.updateFocusedAddress()
    onFocusSectionChanged: panel.updateFocusedAddress()
    onConnectedDevicesChanged: {
        panel.reselectFocusedDevice();
        panel.syncPendingActions();
    }
    onKnownDevicesChanged: {
        panel.reselectFocusedDevice();
        panel.syncPendingActions();
    }
    onDiscoveredDevicesChanged: {
        panel.reselectFocusedDevice();
        panel.syncPendingActions();
    }
    onVisibleSectionsChanged: panel.clampCursor()

    // ----------------------------------------------------------- lifecycle
    onPanelOpened: {
        // Adopt a scan that is already running — one leaked by a copy that
        // could not finish its own stop, or handed over from another monitor
        // — so this panel's close settles it either way.
        if (panel.adapter !== null && panel.adapter.discovering)
            panel.owesDiscoveryStop = true;
        if (panel.connectedDevices.length > 0) {
            panel.focusSection = "connected";
            panel.selectedIndex = 0;
        } else if (panel.knownDevices.length > 0) {
            panel.focusSection = "known";
            panel.selectedIndex = 0;
        } else if (panel.discoveredDevices.length > 0) {
            panel.focusSection = "discovered";
            panel.selectedIndex = 0;
        } else {
            panel.focusSection = "header";
        }
        panel.actionFocused = false;
        panel.cursorActive = false;
    }

    // ------------------------------------------------- discovery ownership
    //
    // Discovery stops when the panel closes — but a bare write at close time
    // does not do it (omarchy 457aec6). Quickshell only forwards a
    // `discovering` write that DIFFERS from the last state BlueZ reported, so
    // a stop issued while a just-fired StartDiscovery is still awaiting
    // confirmation is swallowed: the property is already false locally, the
    // write is a no-op, and the session — held by quickshell's D-Bus
    // connection, not by this object — outlives the panel entirely. Closing
    // the panel inside the first second left the radio in inquiry until the
    // next shell restart, continuously starving A2DP audio on the same
    // controller into stutters.
    //
    // So: track the StopDiscovery this panel owes BlueZ, and settle it from a
    // timer bound to the CONFIRMED state. A confirmation landing at any point
    // after close re-arms the stop, and a reopen inside the first interval
    // keeps the scan running uninterrupted.
    //
    // Ownership, not state: BlueZ's Discovering also reflects sessions other
    // clients hold, which are never this panel's to stop.
    property bool owesDiscoveryStop: false

    // The bar survives anchorItem going away, which is exactly when this is
    // asked (a panel being torn down still owing a stop).
    function anotherPanelOpen() {
        const bar = (panel.anchorItem && panel.anchorItem.bar) ? panel.anchorItem.bar : panel.grantingBar;
        if (!bar || typeof bar.anyWidgetPanelOpen !== "function")
            return false;
        // This copy is closed or dying by the time this is called, so any
        // "open" answer is necessarily another surface's.
        return bar.anyWidgetPanelOpen("bluetooth");
    }

    Timer {
        id: discoveryStop
        interval: 1000
        repeat: true
        property int attempts: 0
        running: !panel.opened && panel.owesDiscoveryStop && panel.adapter !== null && panel.adapter.discovering === true
        onRunningChanged: if (running)
            attempts = 0
        onTriggered: {
            // The scan now serves a panel still on screen elsewhere — its own
            // open-time adoption may have seen nothing to adopt, so hand the
            // debt over by dropping it here and letting that panel's retry
            // timer re-incur it.
            if (panel.anotherPanelOpen()) {
                panel.owesDiscoveryStop = false;
                return;
            }
            attempts += 1;
            // Bounded, so a session another BlueZ client holds up cannot draw
            // StopDiscovery calls forever.
            if (attempts > 3) {
                panel.owesDiscoveryStop = false;
                return;
            }
            panel.adapter.discovering = false;
        }
    }

    // The debt is settled the moment BlueZ reports discovery down — whether
    // the stop above landed or the session ended some other way — so a stale
    // claim never touches a scan another client starts later. While the panel
    // is open, discoveryRetry re-incurs it as it restarts the scan.
    Connections {
        target: panel.adapter
        function onDiscoveringChanged() {
            if (panel.adapter && !panel.adapter.discovering)
                panel.owesDiscoveryStop = false;
        }
    }

    // A panel torn down while open (bar reconfig, widget leaving the layout)
    // never emits panelClosed, so the timer above never gets its chance.
    // Nothing here can wait for a BlueZ confirmation, so this is the one place
    // the write still goes out directly — and only when no other panel is
    // holding the scan up.
    Component.onDestruction: {
        if (!panel.owesDiscoveryStop || panel.anotherPanelOpen())
            return;
        if (panel.adapter && panel.adapter.discovering)
            panel.adapter.discovering = false;
    }

    // BlueZ rejects StartDiscovery while the adapter is still powering up,
    // and discovery can also time out on its own. While the panel is open,
    // keep nudging it back on so an enabled adapter is always scanning.
    // Gated on state rather than enabled — enabled flips on the property
    // write, but state tracks BlueZ's own PowerState, so the nudge waits out
    // the power-up instead of drawing a "Resource Not Ready" refusal first
    // (their timer eats that refusal and retries; same behaviour, clean log).
    Timer {
        id: discoveryRetry
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: panel.opened && panel.adapter !== null && panel.adapter.state === BluetoothAdapterState.Enabled && !panel.adapter.discovering
        onTriggered: {
            panel.owesDiscoveryStop = true;
            panel.adapter.discovering = true;
        }
    }

    Timer {
        id: pendingTimeout
        interval: 20000
        repeat: false
        onTriggered: panel.pendingActions = ({})
    }

    Timer {
        id: audioSwitchTimer
        interval: 500
        repeat: false
        onTriggered: panel.switchPendingAudioOutput()
    }

    PhraseRotator {
        theme: panel.theme
        target: hero.metaItem
        running: panel.opened && panel.rotatingPhrases
        onAdvance: panel.phraseIndex = (panel.phraseIndex + 1) % panel.activePhrases.length
    }

    // ------------------------------------------------------------ keyboard
    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            if (panel.cursorActive)
                panel.moveCursor(1);
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            if (panel.cursorActive)
                panel.moveCursor(-1);
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            if (panel.cursorActive)
                panel.moveCursorH(1);
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            if (panel.cursorActive)
                panel.moveCursorH(-1);
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (panel.cursorActive)
                panel.activateCursor();
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Delete:
        case Qt.Key_X:
            if (panel.cursorActive)
                panel.deleteSelected();
            break;
        case Qt.Key_B:
            panel.toggleBluetooth();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------- content
    Column {
        id: sections

        width: parent.width
        spacing: panel.theme.space(3)

        // ---------------------------------------------------------- hero
        PanelHero {
            id: hero

            theme: panel.theme
            width: parent.width
            title: "Bluetooth"
            meta: panel.heroStatusText.toUpperCase()

            icon: OpticalGlyph {
                text: panel.icon
                color: panel.theme.textPrimary
                opacity: panel.adapter && panel.adapter.enabled ? 1.0 : 0.5
                pixelSize: panel.theme.fontPx(1.6)
            }

            // Their compact on/off switch on the trailing edge of the hero,
            // and the header's only cursor target — status text alone; the
            // switch owns toggling, mouse and keyboard alike.
            trailing: PanelSwitch {
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.adapter !== null
                checked: panel.adapter !== null && panel.adapter.enabled
                hasCursor: panel.headerHasCursor
                hint: panel.toggleHint
                onHovered: panel.setHeaderCursor()
                onToggled: panel.toggleBluetooth()
            }
        }

        Separator {
            theme: panel.theme
        }

        // ------------------------------------------------------ connected
        // Fixed above the scroll area, as theirs is: what is connected stays
        // in view however noisy the neighborhood below gets.
        Column {
            id: connectedList

            visible: panel.connectedDevices.length > 0
            width: parent.width
            spacing: panel.theme.space(1.5)

            SectionHeader {
                theme: panel.theme
                width: parent.width
                label: "CONNECTED"
            }

            Repeater {
                model: panel.connectedRows

                DeviceRow {
                    required property var modelData
                    required property int index

                    width: connectedList.width
                    dev: modelData
                    rowIndex: index
                    sectionName: "connected"
                    isDiscovered: false
                }
            }
        }

        Separator {
            theme: panel.theme
            visible: panel.connectedDevices.length > 0 && panel.scrollRows.length > 0
        }

        // A ListView, not a Flickable: it owns the scroll position, so it
        // keeps the current row visible on j/k, re-clamps itself when
        // discovery shortens the list, and — because Contain only moves when
        // a row is actually clipped — never lurches under a hovering mouse.
        ListView {
            id: deviceListView

            width: parent.width
            height: Math.min(contentHeight, panel.theme.space(100))
            spacing: panel.theme.space(1.5)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            model: panel.scrollRows
            currentIndex: panel.scrollRowIndex
            // Deferred by a turn: scrollRows is rebuilt every time discovery
            // reports, and swapping the model resets the view out from under
            // a call made straight from the signal.
            onCurrentIndexChanged: if (currentIndex >= 0)
                Qt.callLater(keepCurrentVisible)
            function keepCurrentVisible() {
                if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain);
            }

            delegate: Item {
                required property var modelData
                required property int index
                readonly property string sectionTitle: panel.scrollSectionTitle(index)

                width: ListView.view.width
                height: delegateColumn.implicitHeight

                Column {
                    id: delegateColumn
                    width: parent.width
                    spacing: panel.theme.space(1.5)

                    Separator {
                        theme: panel.theme
                        visible: index > 0 && sectionTitle !== ""
                        height: visible ? 1 : 0
                    }

                    SectionHeader {
                        theme: panel.theme
                        visible: sectionTitle !== ""
                        height: visible ? implicitHeight : 0
                        width: parent.width
                        label: sectionTitle
                    }

                    DeviceRow {
                        width: parent.width
                        dev: modelData.dev
                        rowIndex: modelData.indexInSection
                        sectionName: modelData.section
                        isDiscovered: modelData.section === "discovered"
                    }
                }
            }
        }

        // ---------------------------------------------------- empty state
        Text {
            visible: panel.connectedDevices.length === 0 && panel.scrollRows.length === 0
            width: parent.width
            text: !panel.adapter ? "No Bluetooth adapter" : !panel.adapter.enabled ? "Turn Bluetooth on to scan" : "Scanning for devices…"
            color: panel.theme.textMuted
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.917)
            wrapMode: Text.WordWrap
        }
    }

    // ----------------------------------------------------------- components
    // Two-line device row showing name + live status. Pending state is owned
    // by the panel so it survives rows moving between sections.
    component DeviceRow: CursorSurface {
        id: row

        theme: panel.theme

        required property var dev
        required property int rowIndex
        required property string sectionName
        required property bool isDiscovered

        readonly property bool isConnected: !!(dev && dev.connected)
        readonly property int devState: dev && dev.state !== undefined ? dev.state : -1
        readonly property string action: panel.pendingAction(dev ? dev.address : "")
        readonly property string actionTooltip: {
            if (!dev)
                return "";
            if (isConnected)
                return "Disconnect";
            if (isDiscovered)
                return "Pair";
            return "Connect";
        }

        readonly property bool rowSelected: panel.cursorActive && panel.focusSection === sectionName && panel.selectedIndex === rowIndex
        readonly property bool forgetAvailable: (sectionName === "known" || sectionName === "connected") && !isDiscovered
        readonly property bool showForgetButton: forgetAvailable && (rowMouse.containsMouse || rowSelected)

        // Per-pod levels read over AAP, live while the device is connected.
        // Reading btbattery.byAddress through the service's accessor keeps this
        // binding subscribed, so a level change repaints the row.
        readonly property var aapBattery: panel.btbattery && dev && dev.address ? panel.btbattery.batteryFor(dev.address) : null

        readonly property string statusText: {
            if (!dev)
                return "";
            if (action === "forgetting")
                return "Forgetting…";
            if (action === "disconnecting" || devState === BluetoothDeviceState.Disconnecting)
                return "Disconnecting…";
            if (isConnected) {
                // AAP first: it carries a figure per pod plus the case, where
                // BlueZ's Battery1 would carry one number at best — and for
                // AirPods carries nothing at all.
                const aapText = Model.batteryText(aapBattery);
                if (aapText !== "")
                    return aapText;
                if (dev.batteryAvailable)
                    return Math.round(dev.battery * 100) + "%";
                return sectionName === "connected" ? "" : "Connected";
            }
            if (action === "connecting" || devState === BluetoothDeviceState.Connecting || dev.pairing === true)
                return "Connecting…";
            return "";
        }

        readonly property color statusColor: {
            if (isConnected)
                return panel.theme.textPrimary;
            if (action !== "" || devState === BluetoothDeviceState.Connecting || (dev && dev.pairing === true))
                return panel.theme.textPrimary;
            return panel.theme.textMuted;
        }

        hasCursor: rowSelected && !panel.actionFocused
        current: isConnected
        implicitHeight: rowContent.implicitHeight + panel.theme.space(3)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: row.dev ? Qt.PointingHandCursor : Qt.ArrowCursor

            onContainsMouseChanged: if (containsMouse) {
                panel.cursorActive = true;
                panel.focusSection = row.sectionName;
                panel.selectedIndex = row.rowIndex;
                panel.actionFocused = false;
            }

            onClicked: mouse => {
                const dev = panel.deviceFor(row);
                if (!dev)
                    return;
                if (mouse.button === Qt.RightButton) {
                    if (row.isConnected)
                        panel.disconnectDevice(dev);
                    else if (!row.isDiscovered)
                        panel.forgetDevice(dev);
                    return;
                }
                if (row.isConnected)
                    panel.disconnectDevice(dev);
                else
                    panel.connectDevice(dev);
            }
        }

        PanelHint {
            theme: panel.theme
            visible: row.actionTooltip !== "" && rowMouse.containsMouse && !panel.actionFocused
            anchor: row
            text: row.actionTooltip
        }

        Item {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: Math.max(deviceIcon.implicitHeight, info.implicitHeight, forgetBtn.implicitHeight)

            OpticalGlyph {
                id: deviceIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: row.isConnected ? "󰂱" : "󰂯"
                color: row.statusColor
                pixelSize: panel.theme.fontPx(1.083)
            }

            Column {
                id: info

                anchors.left: deviceIcon.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: forgetBtn.visible ? forgetBtn.left : parent.right
                anchors.rightMargin: forgetBtn.visible ? panel.theme.space(2) : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                Text {
                    width: parent.width
                    text: Model.deviceLabel(row.dev) || "Device"
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    elide: Text.ElideRight
                }

                Text {
                    visible: row.statusText !== ""
                    width: parent.width
                    text: row.statusText
                    color: row.statusColor
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                    elide: Text.ElideRight
                }
            }

            ForgetButton {
                id: forgetBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: row.showForgetButton
                hasCursor: row.rowSelected && panel.actionFocused
                onHovered: on => {
                    if (!on) {
                        if (rowMouse.containsMouse)
                            panel.actionFocused = false;
                        return;
                    }
                    panel.cursorActive = true;
                    panel.focusSection = row.sectionName;
                    panel.selectedIndex = row.rowIndex;
                    panel.actionFocused = true;
                }
                onActivated: {
                    const dev = panel.deviceFor(row);
                    if (dev)
                        panel.forgetDevice(dev);
                }
            }
        }
    }

    // Their PanelActionButton: a bordered square holding one glyph, cursor-
    // aware so l/Enter reaches it from the keyboard.
    component ForgetButton: Rectangle {
        id: forgetButton

        property bool hasCursor: false

        signal hovered(bool on)
        signal activated

        implicitWidth: panel.theme.space(8)
        implicitHeight: panel.theme.space(7)
        radius: panel.theme.radius(0.75)
        color: forgetMouse.containsMouse ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2
        border.width: panel.theme.borderWidth
        border.color: forgetButton.hasCursor ? panel.theme.alpha(panel.theme.accent, 0.6) : panel.theme.surface3

        OpticalGlyph {
            anchors.centerIn: parent
            text: "󰅙"
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(1.0)
        }

        // A MouseArea rather than a TapHandler: the row underneath has its
        // own full-fill MouseArea, and a TapHandler's passive grab lets the
        // press fall through — one click on 󰅙 would forget AND connect.
        // The MouseArea takes the exclusive grab and swallows the click, as
        // upstream's PanelActionButton and our NetworkPanel's forgetMouse do.
        MouseArea {
            id: forgetMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: forgetButton.hovered(containsMouse)
            onClicked: forgetButton.activated()
        }

        PanelHint {
            theme: panel.theme
            visible: forgetMouse.containsMouse
            anchor: forgetButton
            text: "Forget"
        }
    }
}
