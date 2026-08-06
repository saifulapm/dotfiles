import QtQuick
import "../components"
import "TailscaleModel.js" as Model

// Tailscale panel — full port of omarchy's tailscale plugin Panel.qml in our
// tokens: a hero of the Tailscale mark over a rotating phrase with the on/off
// switch on its trailing edge, the action/error line, the CONNECTIONS list
// (their login profiles, plus the authorize row a privileged refusal raises),
// the EXIT NODES list with their Mullvad region picker folded into it, and the
// MACHINES list with per-peer Taildrop and copy actions.
//
// Their single cursor model comes with it: the mouse and the keyboard move the
// same highlight, j/k (and the arrows) walk header → connections → exit nodes
// → machines, Enter activates whatever is under it, and their letter keys are
// t (toggle), r (refresh), c/n/d (copy the selected machine's IP, name or DNS
// name) and s (send files to it). The first arrow press only reveals the
// cursor.
//
// Deviations, all marked in place: the copy menu is an inline expansion of the
// machine row rather than a QtQuick.Controls Popup (this shell hand-rolls its
// controls), a "THIS DEVICE" block names the status, tailnet name and address
// their panel never shows, and two glyphs outside the Material Design range
// are substituted (see below).
BarPanel {
    id: panel

    // TailscaleService — the bar root's shared instance, injected by the
    // widget that opened this panel.
    required property var tailscale
    // The bar widget itself, for persisting inline settings.
    required property var widget

    panelTitle: ""
    cardWidth: 380

    // ------------------------------------------------------------- phrases
    property int phraseIndex: 0
    readonly property var activePhrases: ["Encrypting connections", "Sending secrets", "Guarding wires", "Braiding packets", "Polishing tunnels", "Hiding routes", "Sealing ports", "Sorting tailnets", "Shuffling keys", "Watching machines"]
    readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

    readonly property string toggleHint: tailscale.active ? "Turn Tailscale off" : (tailscale.needsLogin ? "Authorize this device" : "Turn Tailscale on")

    // ---------------------------------------------------- auto-receive advice
    // Only ever one sentence, and only when there is something to do about it.
    readonly property string receiveNotice: {
        const ts = panel.tailscale;
        if (ts.receiveUnit === "" || ts.receiveUnit === "unknown")
            return "";
        if (!ts.receiveActive)
            return "Received files stay in Tailscale's inbox until the receive service runs.";
        if (ts.receiveStuck)
            return ts.receiveDetail === "" ? "The receive service is retrying." : ts.receiveDetail + ".";
        return "";
    }

    readonly property string receiveCommand: {
        const ts = panel.tailscale;
        if (panel.receiveNotice === "")
            return "";
        if (!ts.receiveActive)
            return "systemctl --user enable --now taildrop-receive.service";
        // The script writes its own advice as "run: <command>".
        return ts.receiveHint.replace(/^run:\s*/, "");
    }

    // -------------------------------------------------------------- cursor
    property string focusSection: "header"
    property int accountIndex: 0
    property int peerIndex: 0
    property int exitNodeIndex: 0
    property int mullvadRegionIndex: 0
    property bool cursorActive: false

    // The copy menu, inline: the index of the machine row showing it, or -1.
    property int copyMenuRow: -1
    property int copyIndex: 0
    readonly property bool copyMenuOpen: copyMenuRow >= 0

    property bool mullvadPickerOpen: false
    property string mullvadQuery: ""

    readonly property bool showConnections: tailscale.accounts.length > 1 || tailscale.accountsAccessDenied
    readonly property bool showPeers: tailscale.active && tailscale.peers.length > 0
    readonly property var recentMullvadRegions: {
        const stored = widget && widget.settings ? widget.settings.recentMullvadRegions : undefined;
        return stored instanceof Array ? stored : [];
    }
    readonly property var recentMullvadExitNodes: recentMullvadNodes()
    readonly property var exitNodes: displayExitNodes()
    readonly property bool showExitNodes: tailscale.active && (exitNodes.length > 0 || tailscale.mullvadRegions.length > 0)
    readonly property var filteredMullvadRegions: filteredMullvadRegionNodes()
    // Only claim the header cursor when the switch is actually on screen —
    // "header" stays navigable, but an absent CLI leaves nothing to highlight.
    readonly property bool headerHasCursor: cursorActive && focusSection === "header" && tailscale.installed

    function selectedPeer() {
        if (panel.tailscale.peers.length === 0)
            return null;
        return panel.tailscale.peers[Math.max(0, Math.min(panel.peerIndex, panel.tailscale.peers.length - 1))];
    }

    function selectedExitNode() {
        if (panel.exitNodes.length === 0)
            return null;
        return panel.exitNodes[Math.max(0, Math.min(panel.exitNodeIndex, panel.exitNodes.length - 1))];
    }

    function selectedMullvadRegion() {
        if (panel.filteredMullvadRegions.length === 0)
            return null;
        return panel.filteredMullvadRegions[Math.max(0, Math.min(panel.mullvadRegionIndex, panel.filteredMullvadRegions.length - 1))];
    }

    function selectedAccount() {
        if (panel.tailscale.accounts.length === 0)
            return null;
        return panel.tailscale.accounts[Math.max(0, Math.min(panel.accountIndex, panel.tailscale.accounts.length - 1))];
    }

    // The tailnet's own exit nodes, then the Mullvad regions worth keeping at
    // hand (whatever is live, then the last few chosen), then the row that
    // opens the full region picker.
    function displayExitNodes() {
        const nodes = [];
        for (let i = 0; i < panel.tailscale.tailnetExitNodes.length; i++)
            nodes.push(panel.tailscale.tailnetExitNodes[i]);
        for (let j = 0; j < panel.recentMullvadExitNodes.length; j++)
            nodes.push(panel.recentMullvadExitNodes[j]);
        if (panel.tailscale.mullvadRegions.length > 0)
            nodes.push({
                id: "mullvad:add",
                AddMullvad: true,
                DisplayName: "Choose Mullvad region"
            });
        return nodes;
    }

    function recentMullvadNodes() {
        const nodes = [];
        const seen = {};
        for (let a = 0; a < panel.tailscale.mullvadRegions.length && nodes.length < 5; a++) {
            const activeNode = panel.tailscale.mullvadRegions[a];
            const activeKey = panel.mullvadRegionKey(activeNode);
            if (activeNode.ExitNode === true && activeKey !== "" && !seen[activeKey]) {
                nodes.push(activeNode);
                seen[activeKey] = true;
            }
        }
        for (let i = 0; i < panel.recentMullvadRegions.length && nodes.length < 5; i++) {
            const region = String(panel.recentMullvadRegions[i] || "");
            if (region === "" || seen[region])
                continue;
            const node = panel.mullvadRegionNode(region);
            if (node) {
                nodes.push(node);
                seen[region] = true;
            }
        }
        return nodes;
    }

    function mullvadRegionKey(node) {
        if (!node)
            return "";
        const country = String(node.Country || "");
        const city = String(node.City || "");
        if (country === "" || city === "")
            return "";
        return country + "\n" + city;
    }

    function mullvadRegionNode(region) {
        for (let i = 0; i < panel.tailscale.mullvadRegions.length; i++) {
            const node = panel.tailscale.mullvadRegions[i];
            if (panel.mullvadRegionKey(node) === String(region || ""))
                return node;
            if (String(node.Country || "") === String(region || ""))
                return node;
        }
        return null;
    }

    function filteredMullvadRegionNodes() {
        const query = String(panel.mullvadQuery || "").trim().toLowerCase();
        const result = [];
        for (let i = 0; i < panel.tailscale.mullvadRegions.length; i++) {
            const node = panel.tailscale.mullvadRegions[i];
            const label = (String(node.City || "") + " " + String(node.Country || "")).toLowerCase();
            if (query === "" || label.indexOf(query) !== -1)
                result.push(node);
        }
        return result;
    }

    function mullvadRegionTitle(peer) {
        if (!peer)
            return "Unknown";
        const city = String(peer.City || "").trim();
        const country = String(peer.Country || "").trim();
        if (city === "" || city === "Any")
            return country || String(peer.DisplayName || "Unknown");
        return city;
    }

    function mullvadRegionSubtitle(peer) {
        if (!peer)
            return "";
        return String(peer.Country || "").trim();
    }

    // Their recents list, persisted into this widget's inline shell.json entry
    // (the shell's updateEntryInline, which is how our clock keeps its format).
    function persistRecentMullvad(region) {
        const name = String(region || "");
        if (name === "")
            return;
        const next = [name];
        for (let i = 0; i < panel.recentMullvadRegions.length && next.length < 5; i++) {
            const existing = String(panel.recentMullvadRegions[i] || "");
            if (existing !== "" && existing !== name && next.indexOf(existing) === -1)
                next.push(existing);
        }
        if (!panel.widget || typeof panel.widget.persistSettings !== "function")
            return;
        panel.widget.persistSettings({
            recentMullvadRegions: next
        });
    }

    function chooseExitNode(peer) {
        if (!peer)
            return;
        if (peer.AddMullvad === true) {
            panel.mullvadPickerOpen = !panel.mullvadPickerOpen;
            panel.mullvadRegionIndex = 0;
            return;
        }
        if (peer.Mullvad === true)
            panel.persistRecentMullvad(panel.mullvadRegionKey(peer));
        panel.tailscale.setExitNode(peer);
        panel.mullvadPickerOpen = false;
    }

    function ensureCursor() {
        if (panel.accountIndex >= panel.tailscale.accounts.length)
            panel.accountIndex = Math.max(0, panel.tailscale.accounts.length - 1);
        if (panel.peerIndex >= panel.tailscale.peers.length)
            panel.peerIndex = Math.max(0, panel.tailscale.peers.length - 1);
        if (panel.exitNodeIndex >= panel.exitNodes.length)
            panel.exitNodeIndex = Math.max(0, panel.exitNodes.length - 1);
        if (panel.mullvadRegionIndex >= panel.filteredMullvadRegions.length)
            panel.mullvadRegionIndex = Math.max(0, panel.filteredMullvadRegions.length - 1);
        if (panel.focusSection === "auth" && !panel.tailscale.accountsAccessDenied)
            panel.focusSection = panel.tailscale.accounts.length > 1 ? "accounts" : (panel.showExitNodes ? "exitNodes" : (panel.showPeers ? "peers" : "header"));
        if (panel.focusSection === "accounts" && panel.tailscale.accounts.length <= 1)
            panel.focusSection = panel.tailscale.accountsAccessDenied ? "auth" : (panel.showExitNodes ? "exitNodes" : (panel.showPeers ? "peers" : "header"));
        if (panel.focusSection === "peers" && !panel.showPeers)
            panel.focusSection = panel.showExitNodes ? "exitNodes" : (panel.tailscale.accountsAccessDenied ? "auth" : (panel.tailscale.accounts.length > 1 ? "accounts" : "header"));
        if (panel.focusSection === "exitNodes" && !panel.showExitNodes)
            panel.focusSection = panel.showPeers ? "peers" : (panel.tailscale.accountsAccessDenied ? "auth" : (panel.tailscale.accounts.length > 1 ? "accounts" : "header"));
    }

    function moveCursor(dy) {
        panel.cursorActive = true;
        panel.ensureCursor();
        if (dy !== 0) {
            if (panel.focusSection === "header") {
                if (dy > 0) {
                    if (panel.tailscale.accountsAccessDenied)
                        panel.focusSection = "auth";
                    else if (panel.tailscale.accounts.length > 1)
                        panel.focusSection = "accounts";
                    else if (panel.showExitNodes)
                        panel.focusSection = "exitNodes";
                    else if (panel.showPeers)
                        panel.focusSection = "peers";
                }
            } else if (panel.focusSection === "auth") {
                if (dy < 0)
                    panel.focusSection = "header";
                else if (panel.tailscale.accounts.length > 1)
                    panel.focusSection = "accounts";
                else if (panel.showExitNodes)
                    panel.focusSection = "exitNodes";
                else if (panel.showPeers)
                    panel.focusSection = "peers";
            } else if (panel.focusSection === "accounts") {
                if (dy < 0) {
                    if (panel.accountIndex <= 0)
                        panel.focusSection = panel.tailscale.accountsAccessDenied ? "auth" : "header";
                    else
                        panel.accountIndex--;
                } else {
                    if (panel.accountIndex < panel.tailscale.accounts.length - 1)
                        panel.accountIndex++;
                    else if (panel.showExitNodes)
                        panel.focusSection = "exitNodes";
                    else if (panel.showPeers)
                        panel.focusSection = "peers";
                }
            } else if (panel.focusSection === "peers") {
                if (dy < 0) {
                    if (panel.peerIndex <= 0)
                        panel.focusSection = panel.showExitNodes ? "exitNodes" : (panel.tailscale.accounts.length > 1 ? "accounts" : (panel.tailscale.accountsAccessDenied ? "auth" : "header"));
                    else
                        panel.peerIndex--;
                } else if (panel.peerIndex < panel.tailscale.peers.length - 1)
                    panel.peerIndex++;
            } else if (panel.focusSection === "exitNodes") {
                if (dy < 0) {
                    if (panel.exitNodeIndex <= 0)
                        panel.focusSection = panel.tailscale.accounts.length > 1 ? "accounts" : (panel.tailscale.accountsAccessDenied ? "auth" : "header");
                    else
                        panel.exitNodeIndex--;
                } else if (panel.exitNodeIndex < panel.exitNodes.length - 1)
                    panel.exitNodeIndex++;
                else if (panel.showPeers)
                    panel.focusSection = "peers";
            }
        }
        panel.ensureCursor();
    }

    function activateCursor() {
        panel.ensureCursor();
        if (panel.focusSection === "header")
            panel.tailscale.toggleTailscale();
        else if (panel.focusSection === "auth")
            panel.authorizeOperator();
        else if (panel.focusSection === "accounts") {
            const account = panel.selectedAccount();
            if (account)
                panel.tailscale.switchAccount(account.id);
        } else if (panel.focusSection === "peers")
            panel.openCopyMenu(panel.peerIndex);
        else if (panel.focusSection === "exitNodes")
            panel.chooseExitNode(panel.selectedExitNode());
    }

    function moveMullvadRegionCursor(delta) {
        if (panel.filteredMullvadRegions.length === 0)
            return;
        panel.cursorActive = true;
        panel.mullvadRegionIndex = Math.max(0, Math.min(panel.filteredMullvadRegions.length - 1, panel.mullvadRegionIndex + delta));
    }

    function activateMullvadRegionCursor() {
        const region = panel.selectedMullvadRegion();
        if (region)
            panel.chooseExitNode(region);
    }

    function closeMullvadPicker() {
        panel.mullvadPickerOpen = false;
        panel.refocusKeys();
    }

    function setPeerCursor(index) {
        panel.cursorActive = true;
        panel.focusSection = "peers";
        panel.peerIndex = index;
    }

    function setExitNodeCursor(index) {
        panel.cursorActive = true;
        panel.focusSection = "exitNodes";
        panel.exitNodeIndex = index;
    }

    function setAccountCursor(index) {
        panel.cursorActive = true;
        panel.focusSection = "accounts";
        panel.accountIndex = index;
    }

    function setAuthCursor() {
        panel.cursorActive = true;
        panel.focusSection = "auth";
    }

    function setHeaderCursor() {
        panel.cursorActive = true;
        panel.focusSection = "header";
    }

    // The polkit dialog takes over from here, so get the panel out of the way:
    // both are Overlay layer surfaces asking for exclusive keyboard focus, and
    // a card still holding it is a password prompt nobody can type into.
    function authorizeOperator() {
        panel.tailscale.authorizeTailscaleOperator();
        panel.close();
    }

    // The file picker takes over from here, so get the panel out of the way.
    function sendPeerFile(peer) {
        if (!panel.tailscale.canSendFiles(peer))
            return;
        panel.tailscale.sendFile(peer);
        panel.close();
    }

    // ----------------------------------------------------------- copy menu
    // Their per-machine copy popup, inline: the machine row grows to show the
    // choices under itself. A QtQuick.Controls Popup would be the literal
    // port, but this shell hand-rolls its controls, and an inline expansion
    // needs no coordinate mapping out of a scrolling card.
    function copyOptionsFor(peer) {
        const options = [];
        if (!peer)
            return options;
        const name = String(peer.DisplayName || peer.HostName || "");
        const dns = Model.cleanDnsName(peer.DNSName);
        const ipv6 = peer.TailscaleIPv6 && peer.TailscaleIPv6.length > 0 ? String(peer.TailscaleIPv6[0]) : "";
        const ip = peer.TailscaleIPs && peer.TailscaleIPs.length > 0 ? String(peer.TailscaleIPs[0]) : "";
        if (name !== "")
            options.push({
                kind: "name",
                label: name
            });
        if (dns !== "")
            options.push({
                kind: "dns",
                label: dns
            });
        if (ipv6 !== "")
            options.push({
                kind: "ipv6",
                label: ipv6
            });
        if (ip !== "")
            options.push({
                kind: "ip",
                label: ip
            });
        return options;
    }

    function openCopyMenu(index) {
        const peer = panel.tailscale.peers[index];
        if (!peer || panel.copyOptionsFor(peer).length === 0)
            return;
        panel.setPeerCursor(index);
        panel.copyIndex = 0;
        panel.copyMenuRow = index;
    }

    function closeCopyMenu() {
        panel.copyMenuRow = -1;
        panel.copyIndex = 0;
    }

    function moveCopyCursor(delta) {
        const options = panel.copyOptionsFor(panel.selectedPeer());
        if (options.length === 0)
            return;
        panel.copyIndex = Math.max(0, Math.min(options.length - 1, panel.copyIndex + delta));
    }

    function copyOption(peer, kind) {
        if (kind === "name")
            panel.tailscale.copyPeerName(peer);
        else if (kind === "dns")
            panel.tailscale.copyPeerDnsName(peer);
        else if (kind === "ipv6")
            panel.tailscale.copyToClipboard(peer && peer.TailscaleIPv6 && peer.TailscaleIPv6.length > 0 ? peer.TailscaleIPv6[0] : "");
        else if (kind === "ip")
            panel.tailscale.copyPeerIp(peer);
        panel.closeCopyMenu();
    }

    function copyCurrentOption() {
        const peer = panel.selectedPeer();
        const options = panel.copyOptionsFor(peer);
        if (options.length === 0)
            return;
        panel.copyOption(peer, options[Math.max(0, Math.min(panel.copyIndex, options.length - 1))].kind);
    }

    // Keep the keyboard-focused row inside the viewport (NetworkPanel's).
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

    // ------------------------------------------------------------ keyboard
    onContentKey: event => {
        // Their key catcher is `blocked` while the copy popup owns the
        // keyboard, so the menu's own keys are all that work.
        if (panel.copyMenuOpen) {
            switch (event.key) {
            case Qt.Key_Escape:
                panel.closeCopyMenu();
                break;
            case Qt.Key_Down:
            case Qt.Key_J:
                panel.moveCopyCursor(1);
                break;
            case Qt.Key_Up:
            case Qt.Key_K:
                panel.moveCopyCursor(-1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                panel.copyCurrentOption();
                break;
            }
            event.accepted = true;
            return;
        }
        if (panel.mullvadPickerOpen && event.key === Qt.Key_Escape) {
            panel.closeMullvadPicker();
            event.accepted = true;
            return;
        }
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
                panel.cursorActive = true;
            break;
        case Qt.Key_T:
            panel.tailscale.toggleTailscale();
            break;
        case Qt.Key_R:
            panel.tailscale.refreshDetails(true);
            break;
        case Qt.Key_C:
            panel.tailscale.copyPeerIp(panel.selectedPeer());
            break;
        case Qt.Key_N:
            panel.tailscale.copyPeerName(panel.selectedPeer());
            break;
        case Qt.Key_D:
            panel.tailscale.copyPeerDnsName(panel.selectedPeer());
            break;
        case Qt.Key_S:
            panel.sendPeerFile(panel.selectedPeer());
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ----------------------------------------------------------- lifecycle
    onPanelOpened: {
        panel.cursorActive = false;
        panel.closeCopyMenu();
        panel.mullvadPickerOpen = false;
        panel.mullvadQuery = "";
        scroller.contentY = 0;
        panel.tailscale.refreshDetails(false);
        panel.ensureCursor();
    }

    onShowConnectionsChanged: panel.ensureCursor()
    onShowPeersChanged: panel.ensureCursor()
    onShowExitNodesChanged: panel.ensureCursor()
    onFilteredMullvadRegionsChanged: panel.ensureCursor()

    Connections {
        target: panel.tailscale
        function onPeersChanged() {
            panel.closeCopyMenu();
            panel.ensureCursor();
        }
        function onAccountsChanged() {
            panel.ensureCursor();
        }
        function onAccountsAccessDeniedChanged() {
            panel.ensureCursor();
        }
    }

    Timer {
        id: phraseTimer
        interval: 2800
        running: panel.opened && panel.tailscale.active
        repeat: true
        onTriggered: phraseSwap.restart()
    }

    SequentialAnimation {
        id: phraseSwap
        PropertyAnimation {
            target: heroMeta
            property: "opacity"
            to: 0.0
            duration: 180
            easing.type: Easing.OutQuad
        }
        ScriptAction {
            script: panel.phraseIndex = (panel.phraseIndex + 1) % panel.activePhrases.length
        }
        PropertyAnimation {
            target: heroMeta
            property: "opacity"
            to: 1.0
            duration: 260
            easing.type: Easing.InQuad
        }
    }

    // -------------------------------------------------------------- content
    Flickable {
        id: scroller

        width: parent.width
        // Capped like their popup: a big tailnet scrolls inside the card
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
            Item {
                id: hero

                width: parent.width
                implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

                TailscaleIcon {
                    id: heroIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    iconSize: panel.theme.fontPx(1.6)
                    color: panel.tailscale.active ? panel.theme.textPrimary : panel.theme.textMuted
                    opacity: panel.tailscale.active ? 1.0 : 0.5
                    crossed: !panel.tailscale.active && !panel.tailscale.needsLogin
                    warning: panel.tailscale.needsLogin
                    badgeColor: panel.theme.error
                    badgeBorderColor: panel.theme.surface1
                    badgeTextColor: panel.theme.surface1
                    fontFamily: panel.theme.fontUi
                }

                // Their compact on/off switch on the trailing edge of the hero,
                // and the header's only cursor target. The service flips
                // `active` optimistically, so the knob throws on the click.
                ToggleSwitch {
                    id: powerSwitch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: panel.tailscale.installed
                    checked: panel.tailscale.active
                    busy: panel.tailscale.busy
                    hasCursor: panel.headerHasCursor
                    hint: panel.toggleHint
                    onHovered: panel.setHeaderCursor()
                    onToggled: panel.tailscale.toggleTailscale()
                }

                Column {
                    id: heroLabels

                    anchors.left: heroIcon.right
                    anchors.leftMargin: panel.theme.space(3)
                    anchors.right: powerSwitch.visible ? powerSwitch.left : parent.right
                    anchors.rightMargin: panel.theme.space(3)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(0.5)

                    Text {
                        width: parent.width
                        text: panel.tailscale.installed && panel.tailscale.selfName !== "" ? panel.tailscale.selfName : "Tailscale"
                        color: panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(1.083)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        id: heroMeta
                        width: parent.width
                        text: panel.tailscale.active ? panel.heroPhraseText : "Tailscale is disconnected"
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.833)
                        elide: Text.ElideRight
                    }
                }
            }

            // -------------------------------------------------- action/error
            Text {
                visible: panel.tailscale.actionStatus !== "" || panel.tailscale.lastError !== ""
                width: parent.width
                text: panel.tailscale.actionStatus !== "" ? panel.tailscale.actionStatus : panel.tailscale.lastError
                color: panel.tailscale.lastError !== "" && panel.tailscale.actionStatus === "" ? panel.theme.error : panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.833)
                wrapMode: Text.WordWrap
            }

            // ------------------------------------------------- not installed
            // Unreachable from the bar (the widget hides itself without a CLI),
            // but kept from theirs for the case where the probe answers while
            // the card is already open.
            Rectangle {
                visible: !panel.tailscale.installed && panel.tailscale.probed
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
                    text: "Tailscale CLI is not installed or not on PATH."
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    wrapMode: Text.WordWrap
                }
            }

            // --------------------------------------------------- this device
            // Ours: their panel names the device in the hero and then never
            // says what state it is in or what address it answers on, which is
            // most of what a tailnet widget is asked. Click a value to copy it.
            Column {
                visible: panel.tailscale.installed && panel.tailscale.probed
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "THIS DEVICE"
                }

                InfoPair {
                    width: parent.width
                    label: "Status"
                    value: panel.tailscale.statusText
                }

                InfoPair {
                    width: parent.width
                    visible: panel.tailscale.selfDnsName !== ""
                    label: "Tailnet name"
                    value: panel.tailscale.selfDnsName
                    copyValue: panel.tailscale.selfDnsName
                }

                InfoPair {
                    width: parent.width
                    visible: panel.tailscale.selfIp !== ""
                    label: "Address"
                    value: panel.tailscale.selfIp
                    copyValue: panel.tailscale.selfIp
                }

                // Ours: Taildrop only half works on Linux out of the box —
                // tailscaled holds received files in an inbox until something
                // runs `tailscale file get`. taildrop-receive.service is what
                // runs it here, so the panel says whether it is up.
                InfoPair {
                    width: parent.width
                    label: "Auto-receive"
                    value: panel.tailscale.receiveSummary
                }

                InfoPair {
                    width: parent.width
                    visible: panel.tailscale.receivePending > 0
                    label: "Inbox"
                    value: panel.tailscale.receivePending + (panel.tailscale.receivePending === 1 ? " file waiting" : " files waiting")
                }

                NoticeRow {
                    width: parent.width
                    visible: panel.receiveNotice !== ""
                    text: panel.receiveNotice
                    command: panel.receiveCommand
                }
            }

            // --------------------------------------------------- connections
            Separator {
                theme: panel.theme
                visible: panel.showConnections
            }

            Column {
                visible: panel.showConnections
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "CONNECTIONS"
                }

                AuthRow {
                    visible: panel.tailscale.accountsAccessDenied
                    width: parent.width
                }

                Repeater {
                    model: panel.tailscale.accounts

                    AccountRow {
                        required property var modelData
                        required property int index

                        width: parent.width
                        account: modelData
                        rowIndex: index
                    }
                }
            }

            // ---------------------------------------------------- exit nodes
            Separator {
                theme: panel.theme
                visible: panel.showExitNodes
            }

            Column {
                visible: panel.showExitNodes
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "EXIT NODES"
                }

                Column {
                    id: exitNodeColumn
                    width: parent.width
                    spacing: panel.theme.space(0.5)

                    Repeater {
                        model: panel.exitNodes

                        ExitNodeRow {
                            required property var modelData
                            required property int index

                            width: exitNodeColumn.width
                            peer: modelData
                            rowIndex: index
                        }
                    }

                    Column {
                        visible: panel.mullvadPickerOpen
                        width: parent.width
                        spacing: panel.theme.space(1)
                        topPadding: panel.theme.space(1)

                        TextField {
                            width: parent.width
                            placeholder: "Search regions"
                            focusWhen: panel.mullvadPickerOpen
                            onTextEdited: text => {
                                panel.mullvadQuery = text;
                                panel.mullvadRegionIndex = 0;
                            }
                            onMoveRequested: delta => panel.moveMullvadRegionCursor(delta)
                            onAccepted: panel.activateMullvadRegionCursor()
                            onCancelled: panel.closeMullvadPicker()
                        }

                        Text {
                            visible: panel.filteredMullvadRegions.length === 0
                            width: parent.width
                            text: "No Mullvad regions found."
                            color: panel.theme.textMuted
                            font.family: panel.theme.fontUi
                            font.pixelSize: panel.theme.fontPx(0.833)
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Column {
                            id: mullvadRegionColumn
                            width: parent.width
                            spacing: panel.theme.space(0.5)

                            Repeater {
                                model: panel.filteredMullvadRegions

                                MullvadRegionRow {
                                    required property var modelData
                                    required property int index

                                    width: mullvadRegionColumn.width
                                    peer: modelData
                                    rowIndex: index
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------------ machines
            Separator {
                theme: panel.theme
                visible: panel.tailscale.installed && panel.tailscale.active
            }

            Column {
                visible: panel.tailscale.installed && panel.tailscale.active
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "MACHINES"
                }

                Text {
                    visible: panel.tailscale.peers.length === 0
                    width: parent.width
                    text: "No machines found on this tailnet."
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    horizontalAlignment: Text.AlignHCenter
                }

                Column {
                    id: peerColumn

                    visible: panel.showPeers
                    width: parent.width
                    spacing: panel.theme.space(0.5)

                    Repeater {
                        model: panel.tailscale.peers

                        PeerRow {
                            required property var modelData
                            required property int index

                            width: peerColumn.width
                            peer: modelData
                            rowIndex: index
                        }
                    }
                }
            }
        }
    }

    // ----------------------------------------------------------- components
    component CursorSurface: Rectangle {
        property bool hasCursor: false
        property bool current: false

        radius: panel.theme.radius(0.75)
        color: current ? panel.theme.alpha(panel.theme.accent, 0.18) : (hasCursor ? panel.theme.alpha(panel.theme.textPrimary, 0.06) : "transparent")
        border.width: panel.theme.borderWidth
        border.color: hasCursor ? panel.theme.alpha(panel.theme.accent, 0.6) : "transparent"
    }

    // A label on the left and a value on the right; the value copies itself
    // when it has something worth copying.
    component InfoPair: Item {
        id: infoPair

        property string label: ""
        property string value: ""
        property string copyValue: ""

        implicitHeight: visible ? Math.max(infoLabel.implicitHeight, infoValue.implicitHeight) : 0

        HoverHandler {
            id: infoHover
            enabled: infoPair.copyValue !== ""
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            enabled: infoPair.copyValue !== ""
            onTapped: panel.tailscale.copyToClipboard(infoPair.copyValue)
        }

        PanelHint {
            theme: panel.theme
            visible: infoHover.hovered
            anchor: infoPair
            text: "Copy"
        }

        Text {
            id: infoLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: infoPair.label
            color: panel.theme.textPrimary
            opacity: 0.6
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.833)
        }

        Text {
            id: infoValue
            anchors.right: parent.right
            anchors.left: infoLabel.right
            anchors.leftMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: infoPair.value
            color: panel.theme.textPrimary
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.833)
        }
    }

    // Ours: a sentence about something the shell cannot fix by itself, over the
    // command that fixes it. Tapping copies the command — this shell has no
    // terminal to hand it to, and typing a `--operator=` line back out of a
    // screenshot is exactly the kind of thing a panel should spare you.
    component NoticeRow: Rectangle {
        id: noticeRow

        property string text: ""
        property string command: ""

        implicitHeight: visible ? noticeColumn.implicitHeight + panel.theme.space(3) : 0
        radius: panel.theme.radius(0.75)
        color: panel.theme.surface2

        HoverHandler {
            id: noticeHover
            enabled: noticeRow.command !== ""
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            enabled: noticeRow.command !== ""
            onTapped: panel.tailscale.copyToClipboard(noticeRow.command)
        }

        PanelHint {
            theme: panel.theme
            visible: noticeHover.hovered
            anchor: noticeRow
            text: "Copy command"
        }

        Column {
            id: noticeColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(3)
            anchors.rightMargin: panel.theme.space(3)
            spacing: panel.theme.space(1)

            Text {
                width: parent.width
                text: noticeRow.text
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.833)
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                visible: noticeRow.command !== ""
                text: noticeRow.command
                color: panel.theme.textPrimary
                font.family: panel.theme.fontMono
                font.pixelSize: panel.theme.fontPx(0.833)
                elide: Text.ElideRight
            }
        }
    }

    component AuthRow: CursorSurface {
        id: authRow

        hasCursor: panel.cursorActive && panel.focusSection === "auth"
        implicitHeight: authInner.implicitHeight + panel.theme.space(3)

        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(authRow)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: !panel.tailscale.busy
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: panel.setAuthCursor()
            onClicked: panel.authorizeOperator()
        }

        Item {
            id: authInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: Math.max(authGlyph.implicitHeight, authLabels.implicitHeight)

            OpticalGlyph {
                id: authGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "󰒃"
                color: panel.theme.textMuted
                pixelSize: panel.theme.fontPx(1.083)
            }

            Column {
                id: authLabels

                anchors.left: authGlyph.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                Text {
                    width: parent.width
                    text: "Authorize Tailscale operator"
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: "Allow this user to operate this Tailscale profile"
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.75)
                    elide: Text.ElideRight
                }
            }
        }
    }

    component AccountRow: CursorSurface {
        id: accountRow

        property var account: null
        property int rowIndex: 0
        readonly property bool selectedAccount: account && account.selected === true
        readonly property bool switchingAccount: account && panel.tailscale.switchingAccountId === String(account.id || "")
        readonly property string accountText: account ? panel.tailscale.accountLabel(account) : "Account"

        hasCursor: panel.cursorActive && panel.focusSection === "accounts" && panel.accountIndex === rowIndex
        current: selectedAccount
        implicitHeight: accountInner.implicitHeight + panel.theme.space(3)

        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(accountRow)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: panel.setAccountCursor(accountRow.rowIndex)
            onClicked: if (accountRow.account)
                panel.tailscale.switchAccount(accountRow.account.id)
        }

        Item {
            id: accountInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(accountGlyph.implicitHeight, accountLabel.implicitHeight)

            // Their account glyph is the Codicon U+EB01, which does not render
            // under our Symbols Nerd Font fallback (nor do FontAwesome or
            // Devicons — only the Material Design range does). Substituted
            // with md-account, U+F0004.
            OpticalGlyph {
                id: accountGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "󰀄"
                color: accountRow.selectedAccount || accountRow.switchingAccount ? panel.theme.textPrimary : panel.theme.textMuted
                pixelSize: panel.theme.fontPx(1.0)
                opacity: accountRow.switchingAccount ? 0.45 : 1.0

                SequentialAnimation on opacity {
                    running: accountRow.switchingAccount
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 1.0
                        duration: 420
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        to: 0.45
                        duration: 420
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Text {
                id: accountLabel

                anchors.left: accountGlyph.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: accountRow.accountText
                color: panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
                font.weight: accountRow.selectedAccount ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
        }
    }

    component ExitNodeRow: CursorSurface {
        id: exitNodeRow

        property var peer: null
        property int rowIndex: 0
        readonly property bool addMullvad: peer && peer.AddMullvad === true
        readonly property bool activeExitNode: peer && peer.ExitNode === true
        readonly property bool settingExitNode: peer && panel.tailscale.settingExitNodeId === String(peer.id || "")
        readonly property string peerName: peer ? String(peer.DisplayName || peer.HostName || "Unknown") : "Unknown"
        readonly property string actionTooltip: addMullvad ? "" : (activeExitNode ? "Disconnect" : "Connect")

        hasCursor: panel.cursorActive && panel.focusSection === "exitNodes" && panel.exitNodeIndex === rowIndex
        current: activeExitNode || settingExitNode || (addMullvad && panel.mullvadPickerOpen)
        implicitHeight: exitNodeInner.implicitHeight + panel.theme.space(3)

        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(exitNodeRow)

        MouseArea {
            id: exitNodeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: panel.setExitNodeCursor(exitNodeRow.rowIndex)
            onClicked: panel.chooseExitNode(exitNodeRow.peer)
        }

        Item {
            id: exitNodeInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(exitNodeGlyph.implicitHeight, exitNodeLabel.implicitHeight)

            // Their "+" for the picker row is an ASCII plus in the UI font;
            // this glyph column is typeset in the symbol font, which carries no
            // ASCII at all, so md-plus (U+F0415) stands in.
            OpticalGlyph {
                id: exitNodeGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: exitNodeRow.addMullvad ? "󰐕" : (exitNodeRow.peer && exitNodeRow.peer.Mullvad === true ? "󰖂" : "󱇢")
                color: exitNodeRow.activeExitNode || exitNodeRow.settingExitNode || exitNodeRow.addMullvad ? panel.theme.textPrimary : panel.theme.textMuted
                pixelSize: panel.theme.fontPx(1.0)

                NumberAnimation on rotation {
                    running: exitNodeRow.settingExitNode
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                }

                onRotationChanged: if (!exitNodeRow.settingExitNode && rotation !== 0)
                    rotation = 0
            }

            Text {
                id: exitNodeLabel

                anchors.left: exitNodeGlyph.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: exitNodeRow.peerName
                color: panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
                font.weight: exitNodeRow.activeExitNode ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
        }

        PanelHint {
            theme: panel.theme
            visible: exitNodeRow.actionTooltip !== "" && exitNodeMouse.containsMouse
            anchor: exitNodeRow
            text: exitNodeRow.actionTooltip
        }
    }

    component MullvadRegionRow: CursorSurface {
        id: regionRow

        property var peer: null
        property int rowIndex: 0
        readonly property string regionName: panel.mullvadRegionTitle(peer)
        readonly property string regionDetail: panel.mullvadRegionSubtitle(peer)
        readonly property bool activeExitNode: peer && peer.ExitNode === true
        readonly property bool settingExitNode: peer && panel.tailscale.settingExitNodeId === String(peer.id || "")
        readonly property bool selectedRegion: panel.mullvadPickerOpen && panel.mullvadRegionIndex === rowIndex
        readonly property string actionTooltip: activeExitNode ? "Disconnect" : "Connect"

        current: activeExitNode || settingExitNode || selectedRegion
        implicitHeight: regionInner.implicitHeight + panel.theme.space(2.5)

        onCurrentChanged: if (current && regionRow.selectedRegion)
            panel.ensureCursorVisible(regionRow)

        MouseArea {
            id: regionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: panel.mullvadRegionIndex = regionRow.rowIndex
            onClicked: panel.chooseExitNode(regionRow.peer)
        }

        Item {
            id: regionInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(regionGlyph.implicitHeight, regionLabels.implicitHeight)

            OpticalGlyph {
                id: regionGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "󰖂"
                color: regionRow.current ? panel.theme.textPrimary : panel.theme.textMuted
                pixelSize: panel.theme.fontPx(1.0)
            }

            Column {
                id: regionLabels

                anchors.left: regionGlyph.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                Text {
                    width: parent.width
                    text: regionRow.regionName
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    font.weight: regionRow.activeExitNode ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: regionRow.regionDetail
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.75)
                    elide: Text.ElideRight
                }
            }
        }

        PanelHint {
            theme: panel.theme
            visible: regionMouse.containsMouse
            anchor: regionRow
            text: regionRow.actionTooltip
        }
    }

    component PeerRow: CursorSurface {
        id: peerRow

        property var peer: null
        property int rowIndex: 0
        readonly property string peerName: peer ? String(peer.DisplayName || peer.HostName || "Unknown") : "Unknown"
        readonly property string peerIp: peer && peer.TailscaleIPs && peer.TailscaleIPs.length > 0 ? String(peer.TailscaleIPs[0]) : ""
        readonly property string peerDns: peer ? String(peer.DNSName || "") : ""
        readonly property var copyOptions: panel.copyOptionsFor(peer)
        readonly property bool menuOpen: panel.copyMenuRow === rowIndex

        hasCursor: panel.cursorActive && panel.focusSection === "peers" && panel.peerIndex === rowIndex
        implicitHeight: peerInner.implicitHeight + panel.theme.space(3) + (menuOpen ? copyMenu.implicitHeight + panel.theme.space(1) : 0)

        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(peerRow)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onContainsMouseChanged: if (containsMouse)
                panel.setPeerCursor(peerRow.rowIndex)
        }

        Item {
            id: peerInner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: panel.theme.space(1.5)
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(peerGlyph.implicitHeight, peerLabels.implicitHeight, copyButton.implicitHeight)

            OpticalGlyph {
                id: peerGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: panel.tailscale.osIcon(peerRow.peer ? peerRow.peer.OS : "")
                color: panel.theme.textPrimary
                pixelSize: panel.theme.fontPx(1.083)
            }

            GlyphAction {
                id: copyButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰆏"
                hint: "Copy"
                enabled: peerRow.copyOptions.length > 0
                onActivated: peerRow.menuOpen ? panel.closeCopyMenu() : panel.openCopyMenu(peerRow.rowIndex)
            }

            GlyphAction {
                id: sendButton
                anchors.right: copyButton.left
                anchors.rightMargin: panel.theme.space(1)
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.tailscale.canSendFiles(peerRow.peer)
                glyph: "󰒊"
                hint: "Send files"
                onActivated: panel.sendPeerFile(peerRow.peer)
            }

            Column {
                id: peerLabels

                anchors.left: peerGlyph.right
                anchors.leftMargin: panel.theme.space(2)
                anchors.right: sendButton.visible ? sendButton.left : copyButton.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                Text {
                    width: parent.width
                    text: peerRow.peerName
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: {
                        const parts = [];
                        if (peerRow.peerIp !== "")
                            parts.push(peerRow.peerIp);
                        if (peerRow.peerDns !== "")
                            parts.push(peerRow.peerDns);
                        return parts.join(" · ");
                    }
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.75)
                    elide: Text.ElideRight
                }
            }
        }

        Column {
            id: copyMenu

            visible: peerRow.menuOpen
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: peerInner.bottom
            anchors.topMargin: panel.theme.space(1)
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            spacing: 0

            Repeater {
                model: peerRow.menuOpen ? peerRow.copyOptions : []

                CopyChoice {
                    required property var modelData
                    required property int index

                    width: copyMenu.width
                    label: String(modelData.label || "")
                    selected: panel.copyIndex === index
                    onHovered: panel.copyIndex = index
                    onChosen: panel.copyOption(peerRow.peer, String(modelData.kind || ""))
                }
            }
        }
    }

    component CopyChoice: CursorSurface {
        id: copyChoice

        property string label: ""
        property bool selected: false

        signal chosen
        signal hovered

        hasCursor: selected
        implicitHeight: panel.theme.space(7)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: copyChoice.hovered()
            onClicked: copyChoice.chosen()
        }

        Text {
            anchors.left: parent.left
            anchors.right: choiceGlyph.left
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            text: copyChoice.label
            color: panel.theme.textPrimary
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.833)
            elide: Text.ElideRight
        }

        OpticalGlyph {
            id: choiceGlyph
            anchors.right: parent.right
            anchors.rightMargin: panel.theme.space(2.5)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰆏"
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(0.917)
        }
    }

    // Their PanelActionButton: a bordered square holding one glyph. The house
    // PanelButton draws its label in the UI font, which carries no Nerd Font
    // coverage — glyphs have to go through OpticalGlyph.
    component GlyphAction: Rectangle {
        id: glyphAction

        property string glyph: ""
        property string hint: ""

        // Item.enabled itself, not a shadowing property of the same name:
        // disabling the item disables its handlers with it.
        signal activated

        implicitWidth: panel.theme.space(8)
        implicitHeight: panel.theme.space(7)
        radius: panel.theme.radius(0.75)
        color: glyphHover.hovered && glyphAction.enabled ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2
        border.width: panel.theme.borderWidth
        border.color: panel.theme.surface3
        opacity: glyphAction.enabled ? 1 : 0.45

        OpticalGlyph {
            anchors.centerIn: parent
            text: glyphAction.glyph
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(1.0)
        }

        HoverHandler {
            id: glyphHover
            cursorShape: glyphAction.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            onTapped: glyphAction.activated()
        }

        PanelHint {
            theme: panel.theme
            visible: glyphHover.hovered && glyphAction.hint !== ""
            anchor: glyphAction
            text: glyphAction.hint
        }
    }

    // Their ToggleSwitch, as ported for the network and dropbox panels.
    component ToggleSwitch: Rectangle {
        id: toggle

        property bool checked: false
        property bool hasCursor: false
        property bool busy: false
        property string hint: ""

        signal hovered
        signal toggled

        implicitWidth: panel.theme.space(10)
        implicitHeight: panel.theme.space(5.5)
        radius: height / 2
        color: checked ? panel.theme.accent : panel.theme.surface3
        border.width: panel.theme.borderWidth
        border.color: toggle.hasCursor ? panel.theme.accent : "transparent"
        opacity: toggle.busy ? 0.6 : 1

        Behavior on color {
            ColorAnimation {
                duration: panel.theme.time(0.5)
            }
        }

        Rectangle {
            y: (parent.height - height) / 2
            x: toggle.checked ? parent.width - width - (parent.height - height) / 2 : (parent.height - height) / 2
            width: parent.height - panel.theme.space(1.5)
            height: width
            radius: width / 2
            color: toggle.checked ? panel.theme.textOnAccent : panel.theme.textMuted

            Behavior on x {
                NumberAnimation {
                    duration: panel.theme.time(0.5)
                    easing.type: panel.theme.easing
                }
            }
        }

        HoverHandler {
            id: toggleHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                toggle.hovered()
        }

        TapHandler {
            onTapped: toggle.toggled()
        }

        PanelHint {
            theme: panel.theme
            visible: toggleHover.hovered && toggle.hint !== ""
            anchor: toggle
            text: toggle.hint
        }
    }

    // NetworkPanel's field, with their region picker's arrow keys added: a
    // focused TextInput swallows every printable key, so j/k cannot move the
    // list from inside the box (upstream reads them too, and cannot either).
    component TextField: Rectangle {
        id: field

        property string placeholder: ""
        property bool focusWhen: false
        property alias text: input.text

        signal textEdited(string text)
        signal moveRequested(int delta)
        signal accepted
        signal cancelled

        implicitHeight: panel.theme.space(8)
        radius: panel.theme.radius(0.75)
        color: panel.theme.surface2
        border.width: panel.theme.borderWidth
        border.color: input.activeFocus ? panel.theme.accent : panel.theme.surface3

        onFocusWhenChanged: if (focusWhen)
            Qt.callLater(function () {
                input.forceActiveFocus();
            })

        Component.onCompleted: if (focusWhen)
            Qt.callLater(function () {
                input.forceActiveFocus();
            })

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            verticalAlignment: TextInput.AlignVCenter
            color: panel.theme.textPrimary
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.917)
            clip: true

            onTextChanged: field.textEdited(text)
            onAccepted: field.accepted()
            Keys.onEscapePressed: field.cancelled()
            Keys.onDownPressed: field.moveRequested(1)
            Keys.onUpPressed: field.moveRequested(-1)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: field.placeholder
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
            }
        }
    }
}
