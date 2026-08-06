import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../components"
import "NetworkModel.js" as Model

// Network panel — full port of omarchy's network plugin Panel.qml in our own
// tokens: a hero carrying the connection name, a QR share button, a speed-test
// button and the Wi-Fi radio switch; the live stats grid (ping, packet loss,
// rates, totals, IP, gateway); the WI-FI BAND selector with its Automatic
// switch; the DNS PROVIDER pills; and the KNOWN/OTHER NETWORKS list with
// inline passphrase entry and forget-on-hover.
//
// The numbers come from bin/network-status --verbose, the band from
// bin/network-band and the DNS provider from bin/network-dns — all three are
// ports of their helpers. Sampling runs on a 1.5s timer (4s for the band,
// which shells out to nmcli several times) and, like the Wi-Fi scanner, only
// while the panel is open: the shell's no-polling rule is about idle cost, and
// nothing here ticks once the card is dismissed.
//
// One cursor model drives mouse and keyboard together, as in AudioPanel:
// hovering moves the cursor, j/k walk it across sections, h/l move within a
// row of pills, Enter activates, Escape closes.
BarPanel {
    id: panel

    panelTitle: ""
    cardWidth: theme.space(95)

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"

    // ------------------------------------------------------------- devices
    readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var wiredDevice: findDevice(DeviceType.Wired)
    readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    readonly property var connectedWifiNetwork: findConnectedWifiNetwork()
    property bool wifiStationAvailable: false

    // Prefer a connected device: a machine can expose several NICs of the same
    // type, and the first-enumerated one may be carrierless.
    function findDevice(type) {
        const devices = panel.networkDevices || [];
        let fallback = null;
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i];
            if (!device || device.type !== type)
                continue;
            if (device.connected)
                return device;
            if (!fallback)
                fallback = device;
        }
        return fallback;
    }

    function findConnectedWifiNetwork() {
        const networks = panel.wifiNetworkObjects || [];
        for (let i = 0; i < networks.length; i++) {
            if (networks[i] && networks[i].connected)
                return networks[i];
        }
        return null;
    }

    readonly property string kind: {
        if (panel.wiredDevice && panel.wiredDevice.connected)
            return "ethernet";
        if (panel.connectedWifiNetwork)
            return "wifi";
        return "disconnected";
    }

    // --------------------------------------------------------------- stats
    // { iface, type, ip, prefix, gateway, speed, duplex, ssid, signal, freq,
    //   bitrate, rx_bytes, tx_bytes, router_ping_ms, internet_ping_ms }
    property var info: ({})

    property real prevRxBytes: 0
    property real prevTxBytes: 0
    property real prevSampleTime: 0
    property string prevIface: ""
    property real downloadRate: 0
    property real uploadRate: 0
    property string pingIface: ""
    property var routerPingSamples: []
    property var internetPingSamples: []
    property real routerPingLatency: -1
    property real internetPingLatency: -1
    property int internetPingPacketLoss: 0
    readonly property int pingHistoryWindow: 24
    readonly property int pingAverageWindow: 5
    readonly property bool hasInternetPing: internetPingSamples.length > 0
    // Every stat row stays mounted whether or not there is data behind it, so
    // a sample arriving late never reflows the grid.
    readonly property bool hasTransferStats: info.rx_bytes !== undefined

    // Their idle caption: a rotating phrase in place of a static "connected".
    property int connectionPhraseIndex: 0
    readonly property var connectionPhrases: ["Wiring bits", "Handling packets", "Sorting frames", "Hauling bytes", "Routing crumbs", "Counting collisions", "Bending light"]
    readonly property string connectionPhrase: connectionPhrases[connectionPhraseIndex % connectionPhrases.length]

    function updateDetails(raw) {
        const next = Model.parseKeyValue(raw);

        // A band change tears the link down and brings it back, and the status
        // command reports nothing at all while there is no route. Publishing
        // that would blank every stat mid-toggle, so the last good sample
        // stands until the reconnect settles. A real disconnect is still
        // reported, because nothing is in flight then.
        if (panel.bandBusy && !next.iface)
            return;

        panel.info = next;
        panel.updateThroughput(next);
        panel.updatePingLatency(next);
    }

    function updateThroughput(next) {
        const state = Model.throughputState({
            prevIface: panel.prevIface,
            prevRxBytes: panel.prevRxBytes,
            prevTxBytes: panel.prevTxBytes,
            prevSampleTime: panel.prevSampleTime,
            downloadRate: panel.downloadRate,
            uploadRate: panel.uploadRate
        }, next, Date.now() / 1000);

        panel.prevIface = state.prevIface;
        panel.prevRxBytes = state.prevRxBytes;
        panel.prevTxBytes = state.prevTxBytes;
        panel.prevSampleTime = state.prevSampleTime;
        panel.downloadRate = state.downloadRate;
        panel.uploadRate = state.uploadRate;
    }

    function updatePingLatency(next) {
        const state = Model.pingLatencyState({
            pingIface: panel.pingIface,
            routerPingSamples: panel.routerPingSamples,
            internetPingSamples: panel.internetPingSamples
        }, next, panel.pingHistoryWindow, panel.pingAverageWindow);

        panel.pingIface = state.pingIface;
        panel.routerPingSamples = state.routerPingSamples;
        panel.internetPingSamples = state.internetPingSamples;
        panel.routerPingLatency = state.routerPingLatency;
        panel.internetPingLatency = state.internetPingLatency;
        panel.internetPingPacketLoss = state.internetPingPacketLoss;
    }

    // ---------------------------------------------------------------- band
    // `bandCurrent` is the band the radio is actually on; `bandSelected` is
    // the pinned choice ("auto" when nothing is pinned).
    property string bandCurrent: ""
    property string bandSelected: "auto"
    property var bandAvailable: []
    property string pendingBand: ""

    readonly property bool bandBusy: pendingBand !== ""
    // While a change is in flight, show the state that was asked for rather
    // than the one still in force, so the row answers the click immediately.
    readonly property string bandEffective: pendingBand !== "" ? pendingBand : bandSelected
    readonly property bool bandPinned: bandEffective !== "auto"
    // Worth showing when there is a real choice, or when a pin is in force
    // even though only one band answers right now — otherwise the Automatic
    // switch vanishes and the pin becomes unclearable from the panel.
    readonly property bool canSelectBand: (kind === "wifi" || bandBusy) && (bandAvailable.length > 1 || bandPinned)
    // Under Automatic there is nothing to pick, so the pills collapse away and
    // the header states the live band instead.
    readonly property bool bandPillsVisible: canSelectBand && bandPinned
    readonly property string bandSectionTitle: Model.bandSectionTitle(bandEffective, bandCurrent)

    function updateBand(raw) {
        const status = Model.parseBandStatus(raw);

        // Mid-reconnect there is no connected station, so the command reports
        // nothing. Publishing that would empty the option list and unmount the
        // section on every toggle — same guard as updateDetails.
        if (panel.bandBusy && status.available.length === 0)
            return;

        panel.bandCurrent = status.band;
        panel.bandSelected = status.selected;
        panel.bandAvailable = status.available;
    }

    // Pinning a band reassociates, but the panel deliberately stays open: the
    // reconnect is the thing you want to watch, and the stats above report it
    // as it happens.
    function setBand(band) {
        if (!band || actionProc.running)
            return;
        panel.pendingBand = band;
        actionProc.command = [panel.binDir + "network-band", band];
        actionProc.running = true;
    }

    // Switching Automatic off has to commit to something, so it pins whatever
    // band the radio already landed on — the reading the header is showing.
    function toggleBandAuto() {
        if (panel.bandSelected !== "auto") {
            panel.setBand("auto");
            return;
        }
        if (panel.bandCurrent === "")
            return;
        panel.setBand(panel.bandCurrent);
    }

    // ----------------------------------------------------------------- dns
    readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]
    property string dnsProvider: ""
    property string pendingDnsProvider: ""
    property bool dnsCustomOpen: false
    property string dnsCustomText: ""

    function updateDns(raw) {
        panel.dnsProvider = String(raw || "").trim() || "DHCP";
    }

    // Custom expands an inline field instead of shelling out to a terminal as
    // theirs does — the panel already owns a keyboard focus scope, and a
    // floating terminal for two IP addresses is a detour.
    function setDns(provider) {
        if (!provider || actionProc.running)
            return;

        if (provider === "Custom") {
            panel.dnsCustomOpen = true;
            return;
        }

        panel.dnsCustomOpen = false;
        panel.pendingDnsProvider = provider;
        actionProc.command = [panel.binDir + "network-dns", provider];
        actionProc.running = true;
    }

    function applyCustomDns() {
        const servers = panel.dnsCustomText.trim();
        if (servers === "" || actionProc.running)
            return;
        panel.pendingDnsProvider = "Custom";
        actionProc.command = [panel.binDir + "network-dns", "Custom", servers];
        actionProc.running = true;
        panel.dnsCustomOpen = false;
        panel.refocusKeys();
    }

    // -------------------------------------------------------------- wifi
    property var wifiNetworks: []
    property bool scanning: false

    // Per-row in-flight state. `actionSsid` flips on for the row whose action
    // is running so it can render "Connecting…" / "Disconnecting…" /
    // "Forgetting…". `passwordSsid` is the row expanded into password entry;
    // it is kept open across refreshes so a slow scan doesn't collapse the
    // field being typed into. Rows gate comparisons on the matching
    // `*Kind`/`*Reason` being non-empty so a hidden-SSID row (ssid == "")
    // doesn't collide with the "" defaults.
    property string actionSsid: ""
    property string actionKind: ""   // "connect" | "disconnect" | "forget"
    property string failureSsid: ""
    property string failureReason: ""
    property string passwordSsid: ""
    property string passwordText: ""
    property string identityText: ""

    readonly property bool busy: actionKind !== ""

    function isProtected(security) {
        return Model.isProtected(security, WifiSecurityType.Open);
    }

    function isEnterprise(security) {
        return security === WifiSecurityType.Wpa2Eap || security === WifiSecurityType.WpaEap;
    }

    function canForgetNetwork(net) {
        return !!(net && net.known && panel.isProtected(net.security) && !net.connected);
    }

    function canShareNetwork(net) {
        if (!net || !net.connected)
            return false;
        return !panel.isEnterprise(net.security);
    }

    function syncWifiNetworks() {
        const nets = [];
        const networks = panel.wifiNetworkObjects || [];

        for (let i = 0; i < networks.length; i++) {
            const network = networks[i];
            if (!network)
                continue;
            panel.checkActionCompletion(network);
            const row = Model.wifiRow(network);
            if (row)
                nets.push(row);
        }
        panel.wifiNetworks = Model.sortWifiRows(nets);
        panel.wifiStationAvailable = !!panel.wifiDevice;
        panel.scanning = false;
    }

    function networkForSsid(ssid) {
        const networks = panel.wifiNetworkObjects || [];
        for (let i = 0; i < networks.length; i++) {
            if (networks[i] && networks[i].name === ssid)
                return networks[i];
        }
        return null;
    }

    function wifiIndexForSsid(ssid) {
        for (let i = 0; i < panel.wifiNetworks.length; i++) {
            if (panel.wifiNetworks[i] && panel.wifiNetworks[i].ssid === ssid)
                return i;
        }
        return -1;
    }

    function runNetworkAction(kind, network, callback) {
        if (panel.actionKind !== "" || !network)
            return;
        panel.actionSsid = network.name || "";
        panel.actionKind = kind;
        panel.failureSsid = "";
        panel.failureReason = "";
        callback(network);
        // Safety net: if the completion signal never arrives, clear the busy
        // state so the row doesn't sit on "Connecting…" forever.
        actionTimeout.restart();
    }

    function clearNetworkAction() {
        actionTimeout.stop();
        if (panel.actionKind === "connect")
            panel.passwordSsid = "";
        panel.failureSsid = "";
        panel.failureReason = "";
        panel.actionSsid = "";
        panel.actionKind = "";
        panel.refresh();
    }

    function failNetworkAction(network, reason) {
        if (!network || panel.actionKind === "" || panel.actionSsid !== (network.name || ""))
            return;
        actionTimeout.stop();
        panel.failureSsid = panel.actionSsid;
        panel.failureReason = Model.networkFailureReason(reason, {
            NoSecrets: ConnectionFailReason.NoSecrets,
            WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
            WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
            WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
            WifiClientFailed: ConnectionFailReason.WifiClientFailed
        });
        panel.actionSsid = "";
        panel.actionKind = "";
        panel.refresh();
    }

    function checkActionCompletion(network) {
        if (!network || panel.actionKind === "" || panel.actionSsid !== (network.name || ""))
            return;
        if (panel.actionKind === "connect" && network.connected)
            panel.clearNetworkAction();
        else if (panel.actionKind === "disconnect" && !network.connected && !network.stateChanging)
            panel.clearNetworkAction();
        else if (panel.actionKind === "forget" && !network.known && !network.stateChanging)
            panel.clearNetworkAction();
    }

    function connectKnown(ssid) {
        panel.runNetworkAction("connect", panel.networkForSsid(ssid), function (network) {
            network.connect();
        });
    }

    function connectWithPassphrase(ssid, passphrase) {
        panel.runNetworkAction("connect", panel.networkForSsid(ssid), function (network) {
            network.connectWithPsk(passphrase);
        });
    }

    function connectEnterprise(ssid, identity, passphrase) {
        panel.runNetworkAction("connect", panel.networkForSsid(ssid), function (network) {
            enterpriseConnect.secret = passphrase;
            enterpriseConnect.command = ["bash", "-c", Model.enterpriseConnectScript, "nmcli-eap", ssid, identity];
            enterpriseConnect.running = true;
        });
    }

    function disconnectNetwork(network) {
        panel.runNetworkAction("disconnect", network || panel.connectedWifiNetwork, function (net) {
            net.disconnect();
        });
    }

    function forgetNetwork(row) {
        panel.runNetworkAction("forget", row ? row.network : null, function (network) {
            network.forget();
        });
    }

    function openPasswordPrompt(ssid) {
        if (panel.passwordSsid !== ssid) {
            panel.passwordText = "";
            panel.identityText = "";
        }
        panel.passwordSsid = ssid;
    }

    function cancelPasswordPrompt() {
        panel.passwordSsid = "";
        panel.passwordText = "";
        panel.identityText = "";
    }

    function toggleWifi() {
        if (!panel.networkManagerAvailable)
            return;
        Networking.wifiEnabled = !Networking.wifiEnabled;
        Qt.callLater(function () {
            panel.refresh(true);
        });
    }

    // ------------------------------------------------------------ qr share
    property var qrRows: []
    property int qrSize: 0
    property string qrError: ""
    property bool qrLoading: false
    property bool qrExpectedStop: false
    property bool pendingQrShow: false
    property string qrPassword: ""
    property bool qrPasswordVisible: false
    property string qrPasswordError: ""
    // qrencode is not installed on every machine this repo restores onto; the
    // share button is hidden rather than offered and then failing.
    property bool qrencodePresent: false
    readonly property bool qrVisible: qrLoading || qrSize > 0 || qrError !== ""

    // The share and speed-test cards outlive the compact panel (their show
    // functions close it), so they take its place in the bar's
    // one-panel-at-a-time slot: the shell's close-every-panel sweep (run
    // before a typeable overlay maps) reaches their keyboard grab there.
    function grabOverlaySlot(overlay) {
        const bar = panel.anchorItem && panel.anchorItem.bar ? panel.anchorItem.bar : null;
        if (bar && bar.requestPanel)
            bar.requestPanel(overlay);
    }

    function releaseOverlaySlot(overlay) {
        const bar = panel.anchorItem && panel.anchorItem.bar ? panel.anchorItem.bar : null;
        if (bar && bar.releasePanel && bar.activePanel === overlay)
            bar.releasePanel(overlay);
    }

    function showWifiQr() {
        if (qrProc.running) {
            // A dismissal's SIGTERM is still in flight; Process.running stays
            // true until the child exits, so queue the reopen for onExited.
            if (panel.qrExpectedStop)
                panel.pendingQrShow = true;
            return;
        }
        panel.qrSize = 0;
        panel.qrRows = [];
        panel.qrError = "";
        panel.qrLoading = true;
        panel.qrExpectedStop = false;
        qrProc.command = panel.info.type === "wifi" && panel.info.iface ? [panel.binDir + "network-qr", panel.info.iface] : [panel.binDir + "network-qr"];
        qrProc.running = true;

        // Leave the compact panel behind while the centered share card is up.
        panel.close();
        panel.grabOverlaySlot(qrOverlay);
    }

    function hideWifiQr() {
        panel.releaseOverlaySlot(qrOverlay);
        panel.pendingQrShow = false;
        if (qrProc.running) {
            panel.qrExpectedStop = true;
            qrProc.running = false;
        }
        if (pwProc.running)
            pwProc.running = false;
        panel.qrSize = 0;
        panel.qrRows = [];
        panel.qrError = "";
        panel.qrLoading = false;
        panel.qrPassword = "";
        panel.qrPasswordVisible = false;
        panel.qrPasswordError = "";
    }

    function toggleQrPassword() {
        if (panel.qrPasswordVisible) {
            panel.qrPasswordVisible = false;
            return;
        }
        if (panel.qrPassword !== "") {
            panel.qrPasswordVisible = true;
            return;
        }
        if (pwProc.running)
            return;
        panel.qrPasswordError = "";
        pwProc.command = panel.info.iface ? [panel.binDir + "network-qr", "--password", panel.info.iface] : [panel.binDir + "network-qr", "--password"];
        pwProc.running = true;
    }

    // ----------------------------------------------------------- speed test
    property bool speedTestRunning: false
    property bool speedTestModalOpen: false
    property bool speedTestExpectedStop: false
    property bool pendingSpeedRun: false
    property string speedTestPhase: ""
    property string speedTestStderr: ""
    property string speedTestDownloadMbps: ""
    property string speedTestUploadMbps: ""
    property string speedTestError: ""
    readonly property bool canRunSpeedTest: !!info.iface

    function showSpeedTest() {
        if (!panel.speedTestModalOpen) {
            panel.speedTestModalOpen = true;
            panel.close();
            panel.grabOverlaySlot(speedTestOverlay);
        }
        panel.runSpeedTest();
    }

    function hideSpeedTest() {
        panel.releaseOverlaySlot(speedTestOverlay);
        panel.speedTestModalOpen = false;
        panel.pendingSpeedRun = false;
        speedTestPhaseTimer.stop();
        // Clear the phase before killing the process: onExited advances to the
        // upload phase when it still reads "down".
        panel.speedTestPhase = "";
        panel.speedTestRunning = false;
        if (speedTestProc.running) {
            panel.speedTestExpectedStop = true;
            speedTestProc.running = false;
        }
    }

    function runSpeedTest() {
        if (speedTestProc.running) {
            if (panel.speedTestExpectedStop)
                panel.pendingSpeedRun = true;
            return;
        }
        panel.speedTestError = "";
        panel.speedTestDownloadMbps = "";
        panel.speedTestUploadMbps = "";
        panel.speedTestRunning = true;
        panel.startSpeedTestPhase("down");
    }

    function startSpeedTestPhase(phase) {
        panel.speedTestExpectedStop = false;
        panel.speedTestPhase = phase;
        panel.speedTestStderr = "";
        speedTestProc.command = [panel.binDir + "network-speedtest", phase];
        speedTestProc.running = true;
        speedTestPhaseTimer.restart();
    }

    function stopSpeedTestPhase() {
        speedTestPhaseTimer.stop();
        if (speedTestProc.running) {
            panel.speedTestExpectedStop = true;
            speedTestProc.running = false;
            return;
        }
        panel.finishSpeedTestPhase();
    }

    function finishSpeedTestPhase() {
        if (panel.speedTestPhase === "down") {
            panel.startSpeedTestPhase("up");
            return;
        }
        panel.speedTestPhase = "";
        panel.speedTestRunning = false;
        panel.speedTestExpectedStop = false;
    }

    function updateSpeedTestLine(line) {
        const value = parseFloat(line);
        if (!isFinite(value) || value < 0)
            return;
        if (panel.speedTestPhase === "down")
            panel.speedTestDownloadMbps = String(value);
        else if (panel.speedTestPhase === "up")
            panel.speedTestUploadMbps = String(value);
        panel.speedTestError = "";
    }

    // -------------------------------------------------------------- refresh
    function refresh(scanWifi) {
        if (!detailsProc.running)
            detailsProc.running = true;
        if (!dnsProc.running) {
            dnsProc.command = [panel.binDir + "network-dns"];
            dnsProc.running = true;
        }
        if (!bandProc.running) {
            bandProc.command = [panel.binDir + "network-band"];
            bandProc.running = true;
        }
        // Sync before raising `scanning`: syncWifiNetworks clears the flag,
        // so the other order lowered it in the same call stack and the
        // "scanning" header could never appear.
        panel.syncWifiNetworks();
        if (panel.wifiDevice) {
            // Gated on `opened`: action callbacks (timeouts, connect
            // completions) land after the panel closes too, and must not
            // re-arm continuous background scanning.
            if (scanWifi === true && panel.opened) {
                panel.scanning = true;
                panel.wifiDevice.scannerEnabled = false;
                scanRestart.start();
            } else {
                panel.wifiDevice.scannerEnabled = panel.opened;
            }
        }
    }

    // -------------------------------------------------------------- cursor
    // Sections: "header" (QR / speed test / radio switch), "band" (Automatic
    // switch, then the pills), "dns" (four provider pills), "wifi" (the list).
    property string focusSection: "dns"
    property bool cursorActive: false
    property int headerIndex: 0
    property int bandIndex: 0
    property bool bandAutoFocused: true
    property int dnsIndex: 0
    property int selectedIndex: -1
    property bool wifiActionFocused: false

    readonly property bool canShareWifi: qrencodePresent && info.type === "wifi" && canShareNetwork(connectedWifiNetwork)
    // The hero switch is the Wi-Fi radio, so it only exists when there is a
    // radio to switch. On a wired box it would otherwise sit there reading
    // "off" beside a perfectly live Ethernet connection.
    readonly property bool canToggleWifi: networkManagerAvailable && wifiStationAvailable
    readonly property int qrHeaderIndex: canShareWifi ? 0 : -1
    readonly property int speedHeaderIndex: canRunSpeedTest ? (canShareWifi ? 1 : 0) : -1
    readonly property int toggleHeaderIndex: canToggleWifi ? (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) : -1
    readonly property int headerActionCount: (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) + (canToggleWifi ? 1 : 0)
    readonly property bool qrHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === qrHeaderIndex
    readonly property bool speedHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === speedHeaderIndex
    readonly property bool toggleHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === toggleHeaderIndex
    // While a text field owns input the cursor model freezes: the field wants
    // j/k/h/l as characters.
    readonly property bool keysBlocked: passwordSsid !== "" || dnsCustomOpen

    onHeaderActionCountChanged: panel.clampHeaderIndex()

    // Availability shifts as scans land, so the option list can shrink out
    // from under the cursor.
    onBandAvailableChanged: if (panel.bandIndex > panel.bandAvailable.length - 1)
        panel.bandIndex = Math.max(0, panel.bandAvailable.length - 1)

    onCanSelectBandChanged: {
        if (!panel.canSelectBand && panel.focusSection === "band") {
            panel.focusSection = "dns";
            panel.bandAutoFocused = true;
        }
    }

    onBandPillsVisibleChanged: if (!panel.bandPillsVisible)
        panel.bandAutoFocused = true

    onPasswordSsidChanged: {
        if (panel.passwordSsid === "" && panel.opened) {
            panel.passwordText = "";
            Qt.callLater(function () {
                panel.refocusKeys();
            });
        }
    }

    // Keep selectedIndex valid as scans refresh the list. If the list empties
    // (station gone, wifi off), bounce the cursor back to the DNS row so the
    // panel doesn't end up with no cursor at all.
    onWifiNetworksChanged: {
        if (panel.wifiNetworks.length === 0) {
            panel.selectedIndex = -1;
            panel.wifiActionFocused = false;
            if (panel.focusSection === "wifi")
                panel.focusSection = "dns";
        } else if (panel.passwordSsid !== "") {
            const passwordIndex = panel.wifiIndexForSsid(panel.passwordSsid);
            if (passwordIndex >= 0) {
                panel.selectedIndex = passwordIndex;
                panel.focusSection = "wifi";
            }
        } else if (panel.selectedIndex >= panel.wifiNetworks.length) {
            panel.selectedIndex = panel.wifiNetworks.length - 1;
        } else if (panel.selectedIndex < 0 && panel.opened) {
            panel.selectedIndex = 0;
        }

        if (panel.selectedIndex < 0 || panel.selectedIndex >= panel.wifiNetworks.length || !panel.canForgetNetwork(panel.wifiNetworks[panel.selectedIndex]))
            panel.wifiActionFocused = false;
    }

    onWifiDeviceChanged: {
        if (panel.wifiDevice)
            panel.wifiDevice.scannerEnabled = panel.opened;
        panel.syncWifiNetworks();
    }

    onWifiNetworkObjectsChanged: panel.syncWifiNetworks()

    function clampHeaderIndex() {
        const max = Math.max(0, panel.headerActionCount - 1);
        if (panel.headerIndex > max)
            panel.headerIndex = max;
        if (panel.headerIndex < 0)
            panel.headerIndex = 0;
    }

    function setHeaderCursor(index) {
        panel.cursorActive = true;
        panel.focusSection = "header";
        panel.headerIndex = index;
    }

    function setCursor(section, index) {
        panel.cursorActive = true;
        panel.focusSection = section;
        if (section === "dns")
            panel.dnsIndex = index;
        else if (section === "band")
            panel.bandIndex = index;
        else if (section === "wifi")
            panel.selectedIndex = index;
    }

    function activateHeader() {
        if (panel.headerIndex === panel.qrHeaderIndex)
            panel.showWifiQr();
        else if (panel.headerIndex === panel.speedHeaderIndex)
            panel.showSpeedTest();
        else if (panel.headerIndex === panel.toggleHeaderIndex)
            panel.toggleWifi();
    }

    function activateBand() {
        if (panel.bandAutoFocused) {
            panel.toggleBandAuto();
            return;
        }
        if (panel.bandIndex < 0 || panel.bandIndex >= panel.bandAvailable.length)
            return;
        panel.setBand(panel.bandAvailable[panel.bandIndex]);
    }

    function activateDns() {
        if (panel.dnsIndex < 0 || panel.dnsIndex >= panel.dnsProviders.length)
            return;
        panel.setDns(panel.dnsProviders[panel.dnsIndex]);
    }

    // Enter on the highlighted row. Mirrors row-click semantics: connected →
    // disconnect, protected-unknown → password prompt, open/known → connect.
    function activateSelected() {
        if (panel.busy || panel.selectedIndex < 0 || panel.selectedIndex >= panel.wifiNetworks.length)
            return;
        const net = panel.wifiNetworks[panel.selectedIndex];
        if (!net)
            return;
        if (panel.wifiActionFocused && panel.canForgetNetwork(net)) {
            panel.forgetNetwork(net);
            return;
        }
        if (net.connected) {
            panel.disconnectNetwork(net.network);
            return;
        }
        if (panel.isProtected(net.security) && !net.known) {
            panel.openPasswordPrompt(net.ssid);
            return;
        }
        panel.connectKnown(net.ssid);
    }

    function selectByDelta(delta) {
        if (panel.wifiNetworks.length === 0) {
            panel.selectedIndex = -1;
            return;
        }
        if (panel.selectedIndex < 0)
            panel.selectedIndex = delta > 0 ? 0 : panel.wifiNetworks.length - 1;
        else
            panel.selectedIndex = Math.max(0, Math.min(panel.wifiNetworks.length - 1, panel.selectedIndex + delta));
        panel.wifiActionFocused = false;
    }

    function selectWifiActionByDelta(delta) {
        if (panel.selectedIndex < 0 || panel.selectedIndex >= panel.wifiNetworks.length)
            return;
        if (!panel.canForgetNetwork(panel.wifiNetworks[panel.selectedIndex])) {
            panel.wifiActionFocused = false;
            return;
        }
        panel.wifiActionFocused = delta > 0;
    }

    // Park the cursor on the pinned band so opening highlights the pill the
    // user expects. Under Automatic there are no pills, so it belongs on the
    // switch.
    function syncBandIndex() {
        const idx = panel.bandAvailable.indexOf(panel.bandSelected);
        panel.bandIndex = idx >= 0 ? idx : 0;
        panel.bandAutoFocused = !panel.bandPillsVisible;
    }

    // Vertical order is header ⇄ band ⇄ DNS ⇄ wifi, with the band section
    // dropping out of the chain entirely when it isn't on screen.
    function moveVertical(dy) {
        if (panel.focusSection === "header") {
            if (dy > 0) {
                if (panel.canSelectBand) {
                    panel.focusSection = "band";
                    panel.bandAutoFocused = true;
                } else {
                    panel.focusSection = "dns";
                }
            }
            return;
        }
        if (panel.focusSection === "band") {
            if (dy < 0) {
                if (!panel.bandAutoFocused)
                    panel.bandAutoFocused = true;
                else if (panel.headerActionCount > 0) {
                    panel.focusSection = "header";
                    panel.headerIndex = 0;
                }
            } else if (panel.bandAutoFocused && panel.bandPillsVisible) {
                panel.bandAutoFocused = false;
            } else {
                panel.focusSection = "dns";
            }
            return;
        }
        if (panel.focusSection === "dns") {
            if (dy < 0) {
                if (panel.canSelectBand) {
                    panel.focusSection = "band";
                    panel.bandAutoFocused = !panel.bandPillsVisible;
                } else if (panel.headerActionCount > 0) {
                    panel.focusSection = "header";
                    panel.headerIndex = 0;
                }
            } else if (panel.wifiNetworks.length > 0) {
                panel.focusSection = "wifi";
                if (panel.selectedIndex < 0)
                    panel.selectedIndex = 0;
            }
            return;
        }
        // wifi: k from the top row escapes back up to the DNS row rather than
        // wrapping to the bottom of the list.
        if (dy < 0 && panel.selectedIndex <= 0) {
            panel.focusSection = "dns";
            panel.wifiActionFocused = false;
        } else {
            panel.selectByDelta(dy);
        }
    }

    function moveHorizontal(dx) {
        if (panel.focusSection === "header")
            panel.headerIndex = Math.max(0, Math.min(panel.headerActionCount - 1, panel.headerIndex + dx));
        else if (panel.focusSection === "band") {
            if (!panel.bandAutoFocused)
                panel.bandIndex = Math.max(0, Math.min(panel.bandAvailable.length - 1, panel.bandIndex + dx));
        } else if (panel.focusSection === "dns")
            panel.dnsIndex = Math.max(0, Math.min(panel.dnsProviders.length - 1, panel.dnsIndex + dx));
        else if (panel.focusSection === "wifi")
            panel.selectWifiActionByDelta(dx);
    }

    // The first arrow press only reveals the cursor, as theirs does.
    function moveRequest(dx, dy) {
        if (!panel.cursorActive) {
            panel.cursorActive = true;
            if (dy >= 0)
                return;
        }
        if (dy !== 0)
            panel.moveVertical(dy);
        if (dx !== 0)
            panel.moveHorizontal(dx);
    }

    function activateCursor() {
        if (!panel.cursorActive) {
            panel.cursorActive = true;
            return;
        }
        if (panel.focusSection === "header")
            panel.activateHeader();
        else if (panel.focusSection === "band")
            panel.activateBand();
        else if (panel.focusSection === "dns")
            panel.activateDns();
        else
            panel.activateSelected();
    }

    onContentKey: event => {
        if (panel.keysBlocked)
            return;
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            panel.moveRequest(0, 1);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            panel.moveRequest(0, -1);
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            panel.moveRequest(1, 0);
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            panel.moveRequest(-1, 0);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            panel.activateCursor();
            break;
        case Qt.Key_R:
            panel.refresh(true);
            break;
        case Qt.Key_W:
            panel.toggleWifi();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // Keep the keyboard-focused row inside the viewport.
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

    // ---------------------------------------------------------- lifecycle
    onPanelOpened: {
        panel.refresh(true);
        panel.cancelPasswordPrompt();
        panel.dnsCustomOpen = false;
        panel.selectedIndex = panel.wifiNetworks.length > 0 ? 0 : -1;
        panel.wifiActionFocused = false;
        panel.focusSection = panel.wifiNetworks.length > 0 ? "wifi" : "dns";
        const idx = panel.dnsProviders.indexOf(panel.dnsProvider);
        panel.dnsIndex = idx >= 0 ? idx : 0;
        panel.syncBandIndex();
        panel.cursorActive = false;
        scroller.contentY = 0;
        if (!qrencodeProbe.running)
            qrencodeProbe.running = true;
    }

    onPanelClosed: {
        // Reset throughput tracking so the next open doesn't compute a fake
        // rate from a sample taken minutes ago.
        panel.prevSampleTime = 0;
        panel.downloadRate = 0;
        panel.uploadRate = 0;
        panel.pingIface = "";
        panel.routerPingSamples = [];
        panel.internetPingSamples = [];
        panel.routerPingLatency = -1;
        panel.internetPingLatency = -1;
        panel.internetPingPacketLoss = 0;
        panel.cancelPasswordPrompt();
        panel.dnsCustomOpen = false;
        if (panel.wifiDevice)
            panel.wifiDevice.scannerEnabled = false;
    }

    // ------------------------------------------------------------ processes
    Process {
        id: qrencodeProbe
        command: ["bash", "-c", "command -v qrencode >/dev/null"]
        onExited: exitCode => panel.qrencodePresent = exitCode === 0
    }

    // Pulls everything about the active route's interface in one shot.
    Process {
        id: detailsProc
        command: [panel.binDir + "network-status", "--verbose"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.updateDetails(text)
        }
    }

    Process {
        id: dnsProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.updateDns(text)
        }
    }

    Process {
        id: bandProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.updateBand(text)
        }
    }

    // Action runner for band and DNS changes. Wi-Fi actions go through the
    // NetworkManager backend directly.
    Process {
        id: actionProc
        onExited: exitCode => {
            if (panel.pendingDnsProvider !== "") {
                if (exitCode === 0)
                    panel.dnsProvider = panel.pendingDnsProvider;
                panel.pendingDnsProvider = "";
                if (!dnsProc.running) {
                    dnsProc.command = [panel.binDir + "network-dns"];
                    dnsProc.running = true;
                }
            }
            if (panel.pendingBand !== "") {
                // A refused or reverted pin leaves bandSelected alone, so the
                // pills keep showing what is actually in force.
                if (exitCode === 0)
                    panel.bandSelected = panel.pendingBand;
                panel.pendingBand = "";
                panel.refresh();
            }
        }
    }

    // Creates and activates the 802.1X profile (see NetworkModel.js). The
    // password goes over stdin, never argv.
    Process {
        id: enterpriseConnect

        property string secret: ""

        stdinEnabled: true
        onStarted: {
            write(secret + "\n");
            secret = "";
        }
    }

    Process {
        id: qrProc
        // Both collectors check qrExpectedStop: a dismissal mid-generation
        // kills the process, but buffered output still arrives afterwards and
        // would repopulate qrSize — reopening the card just closed.
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (!panel.qrExpectedStop) {
                const matrix = Model.parseQrMatrix(text);
                panel.qrRows = matrix.rows;
                panel.qrSize = matrix.size;
            }
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (!panel.qrExpectedStop)
                panel.qrError = String(text || "").trim()
        }
        onExited: exitCode => {
            panel.qrLoading = false;
            if (panel.pendingQrShow) {
                panel.pendingQrShow = false;
                panel.qrExpectedStop = false;
                Qt.callLater(function () {
                    panel.showWifiQr();
                });
                return;
            }
            if (panel.qrExpectedStop)
                return;
            if (exitCode !== 0 || panel.qrSize === 0) {
                panel.qrSize = 0;
                panel.qrRows = [];
                if (panel.qrError === "")
                    panel.qrError = "Could not generate the Wi-Fi QR code";
            }
        }
    }

    // The Wi-Fi password only enters shell memory when the user clicks to
    // reveal it, and hideWifiQr drops it again when the share card closes.
    Process {
        id: pwProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (panel.qrVisible)
                panel.qrPassword = String(text || "").trim()
        }
        onExited: exitCode => {
            if (!panel.qrVisible)
                return;
            if (exitCode === 0 && panel.qrPassword !== "")
                panel.qrPasswordVisible = true;
            else
                panel.qrPasswordError = "Could not read the Wi-Fi password";
        }
    }

    Process {
        id: speedTestProc
        stdout: SplitParser {
            onRead: line => panel.updateSpeedTestLine(line)
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.speedTestStderr = String(text || "").trim()
        }
        onExited: exitCode => {
            speedTestPhaseTimer.stop();

            if (panel.pendingSpeedRun) {
                panel.pendingSpeedRun = false;
                panel.speedTestExpectedStop = false;
                if (panel.speedTestModalOpen)
                    Qt.callLater(function () {
                        panel.runSpeedTest();
                    });
                return;
            }

            if (!panel.speedTestExpectedStop && exitCode !== 0) {
                panel.speedTestError = panel.speedTestStderr || "Speed test failed";
                panel.speedTestPhase = "";
                panel.speedTestRunning = false;
                return;
            }

            panel.speedTestExpectedStop = false;
            panel.finishSpeedTestPhase();
        }
    }

    // --------------------------------------------------------------- timers
    // Everything below only ticks while the card is on screen.
    Timer {
        id: detailsPoll
        interval: 1500
        repeat: true
        running: panel.opened
        onTriggered: if (!detailsProc.running)
            detailsProc.running = true
    }

    // Slower on purpose: this shells out to nmcli several times, and band
    // availability only moves when a scan turns up a new BSSID.
    Timer {
        id: bandPoll
        interval: 4000
        repeat: true
        running: panel.opened
        onTriggered: {
            if (bandProc.running)
                return;
            bandProc.command = [panel.binDir + "network-band"];
            bandProc.running = true;
        }
    }

    Timer {
        id: scanRestart
        interval: 100
        onTriggered: {
            // The panel can close inside this window; onPanelClosed already
            // disarmed the scanner and this must not re-arm it.
            if (panel.wifiDevice)
                panel.wifiDevice.scannerEnabled = panel.opened;
            scanDone.start();
        }
    }

    Timer {
        id: scanDone
        interval: 1500
        onTriggered: panel.syncWifiNetworks()
    }

    Timer {
        id: speedTestPhaseTimer
        interval: 5000
        onTriggered: panel.stopSpeedTestPhase()
    }

    Timer {
        id: actionTimeout
        interval: 15000
        onTriggered: {
            if (!panel.actionKind)
                return;
            panel.failureSsid = panel.actionSsid;
            panel.failureReason = panel.actionKind === "connect" ? "Timed out connecting" : panel.actionKind === "disconnect" ? "Timed out disconnecting" : "Timed out forgetting";
            panel.actionSsid = "";
            panel.actionKind = "";
            panel.refresh();
        }
    }

    PhraseRotator {
        theme: panel.theme
        target: heroMeta
        running: panel.opened && (panel.info.type === "ethernet" || (panel.info.type === "wifi" && !!panel.connectedWifiNetwork))
        onAdvance: panel.connectionPhraseIndex = (panel.connectionPhraseIndex + 1) % panel.connectionPhrases.length
    }

    // ------------------------------------------------------------ overlays
    NetworkQrPanel {
        id: qrOverlay
        theme: panel.theme
        qrRows: panel.qrRows
        qrSize: panel.qrSize
        loading: panel.qrLoading
        error: panel.qrError
        ssid: panel.info.ssid || ""
        secured: panel.connectedWifiNetwork ? panel.isProtected(panel.connectedWifiNetwork.security) : false
        password: panel.qrPassword
        passwordVisible: panel.qrPasswordVisible
        passwordError: panel.qrPasswordError
        opened: panel.qrVisible
        onCloseRequested: panel.hideWifiQr()
        onPasswordToggleRequested: panel.toggleQrPassword()
    }

    NetworkSpeedTestPanel {
        id: speedTestOverlay
        theme: panel.theme
        running: panel.speedTestRunning
        phase: panel.speedTestPhase
        downloadMbps: panel.speedTestDownloadMbps
        uploadMbps: panel.speedTestUploadMbps
        error: panel.speedTestError
        connectionName: {
            if (panel.info.type === "wifi")
                return panel.info.ssid || "Wi-Fi";
            if (panel.info.type === "ethernet")
                return "Ethernet";
            return "";
        }
        opened: panel.speedTestModalOpen
        onCloseRequested: panel.hideSpeedTest()
        onRunAgainRequested: panel.runSpeedTest()
    }

    // ------------------------------------------------------------- content
    Flickable {
        id: scroller

        width: parent.width
        // Capped like their popup: a busy neighbourhood scrolls inside the
        // card instead of stretching it down the whole screen.
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

            // -------------------------------------------------------- hero
            Item {
                id: hero

                width: parent.width
                implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroActions.implicitHeight)

                OpticalGlyph {
                    id: heroIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.kind === "ethernet" ? "󰈀" : panel.kind === "wifi" ? Model.wifiIconFor(Model.signalPercent(panel.connectedWifiNetwork)) : "󰤮"
                    color: panel.theme.textPrimary
                    opacity: panel.networkManagerAvailable ? 1 : 0.5
                    pixelSize: panel.theme.fontPx(1.6)
                }

                Row {
                    id: heroActions

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(2)

                    HeroAction {
                        visible: panel.canShareWifi
                        glyph: "󰐲"
                        hint: "Show QR code"
                        hasCursor: panel.qrHeaderHasCursor
                        onHovered: panel.setHeaderCursor(panel.qrHeaderIndex)
                        onActivated: panel.showWifiQr()
                    }

                    HeroAction {
                        visible: panel.canRunSpeedTest
                        glyph: "󰓅"
                        hint: "Run a speed test"
                        hasCursor: panel.speedHeaderHasCursor
                        onHovered: panel.setHeaderCursor(panel.speedHeaderIndex)
                        onActivated: panel.showSpeedTest()
                    }

                    PanelSwitch {
                        theme: panel.theme
                        anchors.verticalCenter: parent.verticalCenter
                        visible: panel.canToggleWifi
                        checked: Networking.wifiEnabled
                        hasCursor: panel.toggleHeaderHasCursor
                        hint: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
                        onHovered: panel.setHeaderCursor(panel.toggleHeaderIndex)
                        onToggled: panel.toggleWifi()
                    }
                }

                Column {
                    id: heroLabels

                    anchors.left: heroIcon.right
                    anchors.leftMargin: panel.theme.space(3)
                    anchors.right: heroActions.left
                    anchors.rightMargin: panel.theme.space(3)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(0.5)

                    Text {
                        readonly property string title: {
                            if (panel.info.type === "wifi")
                                return panel.info.ssid || "Wi-Fi";
                            if (panel.info.type === "ethernet")
                                return "Ethernet";
                            return panel.info.iface || (panel.kind === "disconnected" ? "Disconnected" : "No connection");
                        }
                        // Link detail rides inline after the name —
                        // "Ethernet (2.5gbit)" — rather than in a pill.
                        readonly property string detail: Model.headerDetail(panel.info)

                        width: parent.width
                        text: detail !== "" ? title + " (" + detail + ")" : title
                        color: panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(1.083)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        id: heroMeta

                        width: parent.width
                        text: {
                            if (panel.info.type === "wifi")
                                return panel.connectedWifiNetwork ? panel.connectionPhrase.toUpperCase() : (panel.kind === "disconnected" ? "NOT CONNECTED" : "");
                            if (panel.info.type === "ethernet")
                                return panel.connectionPhrase.toUpperCase();
                            return panel.kind === "disconnected" ? "NOT CONNECTED" : "";
                        }
                        visible: text !== ""
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontMono
                        font.pixelSize: panel.theme.fontPx(0.75)
                        font.letterSpacing: 1.2
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }

            // ------------------------------------------------------- stats
            Column {
                width: parent.width
                spacing: panel.theme.space(1)
                visible: !!panel.info.iface

                StatRow {
                    leftLabel: "Ping"
                    leftValue: Model.formatPingLatency(panel.internetPingLatency, panel.hasInternetPing)
                    leftAlert: panel.internetPingPacketLoss > 0
                    leftHint: "Router " + Model.formatPingLatency(panel.routerPingLatency, panel.routerPingSamples.length > 0)
                    rightLabel: "Packet Loss"
                    rightValue: Model.formatPacketLoss(panel.internetPingPacketLoss, panel.hasInternetPing)
                    rightAlert: panel.internetPingPacketLoss > 0
                }

                StatRow {
                    leftLabel: "Receiving"
                    leftValue: panel.hasTransferStats ? Model.formatRate(panel.downloadRate) : "--"
                    rightLabel: "Sending"
                    rightValue: panel.hasTransferStats ? Model.formatRate(panel.uploadRate) : "--"
                }

                StatRow {
                    leftLabel: "Downloaded"
                    leftValue: panel.hasTransferStats ? Model.formatBytes(parseFloat(panel.info.rx_bytes || "0")) : "--"
                    rightLabel: "Uploaded"
                    rightValue: panel.hasTransferStats ? Model.formatBytes(parseFloat(panel.info.tx_bytes || "0")) : "--"
                }

                StatRow {
                    leftLabel: "IP Address"
                    leftValue: panel.info.ip || "--"
                    leftCopyable: !!panel.info.ip
                    rightLabel: "Gateway"
                    rightValue: panel.info.gateway || "--"
                    rightCopyable: !!panel.info.gateway
                }
            }

            // -------------------------------------------------------- band
            Separator {
                theme: panel.theme
                visible: panel.canSelectBand
            }

            Column {
                width: parent.width
                spacing: panel.theme.space(1.5)
                visible: panel.canSelectBand

                // "Automatic" rides on the header line rather than under the
                // pills: it qualifies the whole row, and at header scale it
                // reads as a modifier instead of competing with the band
                // choices for attention.
                Item {
                    width: parent.width
                    implicitHeight: Math.max(bandHeader.implicitHeight, bandAutoRow.implicitHeight)

                    SectionHeader {
                        id: bandHeader
                        theme: panel.theme
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        label: panel.bandSectionTitle
                    }

                    Row {
                        id: bandAutoRow

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: panel.theme.space(1.5)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "AUTOMATIC"
                            color: panel.theme.textMuted
                            font.family: panel.theme.fontMono
                            font.pixelSize: panel.theme.fontPx(0.75)
                            font.letterSpacing: 1.2
                            font.weight: Font.DemiBold
                        }

                        PanelSwitch {
                            theme: panel.theme
                            anchors.verticalCenter: parent.verticalCenter
                            compact: true
                            checked: !panel.bandPinned
                            busy: panel.bandBusy
                            hasCursor: panel.cursorActive && panel.focusSection === "band" && panel.bandAutoFocused
                            hint: panel.bandPinned ? "Let Wi-Fi pick the band" : "Stay on " + Model.bandLabel(panel.bandCurrent)
                            onHovered: {
                                panel.cursorActive = true;
                                panel.focusSection = "band";
                                panel.bandAutoFocused = true;
                            }
                            onToggled: panel.toggleBandAuto()
                        }
                    }
                }

                // Collapsing container: the pills animate their height so
                // toggling Automatic slides the sections below into place
                // instead of snapping. `visible` only drops at a real zero.
                Item {
                    id: bandPillsClip

                    width: parent.width
                    clip: true
                    visible: height > 0
                    height: panel.bandPillsVisible ? bandRow.implicitHeight : 0
                    opacity: panel.bandPillsVisible ? 1 : 0

                    Behavior on height {
                        NumberAnimation {
                            duration: panel.theme.time(1)
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: panel.theme.time(1)
                            easing.type: Easing.OutCubic
                        }
                    }

                    Row {
                        id: bandRow

                        readonly property int count: Math.max(1, panel.bandAvailable.length)
                        readonly property real cellWidth: (width - spacing * (count - 1)) / count

                        width: parent.width
                        spacing: panel.theme.space(1.5)

                        Repeater {
                            model: panel.bandAvailable

                            // The wrapper takes modelData/index from the
                            // delegate context, which does not bind into
                            // nested `component` declarations.
                            Item {
                                required property var modelData
                                required property int index

                                width: bandRow.cellWidth
                                height: bandPill.implicitHeight

                                Pill {
                                    id: bandPill

                                    width: parent.width
                                    label: Model.bandLabel(parent.modelData)
                                    hint: Model.bandTooltip(parent.modelData)
                                    // `current` (fill) is the band actually in
                                    // use, `selected` (bold) the pinned one;
                                    // under Automatic nothing is pinned.
                                    current: panel.bandCurrent === parent.modelData
                                    selected: panel.bandEffective === parent.modelData
                                    hasCursor: panel.cursorActive && panel.focusSection === "band" && !panel.bandAutoFocused && panel.bandIndex === parent.index
                                    onHovered: {
                                        panel.cursorActive = true;
                                        panel.focusSection = "band";
                                        panel.bandIndex = parent.index;
                                        panel.bandAutoFocused = false;
                                    }
                                    onActivated: panel.setBand(parent.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // --------------------------------------------------------- dns
            Separator {
                theme: panel.theme
            }

            Column {
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "DNS PROVIDER"
                    value: panel.pendingDnsProvider !== "" ? "APPLYING…" : ""
                    valueColor: panel.theme.textMuted
                    valueSpacing: 1.2
                }

                Row {
                    id: dnsRow

                    readonly property real cellWidth: (width - spacing * 3) / 4

                    width: parent.width
                    spacing: panel.theme.space(1.5)

                    Repeater {
                        model: panel.dnsProviders

                        Item {
                            required property var modelData
                            required property int index

                            width: dnsRow.cellWidth
                            height: dnsPill.implicitHeight

                            Pill {
                                id: dnsPill

                                width: parent.width
                                label: parent.modelData
                                hint: parent.modelData === "DHCP" ? "Use DNS from DHCP" : parent.modelData === "Custom" ? "Set custom DNS servers" : "Set DNS to " + parent.modelData
                                current: panel.dnsProvider === parent.modelData
                                hasCursor: panel.cursorActive && panel.focusSection === "dns" && panel.dnsIndex === parent.index
                                onHovered: panel.setCursor("dns", parent.index)
                                onActivated: panel.setDns(parent.modelData)
                            }
                        }
                    }
                }

                // Inline custom-server entry. NetworkManager holds the values,
                // so nothing about DNS is persisted in shell.json.
                Row {
                    width: parent.width
                    spacing: panel.theme.space(1.5)
                    visible: panel.dnsCustomOpen

                    PanelTextField {
                        id: dnsField

                        theme: panel.theme

                        width: parent.width - dnsApply.width - panel.theme.space(1.5)
                        placeholder: "1.1.1.1 9.9.9.9"
                        focusWhen: panel.dnsCustomOpen
                        onTextEdited: text => panel.dnsCustomText = text
                        onAccepted: panel.applyCustomDns()
                        onCancelled: {
                            panel.dnsCustomOpen = false;
                            panel.refocusKeys();
                        }
                    }

                    PanelButton {
                        id: dnsApply
                        anchors.verticalCenter: parent.verticalCenter
                        theme: panel.theme
                        label: "Apply"
                        enabled: panel.dnsCustomText.trim() !== ""
                        onClicked: panel.applyCustomDns()
                    }
                }
            }

            // -------------------------------------------------------- wifi
            Separator {
                theme: panel.theme
                visible: panel.wifiStationAvailable
            }

            Column {
                width: parent.width
                spacing: panel.theme.space(1)
                visible: panel.wifiStationAvailable

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    visible: panel.scanning
                    label: "SCANNING WI-FI…"
                }

                Repeater {
                    model: panel.wifiNetworks

                    Column {
                        required property var modelData
                        required property int index

                        readonly property string sectionTitle: Model.wifiSectionTitle(panel.wifiNetworks, index)

                        width: sections.width
                        spacing: panel.theme.space(1)

                        SectionHeader {
                            theme: panel.theme
                            width: parent.width
                            visible: parent.sectionTitle !== ""
                            height: visible ? implicitHeight : 0
                            label: parent.sectionTitle
                        }

                        NetworkRow {
                            width: parent.width
                            net: parent.modelData
                            rowIndex: parent.index
                        }
                    }
                }

                Text {
                    visible: panel.wifiNetworks.length === 0
                    text: Networking.wifiEnabled ? "Scanning…" : "Wi-Fi is off"
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                }
            }
        }
    }

    // ---------------------------------------------------------- components
    // A pair of label/value pairs on one line, which is how their GridLayout
    // reads at this width: two columns, value right-aligned in each.
    component StatRow: Item {
        id: statRow

        property string leftLabel: ""
        property string leftValue: ""
        property bool leftAlert: false
        property bool leftCopyable: false
        property string leftHint: ""
        property string rightLabel: ""
        property string rightValue: ""
        property bool rightAlert: false
        property bool rightCopyable: false
        property string rightHint: ""

        width: sections.width
        implicitHeight: leftCell.implicitHeight

        StatCell {
            id: leftCell
            anchors.left: parent.left
            width: (parent.width - panel.theme.space(4)) / 2
            label: statRow.leftLabel
            value: statRow.leftValue
            alert: statRow.leftAlert
            copyable: statRow.leftCopyable
            hint: statRow.leftHint
        }

        StatCell {
            anchors.right: parent.right
            width: (parent.width - panel.theme.space(4)) / 2
            label: statRow.rightLabel
            value: statRow.rightValue
            alert: statRow.rightAlert
            copyable: statRow.rightCopyable
            hint: statRow.rightHint
        }
    }

    component StatCell: Item {
        id: cell

        property string label: ""
        property string value: ""
        property bool alert: false
        property bool copyable: false
        // Their grid reports the internet probe only; the helper measures the
        // gateway in the same pass, so it rides along as a hint rather than
        // taking a row of its own.
        property string hint: ""

        implicitHeight: Math.max(cellLabel.implicitHeight, cellValue.implicitHeight)

        HoverHandler {
            id: cellHover
            enabled: cell.hint !== "" || cell.copyable
        }

        PanelHint {
            theme: panel.theme
            visible: cellHover.hovered && (cell.hint !== "" || cell.copyable)
            anchor: cell
            text: cell.hint !== "" ? cell.hint : "Click to copy"
        }

        Text {
            id: cellLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: cell.label
            color: panel.theme.textMuted
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.833)
        }

        Text {
            id: cellValue
            anchors.right: parent.right
            anchors.left: cellLabel.right
            anchors.leftMargin: panel.theme.space(1)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: cell.value
            color: cell.alert ? panel.theme.error : panel.theme.textPrimary
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.833)

            // Click an address to copy it, as their DetailValue does.
            MouseArea {
                anchors.fill: parent
                enabled: cell.copyable && cell.value !== ""
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" | wl-copy", "wl-copy", cell.value])
            }
        }
    }

    // Hero icon action (QR, speed test).
    component HeroAction: CursorSurface {
        id: heroAction

        theme: panel.theme

        property string glyph: ""
        property string hint: ""

        signal hovered
        signal activated

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: panel.theme.space(8)
        implicitHeight: panel.theme.space(7)

        OpticalGlyph {
            anchors.centerIn: parent
            text: heroAction.glyph
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(1.15)
        }

        HoverHandler {
            id: heroHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                heroAction.hovered()
        }

        TapHandler {
            onTapped: heroAction.activated()
        }

        PanelHint {
            theme: panel.theme
            visible: heroHover.hovered
            anchor: heroAction
            text: heroAction.hint
        }
    }

    // Their ToggleSwitch: a track with a knob, cursor-aware, with the busy
    // state dimming it while a change is in flight.
    // A band or DNS choice.
    component Pill: CursorSurface {
        id: pill

        theme: panel.theme

        property string label: ""
        property string hint: ""
        property bool selected: false

        signal hovered
        signal activated

        implicitHeight: panel.theme.space(7)

        Text {
            anchors.centerIn: parent
            width: parent.width - panel.theme.space(2)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: pill.label
            color: pill.current || pill.selected ? panel.theme.accent : panel.theme.textPrimary
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.833)
            font.weight: pill.selected ? Font.DemiBold : Font.Normal
        }

        HoverHandler {
            id: pillHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                pill.hovered()
        }

        TapHandler {
            onTapped: pill.activated()
        }

        PanelHint {
            theme: panel.theme
            visible: pillHover.hovered && pill.hint !== ""
            anchor: pill
            text: pill.hint
        }
    }

    // A single Wi-Fi network. Collapses to one line normally; expands inline
    // into a passphrase prompt when a protected network has no credentials
    // yet. Clicking a connected row disconnects.
    component NetworkRow: CursorSurface {
        id: row

        theme: panel.theme

        required property var net
        required property int rowIndex

        readonly property bool isConnected: !!(net && net.connected)
        readonly property bool isKnown: !!(net && net.known)
        readonly property bool isSecured: net ? panel.isProtected(net.security) : false
        readonly property bool isEnterprise: net ? panel.isEnterprise(net.security) : false
        readonly property bool canForget: isKnown && isSecured && !isConnected
        readonly property bool isSelected: panel.focusSection === "wifi" && panel.selectedIndex === rowIndex
        readonly property bool forgetFocused: isSelected && panel.wifiActionFocused && canForget
        readonly property bool forgetVisible: canForget && (forgetFocused || forgetHover.hovered)
        readonly property bool isBusy: panel.actionKind !== "" && panel.actionSsid === (net ? net.ssid : "")
        readonly property bool isFailed: panel.failureReason !== "" && panel.failureSsid === (net ? net.ssid : "")
        readonly property bool isPasswordOpen: panel.passwordSsid !== "" && panel.passwordSsid === (net ? net.ssid : "")

        readonly property string statusText: {
            if (!net || isPasswordOpen)
                return "";
            if (isBusy && panel.actionKind === "connect")
                return "Connecting…";
            if (isBusy && panel.actionKind === "disconnect")
                return "Disconnecting…";
            if (isBusy && panel.actionKind === "forget")
                return "Forgetting…";
            if (isFailed)
                return panel.failureReason || "Failed";
            if (isConnected)
                return "Connected";
            return "";
        }

        readonly property color statusColor: {
            if (isFailed)
                return panel.theme.error;
            if (isConnected)
                return panel.theme.accent;
            return panel.theme.textMuted;
        }

        function submitCredentials() {
            if (!net || panel.busy || panel.passwordText.length === 0)
                return;
            if (!isEnterprise) {
                panel.connectWithPassphrase(net.ssid, panel.passwordText);
                return;
            }
            if (panel.identityText.length > 0)
                panel.connectEnterprise(net.ssid, panel.identityText, panel.passwordText);
        }

        hasCursor: panel.cursorActive && isSelected && !panel.wifiActionFocused
        current: isConnected
        implicitHeight: rowBody.implicitHeight + (isPasswordOpen ? passwordPanel.implicitHeight + panel.theme.space(2) : 0)
        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(row)

        Connections {
            target: row.net ? row.net.network : null

            function onConnectionFailed(reason) {
                panel.failNetworkAction(row.net.network, reason);
                if (reason === ConnectionFailReason.NoSecrets)
                    panel.openPasswordPrompt(row.net.ssid);
            }

            function onConnectedChanged() {
                if (row.net)
                    panel.checkActionCompletion(row.net.network);
            }

            function onKnownChanged() {
                if (row.net)
                    panel.checkActionCompletion(row.net.network);
            }

            function onStateChangingChanged() {
                if (row.net)
                    panel.checkActionCompletion(row.net.network);
            }
        }

        Item {
            id: rowBody

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(networkIcon.implicitHeight, networkInfo.implicitHeight, rightAction.implicitHeight) + panel.theme.space(3)

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !panel.busy
                // Mouse leaving doesn't clear the cursor, so j/k pick up from
                // the row the pointer last visited.
                onContainsMouseChanged: if (containsMouse) {
                    panel.setCursor("wifi", row.rowIndex);
                    panel.wifiActionFocused = false;
                }
                onClicked: {
                    if (!row.net)
                        return;
                    panel.setCursor("wifi", row.rowIndex);
                    panel.wifiActionFocused = false;
                    if (row.isConnected) {
                        panel.disconnectNetwork(row.net.network);
                        return;
                    }
                    if (row.isSecured && !row.isKnown) {
                        panel.openPasswordPrompt(row.net.ssid);
                        return;
                    }
                    panel.connectKnown(row.net.ssid);
                }
            }

            OpticalGlyph {
                id: networkIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: row.net ? Model.wifiIconFor(row.net.signal) : ""
                color: row.isConnected ? panel.theme.accent : panel.theme.textPrimary
                pixelSize: panel.theme.fontPx(1.083)
            }

            // Lock glyph for protected networks; a known disconnected network
            // reveals the forget action on that same right edge.
            Item {
                id: rightAction

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: row.isSecured
                width: panel.theme.space(5.5)
                implicitHeight: panel.theme.space(5.5)

                Rectangle {
                    anchors.fill: parent
                    visible: row.forgetFocused
                    radius: panel.theme.radius(0.75)
                    color: panel.theme.alpha(panel.theme.error, 0.15)
                    border.width: panel.theme.borderWidth
                    border.color: panel.theme.error
                }

                OpticalGlyph {
                    anchors.centerIn: parent
                    text: row.forgetVisible ? "󰅙" : "󰌾"
                    color: row.forgetVisible ? panel.theme.error : panel.theme.textMuted
                    pixelSize: panel.theme.fontPx(0.917)
                }

                MouseArea {
                    id: forgetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: row.canForget && !panel.busy
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onContainsMouseChanged: if (containsMouse) {
                        panel.setCursor("wifi", row.rowIndex);
                        panel.wifiActionFocused = true;
                    }
                    onClicked: if (row.net)
                        panel.forgetNetwork(row.net)
                }

                HoverHandler {
                    id: forgetHover
                    enabled: row.canForget
                }

                PanelHint {
                    theme: panel.theme
                    visible: forgetMouse.containsMouse && row.canForget
                    anchor: rightAction
                    text: "Forget network"
                }
            }

            Column {
                id: networkInfo

                anchors.left: networkIcon.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: rightAction.visible ? rightAction.left : parent.right
                anchors.rightMargin: rightAction.visible ? panel.theme.space(2) : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    width: parent.width
                    text: row.net ? (row.net.ssid || "Hidden") : ""
                    color: row.isConnected ? panel.theme.accent : panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    font.weight: row.isConnected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                // Signal strength is carried by the icon and the right edge
                // carries the lock, so the second line is action status only.
                // It collapses to zero height when empty.
                Text {
                    width: parent.width
                    visible: row.statusText !== ""
                    height: visible ? implicitHeight : 0
                    text: row.statusText
                    color: row.statusColor
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.75)
                    elide: Text.ElideRight
                }
            }
        }

        // Inline passphrase prompt. Submitting (Enter or the check button)
        // fires connect; Esc cancels back to the row.
        Item {
            id: passwordPanel

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: rowBody.bottom
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            visible: row.isPasswordOpen
            implicitHeight: (idField.visible ? idField.implicitHeight + panel.theme.space(1.5) : 0) + pwField.implicitHeight + panel.theme.space(2)

            PanelTextField {
                id: idField

                theme: panel.theme

                anchors.left: parent.left
                anchors.right: connectButton.left
                anchors.top: parent.top
                anchors.rightMargin: panel.theme.space(1.5)
                visible: row.isEnterprise && !row.isBusy && !row.isFailed
                placeholder: "Identity (user@domain)"
                focusWhen: row.isPasswordOpen && row.isEnterprise
                onTextEdited: text => {
                    if (row.isPasswordOpen)
                        panel.identityText = text;
                }
                onAccepted: pwField.forceFocus()
                onCancelled: panel.cancelPasswordPrompt()
            }

            PanelTextField {
                id: pwField

                theme: panel.theme

                function forceFocus() {
                    focusWhen = false;
                    focusWhen = true;
                }

                anchors.left: parent.left
                anchors.right: connectButton.left
                anchors.top: idField.visible ? idField.bottom : parent.top
                anchors.topMargin: idField.visible ? panel.theme.space(1.5) : 0
                anchors.rightMargin: panel.theme.space(1.5)
                visible: !row.isBusy && !row.isFailed
                password: true
                placeholder: "Passphrase"
                focusWhen: row.isPasswordOpen && !row.isEnterprise
                onTextEdited: text => {
                    if (row.isPasswordOpen)
                        panel.passwordText = text;
                }
                onAccepted: row.submitCredentials()
                onCancelled: panel.cancelPasswordPrompt()
            }

            // Their prompt shows the in-flight state in place of the fields.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                visible: row.isBusy || row.isFailed
                height: panel.theme.space(8)
                radius: panel.theme.radius(0.75)
                color: panel.theme.surface2
                border.width: panel.theme.borderWidth
                border.color: row.isFailed ? panel.theme.error : panel.theme.surface3

                Text {
                    anchors.centerIn: parent
                    text: row.isFailed ? (panel.failureReason || "Failed") : "Connecting…"
                    color: row.isFailed ? panel.theme.error : panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.833)
                }
            }

            PanelButton {
                id: connectButton

                anchors.right: parent.right
                anchors.top: parent.top
                theme: panel.theme
                visible: !row.isBusy && !row.isFailed
                label: "Connect"
                // NetworkManager rejects a WPA passphrase shorter than this,
                // so the button stays dead rather than bouncing back an error.
                enabled: panel.passwordText.length >= 8 && (!row.isEnterprise || panel.identityText.length > 0)
                onClicked: row.submitCredentials()
            }
        }

        // A failed attempt clears itself so the field comes back for a retry.
        Timer {
            interval: 2000
            running: row.isFailed && row.isPasswordOpen
            onTriggered: {
                panel.failureSsid = "";
                panel.failureReason = "";
            }
        }
    }
}
