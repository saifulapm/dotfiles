import QtQuick

// Omarchy's PanelToolTip, kept inside the card: the bar's tooltips belong to
// the bar window, which a panel is not.
//
// IT LIVES IN THE CARD'S OVERLAY, not under the control it describes, and that
// is the whole point. QML stacking is per-parent, so a hint parented to its
// anchor sits inside one row of the content column and every LATER row paints
// straight over it, whatever z it asks for — a tooltip with the next section's
// labels printed through it. The card also clips, so a hint hanging off a
// control near the bottom edge was simply cut in half. Both were live: the
// Wi-Fi band switch's hint had "5GHz" drawn across it, and the notification
// panel's "Do not disturb" lost its lower half.
//
// So: reparent to BarPanel's hintOverlay (found by walking up from the anchor,
// so nothing has to be threaded through every panel), position by mapping the
// anchor's box into overlay coordinates, then FLIP AND CLAMP to stay inside.
// `above` is now only the preference — a hint that would not fit below goes
// above on its own, and one that would not fit either way picks the roomier
// side. Call sites no longer have to know where they sit in the card.
Rectangle {
    id: hintBox

    required property var theme
    property Item anchor: null
    property string text: ""
    // Preferred side. Honoured when it fits; overridden when it does not.
    property bool above: false

    // Walk up from the anchor for the card that OWNS the overlay, and take the
    // overlay from it. Looking for the overlay itself does not work: it is a
    // sibling of the content, not an ancestor, so the walk never meets it,
    // `placed` stays false and the hint lands at the anchor's own origin and
    // runs off the card. Null until the anchor is parented, so every geometry
    // binding below tolerates it.
    readonly property Item overlay: {
        let node = hintBox.anchor;
        while (node) {
            if (node.panelHintOverlay)
                return node.panelHintOverlay;
            node = node.parent;
        }
        return null;
    }

    readonly property bool placed: !!anchor && !!overlay

    parent: overlay || anchor

    // The anchor's box in overlay coordinates. Recomputed whenever anything it
    // depends on moves — the explicit width/height/x/y reads are what make this
    // binding re-evaluate on a scroll or a relayout, not decoration.
    readonly property rect anchorBox: {
        if (!placed)
            return Qt.rect(0, 0, 0, 0);
        void anchor.x;
        void anchor.y;
        void anchor.width;
        void anchor.height;
        void overlay.width;
        void overlay.height;
        const p = anchor.mapToItem(overlay, 0, 0);
        return Qt.rect(p.x, p.y, anchor.width, anchor.height);
    }

    readonly property real gap: theme.space(1)

    // Below unless it does not fit; then above; then whichever side is roomier,
    // so a hint on a control taller than the space around it still shows.
    readonly property bool showAbove: {
        if (!placed)
            return above;
        const roomBelow = overlay.height - (anchorBox.y + anchorBox.height) - gap;
        const roomAbove = anchorBox.y - gap;
        if (above)
            return roomAbove >= height || roomAbove >= roomBelow;
        return roomBelow < height && (roomAbove >= height || roomAbove > roomBelow);
    }

    width: hintLabel.implicitWidth + theme.space(3)
    height: hintLabel.implicitHeight + theme.space(2)

    // Right-aligned to the anchor, as before, then clamped so a hint wider than
    // the space to its left cannot slide out of the card.
    x: placed ? Math.max(0, Math.min(anchorBox.x + anchorBox.width - width, overlay.width - width)) : 0
    y: {
        if (!placed)
            return 0;
        const wanted = showAbove ? anchorBox.y - height - gap : anchorBox.y + anchorBox.height + gap;
        return Math.max(0, Math.min(wanted, overlay.height - height));
    }

    radius: theme.radius(0.75)
    color: theme.surface2
    border.width: theme.borderWidth
    border.color: theme.surface3
    z: 10

    StyledText {
        id: hintLabel
        theme: hintBox.theme
        anchors.centerIn: parent
        text: hintBox.text
        role: StyledText.Small
    }
}
