import QtQuick

// The hub's design tokens, spoken in this shell's theme.
//
// Same shape as Modules/Dekho/Style.qml and for the same reason: the layout
// literals below are tuned against one reference window, and a hub that copied
// them raw would arrive on a 3467x1914 desk as a stamp collection — which is
// the verdict the movie hub's first version actually collected. So the
// literals stay at the call sites and go through ui() and type(), and the
// PROPORTIONS survive while the numbers follow the window.
//
// It stays theme-honest: ui() carries the theme's density and type() goes
// through fontPx(), so a theme change moves this hub with the rest of the
// desktop, and a theme with `duration = 0` stops its motion dead.
QtObject {
    id: style

    required property var theme

    property real windowHeight: 1000
    property real windowWidth: 1600

    // Follows whichever dimension is tighter — a window narrowed to half the
    // desk is a smaller screen, not a taller one.
    readonly property real boost: Math.max(1, Math.min(2.1, Math.min(windowHeight / 1000, windowWidth / 1380)))

    function ui(n) {
        return Math.round(n * style.boost * style.theme.density);
    }

    function type(n) {
        return style.theme.fontPx(n / 12 * style.boost);
    }

    function alpha(c, a) {
        return style.theme.alpha(c, a);
    }

    // ----------------------------------------------------------------- colour
    readonly property color bg: theme.surface0
    readonly property color panel: theme.surface1
    readonly property color raised: theme.surface2
    readonly property color fg: theme.textPrimary
    readonly property color muted: theme.textMuted
    readonly property color accent: theme.accent
    readonly property color green: theme.okColor
    readonly property color yellow: theme.warn
    readonly property color red: theme.error

    readonly property string fontFamily: theme.fontUi

    // THE ARABIC FACE IS NAMED, NOT INHERITED. The theme's UI font is chosen
    // for Latin and has no Arabic coverage worth reading Quran in; left to
    // fontconfig's fallback the ayah renders in whatever happens to be first.
    // "Noto Naskh Arabic" is what this machine has and it is a naskh, which is
    // the right family of shape for a mushaf.
    //
    // A dedicated Quranic face (Amiri, Scheherazade, or a real KFGQPC mushaf
    // font) would be better — the Uthmani text is designed around one — but
    // installing fonts is the user's call, so this uses what is already here.
    readonly property string arabicFamily: "Noto Naskh Arabic"

    // ---------------------------------------------------- recitation verdicts
    // The four states a word can come back in. `wrong` is deliberately the
    // theme's warn and not its error: the checker is right about 28 words in
    // 29, and painting a possible false positive in alarm red overstates how
    // sure it is.
    function wordColor(op) {
        switch (op) {
        case "ok":
            return style.green;
        case "wrong":
            return style.yellow;
        case "missed":
            return style.red;
        default:
            return style.muted;
        }
    }

    readonly property int radiusSm: Math.max(ui(5), theme.radius(0.6))
    readonly property int radiusMd: Math.max(ui(6), theme.radius(0.75))
    readonly property int radiusLg: Math.max(ui(8), theme.radius(1))
    readonly property int hairline: Math.max(1, theme.borderWidth)

    readonly property int normal: theme.motion.standard
    readonly property int slow: theme.motion.slow
    readonly property int easing: theme.motion.easing

    readonly property int pagePad: Math.max(ui(22), Math.round(windowWidth * 0.032))
    readonly property int gutter: ui(8)
}
