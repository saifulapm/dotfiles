import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../../components"

// Centered Wi-Fi share overlay — port of omarchy's WifiQrPanel.qml: no card,
// just the code floating on a heavy scrim, with the SSID above it and the
// passphrase revealed on demand below. Esc or the scrim dismiss it.
//
// The matrix arrives from bin/network-qr as rows of 0/1 and is painted with
// native rectangles, so there is no temporary image and nothing to cache.
PanelWindow {
    id: root

    required property var theme
    property var qrRows: []
    property int qrSize: 0
    property bool loading: false
    property string error: ""
    property string ssid: ""
    property bool secured: false
    property string password: ""
    property bool passwordVisible: false
    property string passwordError: ""
    property bool opened: false

    readonly property bool showingQr: qrSize > 0 && !loading && error === ""

    // The scrim below is a fixed near-black regardless of theme, so text on
    // it needs a fixed light palette, not the themed foreground.
    readonly property color onScrim: "white"
    readonly property color onScrimDim: Qt.rgba(1, 1, 1, 0.55)
    readonly property color onScrimUrgent: "#ff6b6b"

    signal closeRequested
    signal passwordToggleRequested

    // The bar's one-panel-at-a-time slot calls close() on whatever holds it;
    // this card registers there (NetworkPanel.showWifiQr) so the shell's
    // close-every-panel sweep can drop its keyboard grab too.
    function close() {
        root.closeRequested();
    }

    visible: opened
    // The window is instantiated hidden, so the content's `focus: true` is
    // evaluated before the surface is mapped and Escape would land nowhere.
    // Re-acquire after mapping.
    onOpenedChanged: if (opened)
        Qt.callLater(function () {
            if (root.opened)
                keyCatcher.forceActiveFocus();
        })

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qshell-network-qr"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Deep scrim: the floating code needs the backdrop to carry the contrast
    // on any wallpaper.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.78)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.closeRequested()

        Item {
            id: card

            anchors.centerIn: parent
            width: content.implicitWidth
            height: content.implicitHeight
            // Narrow or heavily scaled outputs: shrink the whole thing rather
            // than clipping it at the screen edge.
            scale: Math.min(1, (keyCatcher.width - root.theme.space(8)) / Math.max(1, width), (keyCatcher.height - root.theme.space(8)) / Math.max(1, height))

            // Swallow clicks so only the scrim outside dismisses.
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Column {
                id: content

                anchors.fill: parent
                spacing: root.theme.space(4)

                StyledText {
                    theme: root.theme
                    role: StyledText.Small
                    mono: true

                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.ssid || "Wi-Fi").toUpperCase()
                    color: root.onScrimDim
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, root.theme.space(80))
                    horizontalAlignment: Text.AlignHCenter
                }

                // Only the dark modules paint, so the white canvas keeps its
                // rounded corners; the spec quiet zone baked into the matrix keeps
                // the code itself clear of them.
                Rectangle {
                    id: qrCanvas

                    readonly property int moduleSize: root.qrSize > 0 ? Math.max(4, Math.floor(root.theme.space(60) / root.qrSize)) : 0

                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.showingQr
                    width: root.qrSize * moduleSize
                    height: width
                    color: root.onScrim
                    radius: root.theme.radius(1)

                    Grid {
                        anchors.centerIn: parent
                        columns: root.qrSize

                        Repeater {
                            model: root.showingQr ? root.qrSize * root.qrSize : 0

                            Rectangle {
                                required property int index

                                readonly property int matrixRow: Math.floor(index / root.qrSize)
                                readonly property int matrixColumn: index % root.qrSize

                                width: qrCanvas.moduleSize
                                height: qrCanvas.moduleSize
                                color: root.qrRows[matrixRow].charAt(matrixColumn) === "1" ? "#111111" : "transparent"
                            }
                        }
                    }
                }

                StyledText {
                    theme: root.theme

                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.loading
                    text: "Generating QR code…"
                    color: root.onScrimDim
                }

                StyledText {
                    theme: root.theme

                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.error !== ""
                    text: root.error
                    color: root.onScrimUrgent
                    wrapMode: Text.Wrap
                    width: Math.min(implicitWidth, root.theme.space(80))
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledText {
                    theme: root.theme

                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.showingQr
                    text: "Scan to join this network"
                    color: root.onScrimDim
                }

                // The passphrase only enters shell memory when it is asked for,
                // and the panel drops it again when this card closes.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.showingQr && root.secured
                    text: root.passwordError !== "" ? root.passwordError : root.passwordVisible ? root.password : "Show password"
                    color: root.passwordError !== "" ? root.onScrimUrgent : root.onScrim
                    opacity: root.passwordVisible || root.passwordError !== "" ? 1 : 0.6
                    font.family: root.passwordVisible ? root.theme.fontMono : root.theme.fontUi
                    font.pixelSize: root.theme.fontPx(0.917)
                    wrapMode: Text.WrapAnywhere
                    width: Math.min(implicitWidth, root.theme.space(80))
                    horizontalAlignment: Text.AlignHCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.passwordToggleRequested()
                    }
                }
            }
        }
    }
}
