import QtQuick

// The single highlight surface panel rows and controls share: `current` is
// the active choice (filled), `hasCursor` is where mouse or keyboard sits
// (outlined), `pressed` is the moment of the click. Omarchy's cursor model,
// one copy.
//
// This is the shell's state layer. It is a plain Rectangle on purpose: the
// Material reference implementations reach for a Shape with a radial gradient
// (caelestia's StateLayer) or layer.enabled with an OpacityMask (end-4's
// RippleButton), and both spend a render pass — the second an entire
// framebuffer object — per interactive row. A shell that holds a wifi list, a
// device list and a notification list open pays that per visible row,
// forever. Two animated color properties buy most of the same feel for a
// scene-graph node that was already there.
//
// The transitions are what makes a panel feel responsive rather than
// switched: before this the fills snapped between states in one frame,
// because every site that hand-rolled this highlight — 26 of them across the
// shell — wrote the color expression and stopped there.
Rectangle {
    id: root

    required property var theme
    property bool hasCursor: false
    property bool current: false
    // Held down right now. Optional: rows that only care about hover leave it
    // alone and the state is simply never entered.
    property bool pressed: false
    // The outline says "the keyboard cursor is here", which only means
    // something where the cursor and the selection are different things — a
    // panel row you arrow onto before choosing it. In the pickers (launcher,
    // clipboard, menu, emojis, file picker) they are the same thing and the
    // fill already says it, so those rows have never drawn an outline and
    // must not start.
    property bool bordered: true

    radius: root.theme.radius(0.75)
    color: root.current ? root.theme.alpha(root.theme.accent, 0.18) : (root.pressed ? root.theme.alpha(root.theme.textPrimary, 0.12) : (root.hasCursor ? root.theme.alpha(root.theme.textPrimary, 0.06) : "transparent"))
    border.width: root.bordered ? root.theme.borderWidth : 0
    border.color: root.bordered && root.hasCursor ? root.theme.alpha(root.theme.accent, 0.6) : "transparent"

    // theme.motion.standard, not a duration of its own: this reads as "the
    // surface answered", every hover in the shell should answer at the same
    // speed, and a theme asking for no motion (retro-82 ships duration = 0)
    // has to be able to switch it off.
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
}
