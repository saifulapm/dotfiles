import QtQuick

// The shell's text primitive. Every label in the tree was spelling out the
// same three properties by hand — family, pixel size, color — 245 times, and
// the sizes had settled into a scale nobody had written down: an audit found
// fontPx(0.917) 69 times, 0.833 59 times, 0.75 44 times, 1.0 24 times, then a
// thin tail. This names that scale so a label picks its ROLE and the theme
// decides the rest.
//
// The roles are the measured multipliers, not new ones, so a site that moves
// to the matching role renders exactly the pixels it did before. Two pairs in
// the tail were the same size already and collapse: 0.792 and 0.833 both land
// on 10 px at the default font.size of 12, as do 1.083 and 1.1 on 13 px. (A
// theme that raises font.size far enough could separate the second pair by a
// pixel — no shipped theme sets the token at all, and a one-pixel drift
// between two labels that were meant to match is the bug this removes, not
// one it adds.)
//
// Family and color stay knobs rather than being folded into the role: mono
// vs ui is a semantic choice about the CONTENT (a value, a hostname, an IP
// wants mono; prose wants ui) and is orthogonal to size.
Text {
    id: root

    enum Role {
        Micro,      // 0.667 -> 8 px  — badge counts, the smallest legible mark
        Caption,    // 0.75  -> 9 px  — UPPERCASE section captions, hero meta
        Small,      // 0.833 -> 10 px — secondary and muted body
        Body,       // 0.917 -> 11 px — the panel default
        BodyLarge,  // 1.0   -> 12 px — list row titles
        Title,      // 1.083 -> 13 px — hero titles, search fields
        TitleLarge, // 1.167 -> 14 px
        Heading,    // 1.333 -> 16 px
        Display     // 1.5   -> 18 px — the lock clock and friends
    }

    required property var theme

    property int role: StyledText.Body
    // Value-shaped content (numbers, paths, hostnames) reads as mono; prose
    // reads as ui. Both resolve to the same family unless a theme splits them.
    property bool mono: false
    // The theme's muted text color instead of the primary one — the single
    // most common override at the call sites this replaces.
    property bool muted: false

    readonly property real roleScale: {
        switch (role) {
        case StyledText.Micro:
            return 0.667;
        case StyledText.Caption:
            return 0.75;
        case StyledText.Small:
            return 0.833;
        case StyledText.BodyLarge:
            return 1.0;
        case StyledText.Title:
            return 1.083;
        case StyledText.TitleLarge:
            return 1.167;
        case StyledText.Heading:
            return 1.333;
        case StyledText.Display:
            return 1.5;
        default:
            return 0.917;
        }
    }

    color: root.muted ? root.theme.textMuted : root.theme.textPrimary
    font.family: root.mono ? root.theme.fontMono : root.theme.fontUi
    font.pixelSize: root.theme.fontPx(root.roleScale)
}
