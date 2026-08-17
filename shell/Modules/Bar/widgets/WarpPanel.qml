import QtQuick
import "../components"
import "../../../components"
import "WarpModel.js" as Model

// Cloudflare WARP panel — port of tobi/omarchy-warp's Panel.qml in our tokens:
// a hero of the cloud mark over the connection state with the on/off switch on
// its trailing edge, the action/error line, the recovery rows a half-set-up
// client needs, THIS DEVICE, the MODE list, TUNNEL stats while connected, and
// the SPLIT TUNNEL readout.
//
// Their single cursor model comes with it, in the shape this shell already uses
// for Tailscale: the mouse and the keyboard move the same highlight, j/k (and
// the arrows) walk header → recovery → mode → the split-tunnel disclosure →
// the rules it opens, Enter activates whatever is under it, and their letter
// keys are t (toggle), r (refresh), i (register — a rename, see below), m (jump
// to the mode list), s (open the split tunnel) and c (copy the device id). The
// first arrow press only reveals the cursor.
//
// Deviations, all marked in place:
//   * their `i` was "install WARP from the AUR"; the package is declared in
//     packages/manifest.toml here, so `i` means "register this device", which is
//     the first-run step that actually remains;
//   * the split-tunnel list is an accordion in the card rather than a Controls
//     Popup — this shell hand-rolls its controls. A disclosure row that names
//     the mode and says what it does, a chevron that turns, and the collapsing
//     clip the Wi-Fi band pills use, so the card grows into the list;
//   * a tailnet line under the split tunnel, which theirs has no reason to
//     carry: WARP in a tunnel mode owns the default route and so does Tailscale.
//     Cloudflare's own default exclude list carries 100.64.0.0/10, so the line
//     says which of the two situations this machine is in instead of warning
//     unconditionally (Model.tailnetVerdict);
//   * an EGRESS section over Cloudflare's cdn-cgi/trace, after ussego/owarp.
//     Every other line on this card is the daemon describing itself; this is
//     the only one that is Cloudflare answering, and so the only one that can
//     say the tunnel is up and carrying nothing;
//   * the panel counts itself into WarpService.viewers while it is open, which
//     is what puts the service on its full cadence. Closed, the poll is one
//     `status` — the stats and the egress line have no reader.
//
// Switch-locked is read as Cloudflare means it: the org has pinned the client
// ON, so the hero switch refuses to go off and says why. Theirs spends the same
// flag on the mode list, dimming seven rows over a policy that is about the
// switch — see WarpService.disconnect().
BarPanel {
    id: panel

    // WarpService — the bar root's shared instance, injected by the widget that
    // opened this panel.
    required property var warp
    // The bar widget itself, for symmetry with the other panels.
    required property var widget

    panelTitle: ""
    cardWidth: theme.space(95)

    // ------------------------------------------------------------- phrases
    property int phraseIndex: 0
    readonly property var activePhrases: ["Tunnelling packets", "Wrapping routes", "Warping bytes", "Shading traffic", "Folding distance", "Resolving privately", "Sealing the path"]
    readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

    readonly property string heroMeta: {
        if (!warp.installed && warp.probed)
            return "warp-cli is not installed";
        // A tunnel that is up and not carrying the traffic has one thing to
        // say, and it is not a phrase about folding distance.
        if (warp.traceLeaking)
            return "Traffic is not going through WARP";
        if (warp.active)
            return panel.heroPhraseText;
        return warp.statusText;
    }

    readonly property string toggleHint: {
        if (warp.needsRegistration)
            return "Register this device";
        if (warp.lockedOn)
            return "Locked on by your organization";
        return warp.active ? "Disconnect WARP" : "Connect WARP";
    }

    // ------------------------------------------------------- recovery rows
    // Only what is actually outstanding, in the order it has to be done.
    readonly property var recoveryRows: {
        const rows = [];
        if (!warp.installed)
            return rows;
        if (warp.daemonDown)
            rows.push({
                id: "daemon",
                glyph: "󰑐",
                label: "Start the WARP daemon",
                detail: "warp-svc is not answering"
            });
        if (warp.needsTos)
            rows.push({
                id: "tos",
                glyph: "󰄬",
                label: "Accept the terms of service",
                detail: "Required before the client will connect"
            });
        if (warp.needsRegistration && !warp.daemonDown)
            rows.push({
                id: "register",
                glyph: "󰀄",
                label: "Register this device",
                detail: "warp-cli registration new"
            });
        return rows;
    }

    readonly property bool showRecovery: recoveryRows.length > 0
    readonly property var modeRows: warp.modeRows
    readonly property bool showModes: warp.installed && !warp.daemonDown && !warp.needsTos && warp.mode !== ""
    readonly property var stats: warp.tunnelStats && warp.tunnelStats.ok === true ? warp.tunnelStats : null
    readonly property var splitEntries: warp.splitTunnelEntries
    readonly property bool showSplit: warp.installed && warp.splitTunnelSummary !== ""
    // Only ever over a real connection and a real answer: never a stale trace
    // from before a disconnect, and never the optimistic switch.
    readonly property bool showEgress: warp.connected && warp.traceOk

    // -------------------------------------------------------------- cursor
    property string focusSection: "header"
    property int recoveryIndex: 0
    property int modeIndex: 0
    property int splitIndex: 0
    property bool cursorActive: false
    property bool splitExpanded: false

    // Only claim the header cursor when the switch is on screen.
    readonly property bool headerHasCursor: cursorActive && focusSection === "header" && warp.installed
    readonly property bool splitToggleHasCursor: cursorActive && focusSection === "splitToggle"

    // The disclosure row is a stop of its own, so j/k reaches the accordion and
    // Enter opens it — the `s` key is the shortcut, not the only way in.
    readonly property var sectionOrder: {
        const order = ["header"];
        if (panel.showRecovery)
            order.push("recovery");
        if (panel.showModes)
            order.push("mode");
        if (panel.showSplit)
            order.push("splitToggle");
        if (panel.showSplit && panel.splitExpanded && panel.splitEntries.length > 0)
            order.push("split");
        return order;
    }

    function sectionLength(section) {
        switch (section) {
        case "recovery":
            return panel.recoveryRows.length;
        case "mode":
            return panel.modeRows.length;
        case "split":
            return panel.splitEntries.length;
        default:
            return 1;
        }
    }

    function sectionIndex(section) {
        switch (section) {
        case "recovery":
            return panel.recoveryIndex;
        case "mode":
            return panel.modeIndex;
        case "split":
            return panel.splitIndex;
        default:
            return 0;
        }
    }

    function setSectionIndex(section, value) {
        switch (section) {
        case "recovery":
            panel.recoveryIndex = value;
            break;
        case "mode":
            panel.modeIndex = value;
            break;
        case "split":
            panel.splitIndex = value;
            break;
        }
    }

    // One flat walk over whatever is on screen: down off the end of a section
    // steps into the next, so nothing is unreachable and nothing needs Tab.
    function moveCursor(delta) {
        const order = panel.sectionOrder;
        let at = order.indexOf(panel.focusSection);
        if (at < 0)
            at = 0;
        let index = panel.sectionIndex(order[at]) + delta;
        while (true) {
            const length = panel.sectionLength(order[at]);
            if (index >= 0 && index < length) {
                panel.focusSection = order[at];
                panel.setSectionIndex(order[at], index);
                return;
            }
            if (index < 0) {
                if (at === 0)
                    return;
                at -= 1;
                index = panel.sectionLength(order[at]) - 1;
            } else {
                if (at === order.length - 1)
                    return;
                at += 1;
                index = 0;
            }
        }
    }

    function setHeaderCursor() {
        panel.cursorActive = true;
        panel.focusSection = "header";
    }

    function setRecoveryCursor(index) {
        panel.cursorActive = true;
        panel.focusSection = "recovery";
        panel.recoveryIndex = index;
    }

    function setModeCursor(index) {
        panel.cursorActive = true;
        panel.focusSection = "mode";
        panel.modeIndex = index;
    }

    function setSplitCursor(index) {
        panel.cursorActive = true;
        panel.focusSection = "split";
        panel.splitIndex = index;
    }

    function setSplitToggleCursor() {
        panel.cursorActive = true;
        panel.focusSection = "splitToggle";
    }

    // Nothing to open with no rules in the list — the row is then a readout, and
    // clicking a readout should do nothing rather than animate an empty box.
    function toggleSplit() {
        if (panel.splitEntries.length === 0)
            return;
        panel.splitExpanded = !panel.splitExpanded;
        // Collapsing under the cursor would leave it on a row inside a clip
        // nobody can see. Hand it back to the row that closed the list.
        if (!panel.splitExpanded && panel.focusSection === "split")
            panel.setSplitToggleCursor();
    }

    function jumpToModes() {
        if (!panel.showModes)
            return;
        panel.cursorActive = true;
        panel.focusSection = "mode";
        // Land on what is in force, not on the top of the list.
        for (let i = 0; i < panel.modeRows.length; i++) {
            if (panel.modeRows[i].current) {
                panel.modeIndex = i;
                return;
            }
        }
    }

    function runRecovery(row) {
        if (!row)
            return;
        switch (row.id) {
        case "daemon":
            panel.warp.startDaemon();
            break;
        case "register":
            panel.warp.register();
            break;
        case "tos":
            // --accept-tos rides on every invocation, so any command clears it;
            // a status read is the cheapest one.
            panel.warp.refresh();
            break;
        }
    }

    function activateCursor() {
        switch (panel.focusSection) {
        case "header":
            panel.warp.toggleConnection();
            break;
        case "recovery":
            panel.runRecovery(panel.recoveryRows[panel.recoveryIndex]);
            break;
        case "mode":
            const row = panel.modeRows[panel.modeIndex];
            if (row)
                panel.warp.setMode(row.id);
            break;
        case "splitToggle":
            panel.toggleSplit();
            break;
        case "split":
            const entry = panel.splitEntries[panel.splitIndex];
            if (entry)
                panel.warp.copyToClipboard(entry.value);
            break;
        }
    }

    function ensureCursorVisible(item) {
        if (!item || !scroller.interactive)
            return;
        const margin = panel.theme.space(2);
        const maxY = Math.max(0, scroller.contentHeight - scroller.height);
        const top = item.mapToItem(sections, 0, 0).y;
        const bottom = top + item.height;
        if (top < scroller.contentY + margin)
            scroller.contentY = Math.max(0, Math.min(maxY, top - margin));
        else if (bottom > scroller.contentY + scroller.height - margin)
            scroller.contentY = Math.max(0, Math.min(maxY, bottom + margin - scroller.height));
    }

    onPanelOpened: {
        panel.cursorActive = false;
        panel.focusSection = "header";
        panel.warp.refreshDetails();
    }

    // What puts the service on its full cadence, and what takes it off again.
    // Counted rather than set, because a bar per screen carries its own panel.
    onOpenedChanged: panel.warp.viewers += panel.opened ? 1 : -1

    // BarPanel documents that a panel can die open — a config edit replaces its
    // section's id list and the widget is torn down under it. Hand the count
    // back, or the service polls in full forever for a card nobody can see.
    Component.onDestruction: if (panel.opened)
        panel.warp.viewers -= 1

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
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (panel.cursorActive)
                panel.activateCursor();
            else
                panel.warp.toggleConnection();
            break;
        case Qt.Key_T:
            panel.warp.toggleConnection();
            break;
        case Qt.Key_R:
            panel.warp.refreshDetails();
            break;
        case Qt.Key_I:
            // Theirs installed the package; ours registers the device, which is
            // the first-run step that is left once the manifest owns the install.
            panel.warp.register();
            break;
        case Qt.Key_M:
            panel.jumpToModes();
            break;
        case Qt.Key_S:
            panel.toggleSplit();
            break;
        case Qt.Key_C:
            panel.warp.copyToClipboard(panel.warp.deviceId);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // Stopped over a leak: the meta line is then a warning, not a phrase, and
    // the rotator would spend half its cycle fading the warning out.
    PhraseRotator {
        theme: panel.theme
        target: hero.metaItem
        running: panel.opened && panel.warp.active && !panel.warp.traceLeaking
        onAdvance: panel.phraseIndex = (panel.phraseIndex + 1) % panel.activePhrases.length
    }

    // -------------------------------------------------------------- content
    Flickable {
        id: scroller

        width: parent.width
        // Capped like their popup: a long rule list scrolls inside the card
        // instead of stretching it down the whole screen.
        height: Math.min(sections.implicitHeight, panel.theme.space(150), panel.height - panel.theme.barHeight - panel.theme.space(14))
        contentWidth: width
        contentHeight: sections.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: sections

            width: scroller.width
            spacing: panel.theme.space(3)

            // ---------------------------------------------------------- hero
            PanelHero {
                id: hero

                theme: panel.theme
                width: parent.width
                title: panel.warp.deviceName !== "" ? panel.warp.deviceName : "Cloudflare WARP"
                meta: panel.heroMeta
                // Muted for everything the client has to say about itself; the
                // leak is the one line here that is not a status.
                metaColor: panel.warp.traceLeaking ? panel.theme.error : panel.theme.textMuted
                metaFamily: panel.theme.fontUi
                metaWeight: Font.Normal
                metaLetterSpacing: 0
                metaPixelSize: panel.theme.fontPx(0.833)

                icon: WarpIcon {
                    iconSize: panel.theme.fontPx(1.6)
                    color: panel.warp.active ? panel.theme.textPrimary : panel.theme.textMuted
                    opacity: panel.warp.active ? 1.0 : 0.5
                    crossed: !panel.warp.active && !panel.warp.needsRegistration && !panel.warp.daemonDown && !panel.warp.needsTos
                    warning: panel.warp.needsRegistration || panel.warp.daemonDown || panel.warp.needsTos || panel.warp.traceLeaking
                    badgeColor: panel.theme.error
                    badgeBorderColor: panel.theme.surface1
                    badgeTextColor: panel.theme.surface1
                    fontFamily: panel.theme.fontUi
                }

                // Their hero switch, and the header's only cursor target. The
                // service flips `active` optimistically, so the knob throws on
                // the click rather than on the next poll.
                trailing: PanelSwitch {
                    theme: panel.theme
                    anchors.verticalCenter: parent.verticalCenter
                    visible: panel.warp.installed
                    checked: panel.warp.active
                    // Dimmed until the daemon agrees, not just until warp-cli
                    // returns: it returns as soon as the request is taken.
                    busy: panel.warp.busy || panel.warp.settling
                    hasCursor: panel.headerHasCursor
                    hint: panel.toggleHint
                    onHovered: panel.setHeaderCursor()
                    onToggled: panel.warp.toggleConnection()
                }
            }

            // -------------------------------------------------- action/error
            StyledText {
                theme: panel.theme
                role: StyledText.Small

                visible: panel.warp.actionStatus !== "" || panel.warp.lastError !== ""
                width: parent.width
                text: panel.warp.actionStatus !== "" ? panel.warp.actionStatus : panel.warp.lastError
                color: panel.warp.lastError !== "" && panel.warp.actionStatus === "" ? panel.theme.error : panel.theme.textMuted
                wrapMode: Text.WordWrap
            }

            // ------------------------------------------------- not installed
            // Unreachable from the bar (the widget hides itself without a CLI),
            // but kept for the case where the probe answers while the card is
            // already open.
            Rectangle {
                visible: !panel.warp.installed && panel.warp.probed
                width: parent.width
                implicitHeight: visible ? missingText.implicitHeight + panel.theme.space(4) : 0
                radius: panel.theme.radius(0.75)
                color: panel.theme.surface2

                StyledText {
                    id: missingText
                    theme: panel.theme
                    muted: true
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: panel.theme.space(3)
                    anchors.rightMargin: panel.theme.space(3)
                    text: "warp-cli is not installed or not on PATH."
                    wrapMode: Text.WordWrap
                }
            }

            // ------------------------------------------------------ recovery
            Column {
                id: recoveryColumn

                visible: panel.showRecovery
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "SETUP"
                }

                Repeater {
                    model: panel.recoveryRows

                    // Declared here rather than in the component: a Repeater
                    // hands its delegate modelData and index as required
                    // properties, and an inline component only sees them if the
                    // use site asks for them (the shape every Repeater in this
                    // shell uses).
                    RecoveryRow {
                        required property var modelData
                        required property int index

                        width: recoveryColumn.width
                        row: modelData
                        rowIndex: index
                    }
                }
            }

            // --------------------------------------------------- this device
            Column {
                visible: panel.warp.installed && panel.warp.probed
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "THIS DEVICE"
                }

                // The hero already carries the status whenever it is not busy
                // rotating a phrase over a live tunnel, and a card that says
                // "Device is not registered" three times over reads as noise.
                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.statusText !== "" && panel.warp.statusText !== panel.heroMeta
                    label: "Status"
                    value: panel.warp.statusText
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.reasonText !== ""
                    label: "Reason"
                    value: panel.warp.reasonText
                }

                // Only when the MODE list below is not on screen to say it in
                // full — with the list up, this row is the same fact twice.
                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.mode !== "" && !panel.showModes
                    label: "Mode"
                    value: panel.warp.modeLabel(panel.warp.mode)
                }

                // Cloudflare's "Lock WARP switch". It says the client cannot be
                // turned off — nothing about the mode list, which is why it is
                // its own row here rather than a suffix on that one.
                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.switchLocked
                    label: "Switch"
                    value: "Locked on by policy"
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.accountLabel !== ""
                    label: "Account"
                    value: panel.warp.accountLabel
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.deviceId !== ""
                    label: "Device"
                    value: panel.warp.deviceId
                    copyValue: panel.warp.deviceId
                    onCopyRequested: value => panel.warp.copyToClipboard(value)
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.alwaysOn
                    label: "Always on"
                    value: "Enabled"
                }
            }

            // ---------------------------------------------------------- mode
            Column {
                id: modeColumn

                visible: panel.showModes
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "MODE"
                }

                Repeater {
                    model: panel.modeRows

                    ModeRow {
                        required property var modelData
                        required property int index

                        width: modeColumn.width
                        row: modelData
                        rowIndex: index
                    }
                }
            }

            // -------------------------------------------------------- tunnel
            Column {
                visible: panel.stats !== null
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "TUNNEL"
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.stats !== null && panel.stats.endpoint !== ""
                    label: "Endpoint"
                    value: panel.stats !== null ? panel.stats.endpoint : ""
                    copyValue: panel.stats !== null ? panel.stats.endpoint : ""
                    onCopyRequested: value => panel.warp.copyToClipboard(value)
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.stats !== null && panel.stats.protocol !== ""
                    label: "Protocol"
                    value: panel.stats !== null ? panel.stats.protocol : ""
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.stats !== null && panel.stats.latency !== ""
                    label: "Latency"
                    value: panel.stats !== null ? panel.stats.latency : ""
                }

                // Loss is what explains a tunnel that is up and miserable, and
                // the latency beside it will not show it.
                InfoPair {
                    theme: panel.theme
                    visible: panel.stats !== null && panel.stats.loss !== ""
                    label: "Loss"
                    value: panel.stats !== null ? panel.stats.loss : ""
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.stats !== null && (panel.stats.sent !== "" || panel.stats.received !== "")
                    label: "Transfer"
                    value: panel.stats === null ? "" : "↑ " + panel.stats.sent + "   ↓ " + panel.stats.received
                }

                // An age, not a timestamp: a handshake minutes old on a tunnel
                // that claims to be up is the first sign it is not.
                InfoPair {
                    theme: panel.theme
                    visible: panel.stats !== null && panel.stats.handshake !== ""
                    label: "Handshake"
                    value: panel.stats !== null ? panel.stats.handshake : ""
                }
            }

            // -------------------------------------------------------- egress
            // The only section on this card the daemon does not write. Every
            // line here is Cloudflare's answer about the request that just
            // reached it, which is the one thing `warp-cli status` cannot say.
            Column {
                visible: panel.showEgress
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "EGRESS"
                }

                InfoPair {
                    theme: panel.theme
                    label: "Cloudflare sees"
                    value: panel.warp.traceWarpLabel
                    valueColor: panel.warp.traceLeaking ? panel.theme.error : panel.theme.textPrimary
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.traceIp !== ""
                    label: "Public IP"
                    value: panel.warp.traceIp
                    copyValue: panel.warp.traceIp
                    onCopyRequested: value => panel.warp.copyToClipboard(value)
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.traceLocation !== ""
                    label: "Datacenter"
                    value: panel.warp.traceLocation
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.traceGateway
                    label: "Gateway"
                    value: "Filtering this device"
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Small

                    visible: panel.warp.traceLeaking
                    width: parent.width
                    text: "The client says the tunnel is up, and Cloudflare saw this request arrive outside it. Reconnecting usually settles it."
                    color: panel.theme.error
                    wrapMode: Text.WordWrap
                }
            }

            // -------------------------------------------------- split tunnel
            Column {
                id: splitColumn

                visible: panel.showSplit
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "SPLIT TUNNEL"
                }

                // The disclosure row. warp-cli owns the rules, so the list it
                // opens is a readout and the only interaction is looking —
                // which is exactly why the row itself has to carry the whole
                // answer: the mode in the reading weight, what the mode does
                // muted beside it, and a chevron that turns rather than a
                // caret glued to the end of a sentence.
                CursorSurface {
                    id: splitToggle

                    theme: panel.theme
                    width: parent.width
                    implicitHeight: splitToggleInner.implicitHeight + panel.theme.space(3)
                    hasCursor: panel.splitToggleHasCursor || splitToggleMouse.containsMouse
                    // Held lit while the list is down, so an open accordion
                    // reads as one block instead of a row and some strays.
                    current: panel.splitExpanded

                    onHasCursorChanged: if (hasCursor)
                        panel.ensureCursorVisible(splitToggle)

                    MouseArea {
                        id: splitToggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: panel.splitEntries.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: panel.setSplitToggleCursor()
                        onClicked: panel.toggleSplit()
                    }

                    Item {
                        id: splitToggleInner

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: panel.theme.space(2)
                        anchors.rightMargin: panel.theme.space(2)
                        implicitHeight: Math.max(splitChevron.implicitHeight, splitModeLabel.implicitHeight)

                        // One chevron turned a quarter, not two glyphs swapped:
                        // the turn is what says the row did something. Rotated
                        // about its own centre so the arm does not walk sideways
                        // through the label.
                        OpticalGlyph {
                            id: splitChevron

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: panel.splitEntries.length > 0
                            text: "󰅂"
                            color: panel.splitExpanded ? panel.theme.textPrimary : panel.theme.textMuted
                            pixelSize: panel.theme.fontPx(1.0)
                            rotation: panel.splitExpanded ? 90 : 0

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: panel.theme.time(1.2)
                                    easing.type: panel.theme.motion.easing
                                }
                            }
                        }

                        StyledText {
                            id: splitModeLabel
                            theme: panel.theme

                            anchors.left: splitChevron.visible ? splitChevron.right : parent.left
                            anchors.leftMargin: splitChevron.visible ? panel.theme.space(2) : 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.warp.splitTunnelModeLabel
                            font.weight: panel.splitExpanded ? Font.DemiBold : Font.Normal
                        }

                        StyledText {
                            theme: panel.theme
                            role: StyledText.Small
                            muted: true

                            anchors.left: splitModeLabel.right
                            anchors.leftMargin: panel.theme.space(2)
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.warp.splitTunnelMeaning
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }
                }

                // The collapsing container this shell already uses for the
                // Wi-Fi band pills and the tray's inactive drawer: the rows
                // stay built and the clip slides over them, so the card grows
                // into the list instead of the list appearing on top of it.
                // `visible` only drops at a real zero, or a mid-collapse row
                // would keep taking hover.
                Item {
                    id: splitClip

                    width: parent.width
                    clip: true
                    visible: height > 0
                    height: panel.splitExpanded ? splitList.implicitHeight : 0
                    opacity: panel.splitExpanded ? 1 : 0

                    Behavior on height {
                        NumberAnimation {
                            duration: panel.theme.time(1.2)
                            easing.type: panel.theme.motion.easing
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: panel.theme.time(1.2)
                            easing.type: panel.theme.motion.easing
                        }
                    }

                    Column {
                        id: splitList

                        // Top-anchored (the default): the clip grows downward
                        // and hands the rows over from the first, which is the
                        // direction the chevron just pointed. Bottom-anchoring
                        // it — the tray drawer's trick, because that one grows
                        // upward — would run the list past the opening.
                        width: parent.width
                        spacing: panel.theme.space(1.5)

                        Repeater {
                            model: panel.splitEntries

                            SplitRow {
                                required property var modelData
                                required property int index

                                width: splitList.width
                                entry: modelData
                                rowIndex: index
                            }
                        }
                    }
                }

                // Ours: which of the two route situations this machine is in.
                // Last in the section deliberately. Collapsed, the clip above
                // takes no height at all and this sits straight under the
                // disclosure row, where it reads as a note on the mode that row
                // names; open, it lands under the rules it is a note about,
                // instead of wedged between a row and the list it just opened.
                StyledText {
                    theme: panel.theme
                    role: StyledText.Small
                    muted: true

                    visible: panel.warp.tailnetVerdict !== ""
                    width: parent.width
                    text: panel.warp.tailnetVerdict
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ----------------------------------------------------------- components
    component RecoveryRow: CursorSurface {
        id: recoveryRow

        theme: panel.theme

        property var row: null
        property int rowIndex: 0

        hasCursor: panel.cursorActive && panel.focusSection === "recovery" && panel.recoveryIndex === rowIndex
        implicitHeight: recoveryInner.implicitHeight + panel.theme.space(3)

        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(recoveryRow)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: panel.setRecoveryCursor(recoveryRow.rowIndex)
            onClicked: panel.runRecovery(recoveryRow.row)
        }

        Item {
            id: recoveryInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(recoveryGlyph.implicitHeight, recoveryText.implicitHeight)

            OpticalGlyph {
                id: recoveryGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: recoveryRow.row ? String(recoveryRow.row.glyph) : ""
                color: panel.theme.error
                pixelSize: panel.theme.fontPx(1.0)
            }

            Column {
                id: recoveryText
                anchors.left: recoveryGlyph.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                StyledText {
                    theme: panel.theme

                    width: parent.width
                    text: recoveryRow.row ? String(recoveryRow.row.label) : ""
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Small
                    muted: true

                    width: parent.width
                    visible: text !== ""
                    text: recoveryRow.row ? String(recoveryRow.row.detail) : ""
                    elide: Text.ElideRight
                }
            }
        }
    }

    component ModeRow: CursorSurface {
        id: modeRow

        theme: panel.theme

        property var row: null
        property int rowIndex: 0
        readonly property bool isCurrent: row && row.current === true
        readonly property bool pending: row && panel.warp.settingMode === String(row.id || "")

        hasCursor: panel.cursorActive && panel.focusSection === "mode" && panel.modeIndex === rowIndex
        current: isCurrent || pending
        implicitHeight: modeInner.implicitHeight + panel.theme.space(2)

        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(modeRow)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: panel.setModeCursor(modeRow.rowIndex)
            onClicked: if (modeRow.row)
                panel.warp.setMode(modeRow.row.id)
        }

        Item {
            id: modeInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(modeGlyph.implicitHeight, modeText.implicitHeight)

            // Whether a mode tunnels is the whole reason the list is worth
            // showing, so the two get different marks: U+F0582, the same VPN
            // mark TailscalePanel draws on an exit node, against U+F059F, the
            // globe DevServicesPanel and DufsPanel use for a plain web reach.
            // Both are already in this shell's vocabulary — picking codepoints
            // out of the Material range without checking what they depict is
            // how the first draft ended up with seven identical boxes.
            OpticalGlyph {
                id: modeGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: modeRow.row && modeRow.row.tunnel ? "󰖂" : "󰖟"
                color: modeRow.isCurrent || modeRow.pending ? panel.theme.textPrimary : panel.theme.textMuted
                pixelSize: panel.theme.fontPx(1.0)

                NumberAnimation on rotation {
                    running: modeRow.pending
                    from: 0
                    to: 360
                    duration: panel.theme.time(6)
                    loops: Animation.Infinite
                }

                onRotationChanged: if (!modeRow.pending && rotation !== 0)
                    rotation = 0
            }

            // One line, not two. Seven modes stacked two-high turned the card
            // into a column of boxes taller than the screen; the description
            // earns its place but not its own row.
            StyledText {
                id: modeText
                theme: panel.theme
                anchors.left: modeGlyph.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                text: modeRow.row ? String(modeRow.row.label) : ""
                font.weight: modeRow.isCurrent ? Font.DemiBold : Font.Normal
            }

            StyledText {
                theme: panel.theme
                role: StyledText.Small
                muted: true

                anchors.left: modeText.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modeRow.row ? String(modeRow.row.description) : ""
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }
    }

    component SplitRow: CursorSurface {
        id: splitRow

        theme: panel.theme

        property var entry: null
        property int rowIndex: 0

        hasCursor: panel.cursorActive && panel.focusSection === "split" && panel.splitIndex === rowIndex
        implicitHeight: splitInner.implicitHeight + panel.theme.space(2)

        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(splitRow)

        MouseArea {
            id: splitMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: panel.setSplitCursor(splitRow.rowIndex)
            onClicked: if (splitRow.entry)
                panel.warp.copyToClipboard(splitRow.entry.value)
        }

        Item {
            id: splitInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(splitValue.implicitHeight, splitKind.implicitHeight)

            StyledText {
                id: splitValue
                theme: panel.theme
                role: StyledText.Small
                mono: true
                anchors.left: parent.left
                anchors.right: splitKind.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                text: splitRow.entry ? String(splitRow.entry.value) : ""
                elide: Text.ElideRight
            }

            StyledText {
                id: splitKind
                theme: panel.theme
                role: StyledText.Small
                muted: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: splitRow.entry ? String(splitRow.entry.description) : ""
            }
        }

        PanelHint {
            theme: panel.theme
            visible: splitMouse.containsMouse
            anchor: splitRow
            text: "Copy"
        }
    }
}
