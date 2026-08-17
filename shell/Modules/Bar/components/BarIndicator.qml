import QtQuick

// Status-slot indicator, ported from omarchy's BarIndicator.
//
// An indicator is a two-state status glyph: ON is fully lit and always shown,
// OFF is dimmed to 0.45 and hidden until the indicator container reveals it.
// Each indicator carries both glyphs and both tooltip strings.
//
// The container mounts every indicator TWICE — once in its inactive block and
// once, when the state is on, in its active block — and tells each copy which
// block it is in via `indicatorBlock`. `belongsInBlock` is how a copy knows to
// render or to collapse to nothing, and `activeOverride` lets the active-block
// copy render as active while its own state is still loading.
//
// Unlike upstream, a standalone indicator (`indicatorBlock: "single"`, i.e.
// one named directly in a shell.json bar array) collapses when it is off
// rather than reserving an empty slot — that is how our dnd and reminder
// widgets behaved before the container existed.
BarIcon {
    id: indicator

    property string activeGlyph: ""
    property string inactiveGlyph: activeGlyph
    property string activeTooltip: ""
    property string inactiveTooltip: activeTooltip

    // "single" (standalone in a bar array) | "active" | "inactive"
    property string indicatorBlock: "single"
    // The Indicators container, when hosted by one.
    property var indicatorHost: null
    // Set to true by the container's active block; null means "use `active`".
    property var activeOverride: null

    readonly property bool effectiveActive: activeOverride === null || activeOverride === undefined ? active : activeOverride === true
    readonly property bool belongsInBlock: indicatorBlock === "active" ? effectiveActive : (indicatorBlock === "inactive" ? !effectiveActive : true)
    readonly property bool inactiveRevealed: !effectiveActive && !!indicatorHost && indicatorHost.revealInactive

    status: true
    // State is carried by opacity, not by the attention color.
    useActiveColor: false

    glyph: effectiveActive ? activeGlyph : inactiveGlyph
    tooltipText: effectiveActive ? activeTooltip : inactiveTooltip

    visible: indicatorBlock === "single" ? effectiveActive : belongsInBlock
    opacity: !visible ? 0 : (effectiveActive ? 1 : (inactiveRevealed ? 0.45 : 0))
    // A collapsed indicator is not a click target and does not hover.
    enabled: visible && (effectiveActive || inactiveRevealed)

    // Hovering a revealed indicator holds the container open — otherwise the
    // pointer moving off the container's own area would slide it shut under
    // the pointer.
    onHoveredChanged: {
        if (indicatorBlock === "inactive" && indicatorHost)
            indicatorHost.setIndicatorItemHovered(hovered);
    }
}
