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

    // Held through the card's fade-out — `visible: opened` unmapped the
    // window on the same frame close() ran, so the exit animation never
    // reached the screen. Input drops instantly (mask below): a dying scrim
    // must not eat the click that lands where it used to be.
    visible: opened || card.opacity > 0
    mask: opened ? null : closedMask
    Region {
        id: closedMask
    }
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

    // Card-shaped frost, never the fullscreen click-catcher: an in-scene
    // blurred-wallpaper backdrop that rides the card's fade and slide, so
    // the frost opens and closes with the card instead of popping in
    // behind it (see components/CardFrost.qml for why the protocol blur
    // can never do this).
    CardFrost {
        theme: panelWindow.theme
        card: card
        windowWidth: panelWindow.width
        windowHeight: panelWindow.height
        offsetX: cardSlide.x
        offsetY: cardSlide.y
        visible: panelWindow.theme.blurActive && card.opacity > 0
    }

    Rectangle {
        id: card

        // The handle PanelHint looks for. It lives on the CARD, not on the
        // overlay, because a hint walks up from the control it describes and
        // the overlay is a SIBLING of the content rather than an ancestor —
        // a walk looking for the overlay itself never meets it, silently
        // falls back to anchor-relative placement, and the hint runs off the
        // card edge. The card is on that path; the overlay hangs off it.
        property Item panelHintOverlay: hintOverlay

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
        // The fade alone read as a pop; the card now also slides away from
        // its bar edge into place, whichever edge the bar is on. A transform
        // keeps the animated offset out of the anchored x/y bindings above.
        transform: Translate {
            id: cardSlide

            property real slide: panelWindow.opened ? 0 : panelWindow.theme.space(1.5)
            x: !panelWindow.barVertical ? 0 : (panelWindow.barPosition === "left" ? -slide : slide)
            y: panelWindow.barVertical ? 0 : (panelWindow.barAtBottom ? slide : -slide)
            Behavior on slide {
                NumberAnimation {
                    duration: panelWindow.theme.time(0.8)
                    easing.type: panelWindow.theme.easing
                }
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
                    // Omarchy's cross-panel switching: Tab walks
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

                StyledText {
                    theme: panelWindow.theme
                    role: StyledText.Title

                    visible: panelWindow.panelTitle !== ""
                    text: panelWindow.panelTitle
                    color: panelWindow.theme.panel.text
                    font.weight: Font.DemiBold
                }

                Column {
                    id: contentColumn
                    width: parent.width
                    spacing: panelWindow.theme.space(2)
                }
            }
        }

        // Where PanelHint puts itself, and the reason it can be trusted to
        // land on top. QML stacking is per-parent: a hint parented to the
        // control it describes sits inside one row of contentColumn, and
        // EVERY LATER ROW paints over it whatever z it asks for — which is
        // exactly what a tooltip must never do. One overlay declared after
        // the content, filling the card, gives every hint the same single
        // stacking context, and the card's own `clip: true` then becomes the
        // bound a hint should honour rather than the thing that truncates it.
        //
        // Not `anchors.fill: card` — the content is inset by cardContent's
        // margins and a hint clamped to the very edge would touch the border.
        Item {
            id: hintOverlay
            anchors.fill: parent
            anchors.margins: panelWindow.theme.space(1.5)
            z: 90
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
