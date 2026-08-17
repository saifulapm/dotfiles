import QtQuick
import "../components"
import "WarpModel.js" as Model

// Cloudflare WARP panel — port of tobi/omarchy-warp's Panel.qml in our tokens:
// a hero of the cloud mark over the connection state with the on/off switch on
// its trailing edge, the action/error line, the recovery rows a half-set-up
// client needs, THIS DEVICE, the MODE list, TUNNEL stats while connected, and
// the SPLIT TUNNEL readout.
//
// Their single cursor model comes with it, in the shape this shell already uses
// for Tailscale: the mouse and the keyboard move the same highlight, j/k (and
// the arrows) walk header → recovery → mode → split, Enter activates whatever is
// under it, and their letter keys are t (toggle), r (refresh), i (register — a
// rename, see below), m (jump to the mode list), s (expand the split tunnel) and
// c (copy the device id). The first arrow press only reveals the cursor.
//
// Deviations, all marked in place:
//   * their `i` was "install WARP from the AUR"; the package is declared in
//     packages/manifest.toml here, so `i` means "register this device", which is
//     the first-run step that actually remains;
//   * the split-tunnel list is an inline expansion rather than a Controls
//     Popup — this shell hand-rolls its controls;
//   * a tailnet line under the split tunnel, which theirs has no reason to
//     carry: WARP in a tunnel mode owns the default route and so does Tailscale.
//     Cloudflare's own default exclude list carries 100.64.0.0/10, so the line
//     says which of the two situations this machine is in instead of warning
//     unconditionally (Model.tailnetVerdict).
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
        if (warp.active)
            return panel.heroPhraseText;
        return warp.statusText;
    }

    readonly property string toggleHint: {
        if (warp.needsRegistration)
            return "Register this device";
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

    // -------------------------------------------------------------- cursor
    property string focusSection: "header"
    property int recoveryIndex: 0
    property int modeIndex: 0
    property int splitIndex: 0
    property bool cursorActive: false
    property bool splitExpanded: false

    // Only claim the header cursor when the switch is on screen.
    readonly property bool headerHasCursor: cursorActive && focusSection === "header" && warp.installed

    readonly property var sectionOrder: {
        const order = ["header"];
        if (panel.showRecovery)
            order.push("recovery");
        if (panel.showModes)
            order.push("mode");
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
            panel.splitExpanded = !panel.splitExpanded;
            break;
        case Qt.Key_C:
            panel.warp.copyToClipboard(panel.warp.deviceId);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    PhraseRotator {
        theme: panel.theme
        target: hero.metaItem
        running: panel.opened && panel.warp.active
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
                metaFamily: panel.theme.fontUi
                metaWeight: Font.Normal
                metaLetterSpacing: 0
                metaPixelSize: panel.theme.fontPx(0.833)

                icon: WarpIcon {
                    iconSize: panel.theme.fontPx(1.6)
                    color: panel.warp.active ? panel.theme.textPrimary : panel.theme.textMuted
                    opacity: panel.warp.active ? 1.0 : 0.5
                    crossed: !panel.warp.active && !panel.warp.needsRegistration && !panel.warp.daemonDown && !panel.warp.needsTos
                    warning: panel.warp.needsRegistration || panel.warp.daemonDown || panel.warp.needsTos
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
                    busy: panel.warp.busy
                    hasCursor: panel.headerHasCursor
                    hint: panel.toggleHint
                    onHovered: panel.setHeaderCursor()
                    onToggled: panel.warp.toggleConnection()
                }
            }

            // -------------------------------------------------- action/error
            Text {
                visible: panel.warp.actionStatus !== "" || panel.warp.lastError !== ""
                width: parent.width
                text: panel.warp.actionStatus !== "" ? panel.warp.actionStatus : panel.warp.lastError
                color: panel.warp.lastError !== "" && panel.warp.actionStatus === "" ? panel.theme.error : panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.833)
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

                Text {
                    id: missingText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: panel.theme.space(3)
                    anchors.rightMargin: panel.theme.space(3)
                    text: "warp-cli is not installed or not on PATH."
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
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

                InfoPair {
                    theme: panel.theme
                    label: "Status"
                    value: panel.warp.statusText === "" ? "Unknown" : panel.warp.statusText
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.reasonText !== ""
                    label: "Reason"
                    value: panel.warp.reasonText
                }

                InfoPair {
                    theme: panel.theme
                    visible: panel.warp.mode !== ""
                    label: "Mode"
                    value: panel.warp.modeLabel(panel.warp.mode) + (panel.warp.switchLocked ? " · locked" : "")
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
                    label: panel.warp.switchLocked ? "MODE · LOCKED" : "MODE"
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

                InfoPair {
                    theme: panel.theme
                    visible: panel.stats !== null && (panel.stats.sent !== "" || panel.stats.received !== "")
                    label: "Transfer"
                    value: panel.stats === null ? "" : "↑ " + panel.stats.sent + "   ↓ " + panel.stats.received
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

                // The summary doubles as the expander: warp-cli owns the rules,
                // so this is a readout and the only interaction is looking.
                CursorSurface {
                    id: splitToggle

                    theme: panel.theme
                    width: parent.width
                    implicitHeight: splitToggleLabel.implicitHeight + panel.theme.space(3)
                    hasCursor: splitToggleMouse.containsMouse
                    current: panel.splitExpanded

                    MouseArea {
                        id: splitToggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.splitExpanded = !panel.splitExpanded
                    }

                    Text {
                        id: splitToggleLabel
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: panel.theme.space(2)
                        anchors.rightMargin: panel.theme.space(2)
                        text: panel.warp.splitTunnelSummary + (panel.splitEntries.length > 0 ? (panel.splitExpanded ? "  ▴" : "  ▾") : "")
                        color: panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.917)
                        elide: Text.ElideRight
                    }
                }

                // Ours: which of the two route situations this machine is in.
                Text {
                    visible: panel.warp.tailnetVerdict !== ""
                    width: parent.width
                    text: panel.warp.tailnetVerdict
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.833)
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: panel.splitExpanded ? panel.splitEntries : []

                    SplitRow {
                        required property var modelData
                        required property int index

                        width: splitColumn.width
                        entry: modelData
                        rowIndex: index
                    }
                }
            }

            // ---------------------------------------------------------- hints
            PanelHint {
                theme: panel.theme
                visible: false
                anchor: sections
                text: ""
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

                Text {
                    width: parent.width
                    text: recoveryRow.row ? String(recoveryRow.row.label) : ""
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: recoveryRow.row ? String(recoveryRow.row.detail) : ""
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.792)
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
        opacity: panel.warp.switchLocked && !isCurrent ? 0.45 : 1.0
        implicitHeight: modeInner.implicitHeight + panel.theme.space(2)

        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(modeRow)

        MouseArea {
            id: modeMouse
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
            Text {
                id: modeText
                anchors.left: modeGlyph.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                text: modeRow.row ? String(modeRow.row.label) : ""
                color: panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
                font.weight: modeRow.isCurrent ? Font.DemiBold : Font.Normal
            }

            Text {
                anchors.left: modeText.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modeRow.row ? String(modeRow.row.description) : ""
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.792)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        PanelHint {
            theme: panel.theme
            visible: modeMouse.containsMouse && panel.warp.switchLocked && !modeRow.isCurrent
            anchor: modeRow
            text: "Locked by your organization"
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

            Text {
                id: splitValue
                anchors.left: parent.left
                anchors.right: splitKind.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                text: splitRow.entry ? String(splitRow.entry.value) : ""
                color: panel.theme.textPrimary
                font.family: panel.theme.fontMono
                font.pixelSize: panel.theme.fontPx(0.833)
                elide: Text.ElideRight
            }

            Text {
                id: splitKind
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: splitRow.entry ? String(splitRow.entry.description) : ""
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.792)
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
