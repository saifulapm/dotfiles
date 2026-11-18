import Quickshell
import Quickshell.Networking
import QtQuick
import "lib/control-net.mjs" as Lib
import "lib/voice.mjs" as V

// Control's Wi-Fi section: every Wi-Fi device's networks, from NetworkManager's own change events; Control draws its rows and the password field in the asking network's row.
Item {
    id: section

    required property var theme
    property int selected: 0
    readonly property var look: V.listLook(theme.tokens)

    readonly property var wifi: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)
    readonly property var all: wifi.reduce((nets, d) => nets.concat(d.networks.values), [])
    readonly property var networks: Lib.wifiOrder(all.map(n => ({
                    name: n.name,
                    connected: n.connected,
                    known: n.known,
                    signalStrength: n.signalStrength
                }))).map(i => all[i])
    // Each row's text, and its look on the page: the signal glyph, what it is and its mark.
    readonly property var rows: networks.map(n => Object.assign(Lib.wifiRow(n), Lib.wifiLook({
                    connected: n.connected,
                    known: n.known,
                    secured: n.security !== WifiSecurityType.Open,
                    signalStrength: n.signalStrength
                })))

    // Quickshell lists a network that is not saved only while its device scans, so the section scans while it is drawn and never while idle.
    function scan() {
        wifi.forEach(d => d.scannerEnabled = visible);
    }
    onVisibleChanged: {
        scan();
        if (!visible)
            closeLine();
    }
    onWifiChanged: scan()

    // The item a key last acted on: the reorder its connect causes keeps the selection on it, and moving away lets it go.
    property var picked: null
    onSelectedChanged: {
        if (networks.indexOf(picked) !== selected)
            picked = null;
    }
    onRowsChanged: {
        const i = networks.indexOf(picked);
        selected = i >= 0 ? i : Math.max(0, Math.min(selected, rows.length - 1));
    }

    // The network a key last asked to join, whose failure may ask for a password.
    property var pending: null
    // The secured network the password line is open for, null while it is closed.
    property var asking: null
    readonly property bool typing: asking !== null
    // The typed password: only its length and its dots leave the section.
    property string psk: ""
    property string message: ""

    function closeLine() {
        asking = null;
        psk = "";
        message = "";
    }

    Connections {
        target: section.pending
        // With the line open every failure says why; with it closed only NoSecrets opens it, as Quickshell takes a PSK only for WPA-PSK, WPA2-PSK and SAE.
        function onConnectionFailed(reason) {
            const n = section.pending;
            if (section.asking === n)
                section.message = section.look.tabText(reason === ConnectionFailReason.NoSecrets ? "Wrong password" : reason === ConnectionFailReason.WifiNetworkLost ? "Network not found" : reason === ConnectionFailReason.WifiAuthTimeout ? "Timed out" : "Could not join");
            else if (reason === ConnectionFailReason.NoSecrets && [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(n.security))
                section.asking = n;
        }
        function onConnectedChanged() {
            if (section.pending.connected && section.asking === section.pending)
                section.closeLine();
        }
    }

    // While the line is open Control hands it every key: j and k are letters there, and Esc closes only the line.
    function typeKey(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (psk !== "") {
                pending = asking;
                asking.connectWithPsk(psk);
                psk = "";
                message = "";
            }
        } else if (event.key === Qt.Key_Escape)
            closeLine();
        else if (event.key === Qt.Key_V && event.modifiers & Qt.ControlModifier)
            // A passphrase holds no line breaks, so the newline a copy often carries goes.
            psk += Quickshell.clipboardText.replace(/[\r\n]/g, "");
        else if (event.key === Qt.Key_Backspace)
            // Spread, not Array.from: QML's Array.from walks UTF-16 units, so it would split an emoji.
            psk = [...psk].slice(0, -1).join("");
        else if (event.text >= " " && event.text !== "\x7f" && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier)))
            psk += event.text;
        return true;
    }

    function key(event) {
        if (typing)
            return typeKey(event);
        const network = networks[selected];
        if (!network)
            return false;
        picked = network;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (network.connected)
                network.disconnect();
            else {
                pending = network;
                network.connect();
            }
        } else if (event.key === Qt.Key_D)
            network.forget();
        else
            return false;
        return true;
    }

    function state() {
        return {
            details: rows.map(r => r.detail),
            line: typing,
            pskLength: psk.length,
            lineMessage: message
        };
    }
}
