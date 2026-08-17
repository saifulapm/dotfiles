import QtQuick

// The single highlight surface panel rows and controls share: `current` is
// the active choice (filled), `hasCursor` is where mouse or keyboard sits
// (outlined). Omarchy's cursor model, one copy.
Rectangle {
    required property var theme
    property bool hasCursor: false
    property bool current: false

    radius: theme.radius(0.75)
    color: current ? theme.alpha(theme.accent, 0.18) : (hasCursor ? theme.alpha(theme.textPrimary, 0.06) : "transparent")
    border.width: theme.borderWidth
    border.color: hasCursor ? theme.alpha(theme.accent, 0.6) : "transparent"
}
