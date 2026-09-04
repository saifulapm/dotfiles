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
    // The step above `fg`, for the few things that have to win against it: a
    // primary button's label, a stat tile's figure.
    readonly property color brightFg: theme.col("ansi.bright-white")
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

    // -------------------------------------------------------------- tajweed
    // The data carries eighteen rules. A printed tajweed mushaf uses six or
    // eight colours and expects you to learn them from a key inside the cover;
    // eighteen would be a colour per rule and a legend nobody reads. These are
    // FOUR FAMILIES, grouped by what your mouth actually has to do, which is
    // the distinction a person relearning to read needs first:
    //
    //   madd     hold the vowel longer
    //   ghunnah  let it resonate through the nose
    //   qalqalah bounce the consonant
    //   silent   do not pronounce it, or merge it into the next letter
    //
    // Finer distinctions — how many counts of madd, which kind of idghaam —
    // are real and are deliberately not drawn. They are a teacher's job, and
    // guessing at them in colour would be the same overclaiming the Recite
    // screen refuses to do.
    function tajweedFamily(rule) {
        switch (rule) {
        case "madd_2":
        case "madd_246":
        case "madd_6":
        case "madd_munfasil":
        case "madd_muttasil":
            return "madd";
        case "ghunnah":
        case "idghaam_ghunnah":
        case "ikhfa":
        case "ikhfa_shafawi":
        case "idghaam_shafawi":
        case "iqlab":
            return "ghunnah";
        case "qalqalah":
            return "qalqalah";
        case "silent":
        case "hamzat_wasl":
        case "lam_shamsiyyah":
        case "idghaam_no_ghunnah":
        case "idghaam_mutajanisayn":
        case "idghaam_mutaqaribayn":
            return "silent";
        default:
            return "";
        }
    }

    function tajweedColor(rule) {
        switch (tajweedFamily(rule)) {
        case "madd":
            return style.accent;
        case "ghunnah":
            return style.green;
        case "qalqalah":
            return style.yellow;
        case "silent":
            return style.alpha(style.muted, 0.55);
        default:
            return style.fg;
        }
    }

    // One word, coloured by its rule spans, as rich text INSIDE a single Text.
    // It lives here rather than in the two files that draw words because it is
    // a pure function of the colours above, and because the reader and the
    // Recite card had already grown a copy each.
    function wordHtml(segments) {
        let out = "";
        for (let i = 0; i < segments.length; i++) {
            const seg = segments[i];
            out += seg.r ? ('<font color="' + tajweedColor(seg.r) + '">' + seg.t + "</font>") : seg.t;
        }
        return out;
    }

    readonly property var tajweedLegend: [
        {
            family: "madd",
            label: "hold it longer"
        },
        {
            family: "ghunnah",
            label: "through the nose"
        },
        {
            family: "qalqalah",
            label: "bounce it"
        },
        {
            family: "silent",
            label: "not pronounced"
        }
    ]

    function familyColor(family) {
        switch (family) {
        case "madd":
            return style.accent;
        case "ghunnah":
            return style.green;
        case "qalqalah":
            return style.yellow;
        case "silent":
            return style.alpha(style.muted, 0.55);
        default:
            return style.fg;
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
