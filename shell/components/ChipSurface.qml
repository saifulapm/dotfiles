import QtQuick

// The tile: a bordered surface2 chip that fills with an accent wash when it
// is the chosen one, lifts under the pointer, and dims when there is nothing
// to choose. The power-profile cells, the AirPods noise-mode cells, the
// monitor pills, the AI provider tabs and PanelButton are all this shape.
//
// It existed five times before this. MonitorPanel had already noticed and
// extracted a private `component Pill`, which is the right instinct solved at
// the wrong scope — the other four went on open-coding the same four numbers
// (accent 0.25, textPrimary 0.08, surface2, surface3), which is exactly how a
// value drifts.
//
// Surface only, no content: the call sites genuinely differ inside — a bare
// label, a glyph over a label, a tab caption — and that variance is theirs to
// keep. What they share is the state-to-color mapping, so that is all this
// owns. Same reasoning as CursorSurface, and the same cheap implementation:
// a Rectangle with animated colors, no Shape and no layer.
//
// Deliberately NOT gated on `interactive` internally. Each call site already
// decides whether its hover handler is live, and taking that over here would
// silently change which inert cells still light up under the pointer.
Rectangle {
    id: root

    required property var theme

    // The active choice — the accent wash.
    property bool chosen: false
    // The keyboard cursor is on this chip. Also outlines it.
    property bool hasCursor: false
    // Pointer hover, where the site tracks it apart from the cursor. NOT
    // `hovered`: that name is already a signal on GlyphButton, PanelSwitch and
    // MonitorPanel's Pill, and a property colliding with it is a hard error.
    property bool pointerOver: false
    // Nothing to choose here (no power-profiles daemon, an output that
    // vanished): dimmed, and the site's own handlers stay off.
    property bool interactive: true

    radius: root.theme.radius(0.75)
    color: root.chosen ? root.theme.alpha(root.theme.accent, 0.25) : (root.hasCursor || root.pointerOver ? root.theme.alpha(root.theme.textPrimary, 0.08) : root.theme.surface2)
    border.width: root.theme.borderWidth
    border.color: root.chosen || root.hasCursor ? root.theme.accent : root.theme.surface3
    opacity: root.interactive ? 1 : 0.45

    Behavior on color {
        ColorAnimation {
            duration: root.theme.motion.standard
            easing.type: root.theme.motion.easing
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: root.theme.motion.standard
            easing.type: root.theme.motion.easing
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.theme.motion.standard
            easing.type: root.theme.motion.easing
        }
    }
}
