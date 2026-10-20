import Quickshell
import Quickshell.Networking
import QtQuick
import "lib/control-net.mjs" as Lib
import "lib/voice.mjs" as V

// Control's Wi-Fi section: every Wi-Fi device's networks, from NetworkManager's own change events.
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
    readonly property var rows: networks.map(n => Lib.wifiRow(n))

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
            hint: line.text,
            line: typing,
            pskLength: psk.length,
            lineText: dots.text,
            lineMessage: messageText.text,
            lineLook: {
                font: dots.font.family,
                px: dots.font.pixelSize,
                ink: String(dots.color),
                border: String(field.border.color),
                placeholder: String(placeholder.color)
            }
        };
    }

    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width

        Text {
            id: line
            textFormat: Text.PlainText
            leftPadding: 20
            text: section.look.tabText(!section.wifi.length ? "No Wi-Fi" : section.typing ? "↵ join · esc cancel" : "↵ connect · d forget")
            color: section.look.small.color
            font.family: section.look.small.font
            font.pixelSize: section.look.small.size
            font.letterSpacing: section.look.small.spacing
        }

        // The password line, drawn as the polkit prompt's field: one dot per typed character.
        Item {
            visible: section.typing
            width: parent.width
            height: field.height + 32

            Rectangle {
                id: field
                x: 20
                y: 16
                width: parent.width - 40
                height: 44
                color: "transparent"
                border.width: 1
                border.color: section.theme.color.ink

                Text {
                    id: dots
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    x: 12
                    width: parent.width - 24
                    clip: true
                    text: "•".repeat([...section.psk].length)
                    color: section.theme.color.ink
                    font.family: section.theme.tokens ? section.theme.tokens.type.ui : ""
                    font.pixelSize: 16
                }

                Text {
                    id: placeholder
                    textFormat: Text.PlainText
                    visible: section.psk === ""
                    anchors.verticalCenter: parent.verticalCenter
                    x: 12
                    text: "Password"
                    color: section.theme.color.muted
                    font.family: dots.font.family
                    font.pixelSize: 16
                }
            }
        }

        Text {
            id: messageText
            visible: text !== ""
            textFormat: Text.PlainText
            leftPadding: 20
            bottomPadding: 8
            text: section.message
            color: section.theme.color.danger
            font.family: section.theme.tokens ? section.theme.tokens.type.ui : ""
            font.pixelSize: 10
            font.letterSpacing: 1.2
        }
    }
}
