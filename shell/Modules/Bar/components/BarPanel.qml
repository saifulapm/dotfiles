import QtQuick
import Quickshell
import Quickshell.Wayland

// Anchored popup panel for bar widgets — omarchy's plugin panels, adapted
// to niri: a fullscreen Overlay window whose scrim dismisses on click (niri
// has no focus-grab protocol), with the card slid under the anchor widget.
// One panel at a time: opening asks the bar to close the previous one.
PanelWindow {
    id: panelWindow

    required property var theme
    // The bar widget this panel hangs under. Set by the widget before open().
    property Item anchorItem: null
    property bool opened: false
    property real cardWidth: 340
    property string panelTitle: ""

    default property alias content: contentColumn.data

    signal panelOpened
    signal panelClosed
    // Unhandled keys reaching the card's focus scope, for panels that add
    // keyboard navigation (the calendar steps months with the arrows).
    signal contentKey(var event)

    // Hand keyboard focus back to the card after a text field took it.
    function refocusKeys() {
        keyCatcher.forceActiveFocus();
    }

    function open() {
        const bar = anchorItem && anchorItem.bar ? anchorItem.bar : null;
        if (bar && bar.requestPanel)
            bar.requestPanel(panelWindow);
        opened = true;
        updateAnchor();
        // Re-measure once the bar layout settles — mapToItem is not
        // reactive to ancestor positions.
        anchorSettleTimer.restart();
        panelOpened();
    }

    function close() {
        if (!opened)
            return;
        const bar = anchorItem && anchorItem.bar ? anchorItem.bar : null;
        if (bar && bar.releasePanel)
            bar.releasePanel(panelWindow);
        opened = false;
        panelClosed();
    }

    function toggle() {
        if (opened)
            close();
        else
            open();
    }

    // Card x: centered under the anchor, clamped to the screen with an 8 px
    // inset. The bar window spans the full output, so bar coords are screen
    // coords. Computed imperatively at open (+ once settled).
    property real anchorCenterX: width / 2

    function updateAnchor() {
        const bar = anchorItem ? anchorItem.bar : null;
        if (!anchorItem || !bar || !bar.contentItem)
            return;
        const point = anchorItem.mapToItem(bar.contentItem, anchorItem.width / 2, 0);
        if (point.x > 0)
            anchorCenterX = point.x;
    }

    Timer {
        id: anchorSettleTimer
        interval: 120
        onTriggered: panelWindow.updateAnchor()
    }

    visible: opened
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qshell-panel"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: panelWindow.close()
    }

    Rectangle {
        id: card

        x: Math.max(8, Math.min(panelWindow.anchorCenterX - width / 2, panelWindow.width - width - 8))
        y: panelWindow.theme.barHeight + 6
        width: panelWindow.cardWidth
        height: Math.min(cardContent.implicitHeight + panelWindow.theme.space(8), panelWindow.height - y - panelWindow.theme.space(4))
        radius: panelWindow.theme.radius(1.5)
        color: panelWindow.theme.surface1
        border.width: panelWindow.theme.borderWidth
        border.color: panelWindow.theme.surface3
        clip: true

        opacity: panelWindow.opened ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: panelWindow.theme.time(0.8)
                easing.type: panelWindow.theme.easing
            }
        }

        MouseArea {
            // Swallow clicks so they don't fall through to the scrim.
            anchors.fill: parent
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: panelWindow.close()
            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Escape)
                    panelWindow.contentKey(event);
            }

            Column {
                id: cardContent
                x: panelWindow.theme.space(4)
                y: panelWindow.theme.space(4)
                width: parent.width - panelWindow.theme.space(8)
                spacing: panelWindow.theme.space(3)

                Text {
                    visible: panelWindow.panelTitle !== ""
                    text: panelWindow.panelTitle
                    color: panelWindow.theme.textPrimary
                    font.family: panelWindow.theme.fontUi
                    font.pixelSize: panelWindow.theme.fontPx(1.083)
                    font.weight: Font.DemiBold
                }

                Column {
                    id: contentColumn
                    width: parent.width
                    spacing: panelWindow.theme.space(2)
                }
            }
        }
    }
}
