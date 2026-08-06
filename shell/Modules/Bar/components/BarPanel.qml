import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../../components"

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
    property real cardWidth: theme.space(85)
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

    // Open the panel of the adjacent panel-owning widget in the same bar
    // section (omarchy's switchPanelFrom). Returns false when this widget is
    // the only one in its section that owns a panel.
    function switchPanel(direction) {
        const bar = anchorItem && anchorItem.bar ? anchorItem.bar : null;
        if (!bar || typeof bar.switchPanelFrom !== "function")
            return false;
        return bar.switchPanelFrom(anchorItem, direction);
    }

    // The bar this panel was requested from, kept so it can be handed back
    // even after anchorItem is gone: a destroyed activePanel emits no change
    // signal, so the bar would keep hover reveal suppressed forever.
    property var grantingBar: null

    function open() {
        const bar = anchorItem && anchorItem.bar ? anchorItem.bar : null;
        if (bar && bar.requestPanel) {
            bar.requestPanel(panelWindow);
            grantingBar = bar;
        }
        opened = true;
        updateAnchor();
        // Re-measure once the bar layout settles — mapToItem is not
        // reactive to ancestor positions.
        anchorSettleTimer.restart();
        panelOpened();
    }

    function releaseBar() {
        const bar = grantingBar;
        grantingBar = null;
        if (bar && bar.releasePanel)
            bar.releasePanel(panelWindow);
    }

    function close() {
        if (!opened)
            return;
        releaseBar();
        opened = false;
        panelClosed();
    }

    // A panel can die open — a config edit replaces its section's id list and
    // the Repeater tears the widget (and this LazyLoader child) down.
    Component.onDestruction: if (opened)
        releaseBar()

    function toggle() {
        if (opened)
            close();
        else
            open();
    }

    // The bar can be moved to any screen edge, and the card has to follow:
    // hanging off the top of the screen would leave it detached from the
    // widget it belongs to. Omarchy's four PopupCard cases, in our
    // full-screen-overlay geometry.
    readonly property string barPosition: anchorItem && anchorItem.bar ? String(anchorItem.bar.position) : "top"
    readonly property bool barAtBottom: barPosition === "bottom"
    readonly property bool barVertical: barPosition === "left" || barPosition === "right"
    readonly property int barExtent: anchorItem && anchorItem.bar && anchorItem.bar.barSize > 0 ? anchorItem.bar.barSize : theme.barHeight

    // Where the card hangs off the anchor: centered under it on a horizontal
    // bar, centered beside it on a vertical one — both clamped to the screen
    // with an 8 px inset. The bar window spans its whole edge of the output,
    // so bar coords are screen coords. Computed imperatively at open (+ once
    // settled): mapToItem is not reactive to ancestor positions.
    property real anchorCenterX: width / 2
    property real anchorCenterY: height / 2

    function updateAnchor() {
        const bar = anchorItem ? anchorItem.bar : null;
        if (!anchorItem || !bar || !bar.contentItem)
            return;
        const point = anchorItem.mapToItem(bar.contentItem, anchorItem.width / 2, anchorItem.height / 2);
        if (point.x > 0)
            anchorCenterX = point.x;
        if (point.y > 0)
            anchorCenterY = point.y;
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

        x: {
            if (!panelWindow.barVertical)
                return Math.max(panelWindow.theme.space(2), Math.min(panelWindow.anchorCenterX - width / 2, panelWindow.width - width - panelWindow.theme.space(2)));
            return panelWindow.barPosition === "left" ? panelWindow.barExtent + panelWindow.theme.space(1.5) : panelWindow.width - panelWindow.barExtent - panelWindow.theme.space(1.5) - width;
        }
        y: {
            if (panelWindow.barVertical)
                return Math.max(panelWindow.theme.space(2), Math.min(panelWindow.anchorCenterY - height / 2, panelWindow.height - height - panelWindow.theme.space(2)));
            return panelWindow.barAtBottom ? panelWindow.height - panelWindow.barExtent - panelWindow.theme.space(1.5) - height : panelWindow.barExtent + panelWindow.theme.space(1.5);
        }
        width: panelWindow.cardWidth
        height: Math.min(cardContent.implicitHeight + panelWindow.theme.space(8), panelWindow.height - (panelWindow.barVertical ? 0 : panelWindow.barExtent) - panelWindow.theme.space(1.5) - panelWindow.theme.space(4))
        radius: panelWindow.theme.radius(1.5)
        // The [panel] surface (omarchy's [popups]): a theme section restyles
        // every bar flyout card at once, and falls back to the base tokens.
        color: panelWindow.theme.panel.background
        // A gradient border is drawn by the Shape ring below instead; the
        // Rectangle's own border would paint its first stop underneath it.
        border.width: cardBorder.active ? 0 : panelWindow.theme.panel.borderWidth
        border.color: panelWindow.theme.panel.border
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
            // Content gets first refusal on every key, Escape included: a
            // panel with something open inside it (the tailscale panel's copy
            // menu, its region picker) closes that first and accepts the
            // event. An Escape nobody claimed closes the card.
            Keys.onPressed: event => {
                panelWindow.contentKey(event);
                if (event.accepted)
                    return;
                if (event.key === Qt.Key_Escape) {
                    panelWindow.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    // Omarchy's cross-panel switching (CREDITS.md): Tab walks
                    // to the next panel-owning widget in the same bar section,
                    // Shift+Tab to the previous one, wrapping at the ends.
                    const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
                    if (panelWindow.switchPanel(back ? -1 : 1))
                        event.accepted = true;
                }
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
                    color: panelWindow.theme.panel.text
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

        // On top of the content, like the Rectangle border it replaces.
        GradientBorder {
            id: cardBorder
            anchors.fill: parent
            z: 100
            spec: panelWindow.theme.panel.borderSpec
            borderWidth: panelWindow.theme.panel.borderWidth
            cornerRadius: card.radius
        }
    }
}
