import QtQuick

// OMAKADE'S DESIGN SYSTEM, SPOKEN IN THIS SHELL'S TOKENS.
//
// omakade (github.com/tsouth89/omakade) is a game library built on Qt 6 + QML —
// the same toolkit this shell runs — so its components port as CODE rather than
// as inspiration. Two things had to be translated for that to work: its theme
// singleton, and its scale. This file is both translations, in one place, so
// every other file in the module can carry omakade's own numbers unchanged and
// still be read side by side with the original.
//
// ---------------------------------------------------------------- the scale
//
// THIS IS THE LOAD-BEARING PART. Every number in omakade's QML is a literal
// tuned for its 1380x880 window: font sizes 8 through 20, button heights 34 and
// 42, a 24 px page margin, 210 px grid cells, a 16 px scrollbar. This window is
// 3467x1914 on the desk. Copied literally, omakade's design would arrive here
// as a stamp collection — and doc §10 records precisely that verdict against
// the first version of this module ("Design looks very bad. fonts very small").
//
// So the literals stay at the call sites, exactly as omakade wrote them, and go
// through ui() and type(). omakade's PROPORTIONS survive unchanged; the numbers
// they resolve to follow the window. `GlassButton`'s `implicitHeight: compact ?
// 34 : 42` becomes `compact ? style.ui(34) : style.ui(42)`, which is 34 and 42
// on a small window and 65 and 80 on the desk. One set of numbers, two screens,
// and a diff against upstream that still reads as a port.
//
// It stays theme-honest on the way through: ui() carries the theme's density
// and type() goes through fontPx(), so a theme that changes font.size or
// space.density moves the whole hub with the rest of the desktop — which is the
// rule the module's old private type scale already lived by (doc §10).
QtObject {
    id: style

    required property var theme

    // The window's own dimensions, assigned by Dekho.qml. Not the screen's: the
    // hub is an ordinary niri toplevel now (doc §12) and can be resized to half
    // the desk, at which point it should read like the laptop it now resembles.
    property real windowHeight: 1000

    // THE SCALE FOLLOWS WHICHEVER DIMENSION IS TIGHTER, and it has to. Derived
    // from height alone — which is what this did first — a window narrowed to
    // half the desk keeps its full 1914 px of height, so every control stays
    // desk-sized while the grid loses three of its seven columns. The verdict on
    // that build was "buttons look bigger… can we zoom out so at this size it
    // looks like the desktop view", and it is the right one: a window half as
    // wide is a smaller screen, not a taller one.
    //
    // 1000 px tall and 1380 px wide are the two references, and 1380 is not
    // arbitrary — it is omakade's own window width, the width every literal in
    // this design was tuned against, so boost 1.0 is the design at its native
    // size. The desk is wide enough that height still wins there (1.91 against
    // 2.51), so nothing about the full-width layout moves; the clamp at 2.1 and
    // the floor at 1.0 are the module's previous `typeBoost` curve, kept rather
    // than retuned so the type lands where the user already accepted it.
    property real windowWidth: 1600

    readonly property real boost: Math.max(1, Math.min(2.1, Math.min(windowHeight / 1000, windowWidth / 1380)))

    // omakade's geometry literals — heights, margins, spacings, radii.
    function ui(n) {
        return Math.round(n * style.boost * style.theme.density);
    }

    // omakade's font-size literals. Divided by 12 because that is the shell's
    // default `font.size`, so type(12) is fontPx(1) and a theme that raises the
    // base size raises omakade's whole scale with it.
    function type(n) {
        return style.theme.fontPx(n / 12 * style.boost);
    }

    function alpha(c, a) {
        return style.theme.alpha(c, a);
    }

    // ---------------------------------------------------------------- colour
    // omakade reads an omarchy Theme singleton. The names on the left are its;
    // the tokens on the right are ours (Services/Theme.qml), chosen so a theme
    // switch moves this module with the rest of the desktop.
    readonly property color bg: theme.surface0          // darkerBackground
    readonly property color panel: theme.surface1       // background
    readonly property color raised: theme.surface2
    readonly property color fg: theme.textPrimary       // foreground
    readonly property color brightFg: theme.col("ansi.bright-white")
    readonly property color muted: theme.textMuted      // mutedText
    readonly property color accent: theme.accent
    readonly property color green: theme.okColor
    readonly property color yellow: theme.warn
    readonly property color blue: theme.col("ansi.blue")
    readonly property color red: theme.error
    readonly property string fontFamily: theme.fontUi

    // omakade's `Math.max(5, Theme.cornerRadius)` idiom, at three sizes: cards
    // and buttons, tiles, and dialogs.
    readonly property int radiusSm: Math.max(ui(5), theme.radius(0.6))
    readonly property int radiusMd: Math.max(ui(6), theme.radius(0.75))
    readonly property int radiusLg: Math.max(ui(8), theme.radius(1))
    readonly property int hairline: Math.max(1, theme.borderWidth)

    // ---------------------------------------------------------------- motion
    // omakade gates every Behavior on `Preferences.reducedMotion`. That check is
    // DELIBERATELY NOT PORTED: this shell already has the stronger version of it
    // — every duration here runs through the theme's `motion.duration`, and
    // themes that ship `duration = 0` (retro-82) stop the whole desktop dead,
    // including this module, with no per-Behavior opt-in to forget.
    readonly property int normal: theme.motion.standard
    readonly property int slow: theme.motion.slow
    readonly property int easing: theme.motion.easing
    readonly property int easingSmooth: theme.motion.easingSmooth

    // ----------------------------------------------------------- page layout
    // omakade's `Math.max(22, root.width * 0.032)` page margin, and the gutter
    // its grid delegates carry as 8/7 px anchor margins.
    readonly property int pagePad: Math.max(ui(22), Math.round(windowWidth * 0.032))
    readonly property int gutter: ui(8)
}
