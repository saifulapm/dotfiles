import QtQuick

// Bordered square holding one glyph (their PanelActionButton): hover fill,
// dimmed while it has nothing to act on, the shared cursor border when the
// keyboard is on it. Uses Item.enabled itself, not a shadowing property of
// the same name: disabling the item disables its handlers with it.
Rectangle {
    id: glyphButton

    required property var theme
    property string glyph: ""
    property string hint: ""
    property bool hasCursor: false
    property real glyphSize: theme.fontPx(1.083)
    // The action this button fired is still running: the glyph spins and taps
    // are refused, so a second click can't queue a duplicate behind the first.
    // Opt-in — every existing call site leaves it false and is unchanged.
    property bool busy: false

    signal hovered
    signal activated

    // Square, whole and odd, so the highlight is not wider than tall and an
    // icon glyph (usually an odd number of pixels wide) has the same space on
    // both sides (omarchy be052339). Kept at our row height rather than their
    // 22 px minimum.
    implicitWidth: theme.space(7) | 1
    implicitHeight: implicitWidth
    radius: theme.radius(0.75)
    color: glyphHover.hovered && glyphButton.enabled ? theme.alpha(theme.textPrimary, 0.08) : theme.surface2
    border.width: theme.borderWidth
    border.color: glyphButton.hasCursor && glyphButton.enabled ? theme.alpha(theme.accent, 0.6) : theme.surface3
    opacity: glyphButton.enabled ? 1 : 0.45

    OpticalGlyph {
        id: buttonGlyph
        // Snapped to whole pixels so the glyph doesn't round away from
        // the fill's centre (omarchy be052339).
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        text: glyphButton.glyph
        color: glyphButton.busy ? glyphButton.theme.accent : glyphButton.theme.textPrimary
        pixelSize: glyphButton.glyphSize

        // Targets the glyph rather than binding `on rotation`, so the angle can
        // be zeroed when the work finishes — an animator bound as a value
        // source leaves the glyph frozen at whatever angle it stopped on.
        RotationAnimator {
            target: buttonGlyph
            running: glyphButton.busy
            from: 0
            to: 360
            duration: glyphButton.theme.time(6)
            loops: Animation.Infinite
            onRunningChanged: if (!running)
                buttonGlyph.rotation = 0
        }
    }

    HoverHandler {
        id: glyphHover
        cursorShape: glyphButton.enabled && !glyphButton.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
        onHoveredChanged: if (hovered && glyphButton.enabled)
            glyphButton.hovered()
    }

    TapHandler {
        enabled: glyphButton.enabled && !glyphButton.busy
        onTapped: glyphButton.activated()
    }

    PanelHint {
        theme: glyphButton.theme
        visible: glyphHover.hovered && glyphButton.enabled && glyphButton.hint !== ""
        anchor: glyphButton
        text: glyphButton.hint
    }
}
