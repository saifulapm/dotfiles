import QtQuick
import "MinimapModel.js" as Model

// The minimap: one hairline pill per column of this screen's workspace, as
// wide as that column is on screen, the focused one in the accent color. Two
// windows stacked in a column split its pill.
//
// It answers the question a scrolling compositor keeps asking and never
// shows: how much is parked off to the left, how much to the right, and
// which of it am I looking at.
//
// Not a bar widget — a mark another widget wears. Clock.qml hangs it under
// the date and time, on the bar's inner edge, and gives it the label's width
// to work in (`budget`). Pills are scaled against the SCREEN while the
// workspace fits on it, so a half-empty workspace draws a half-length strip
// and only one with more than a screenful fills the budget end to end
// (MinimapModel.strip).
Item {
    id: strip

    required property var theme
    required property var niri
    // Which screen's workspace to draw. Empty means "the focused one",
    // which is what a bar surface with no screen name would want.
    property string screenName: ""
    // How much room the strip may use, in pixels — the host's, not its own:
    // the clock is as wide as its label, and a strip wider than the text it
    // underlines would look like a different widget.
    property real budget: 120
    // Which way the rail runs. A bar on its side turns the rail with it: the
    // columns stack downwards and the line hugs the bar's inner edge, so it
    // stays a border either way rather than a horizontal mark in a column.
    property bool vertical: false
    // The unfocused pill color; the host passes its own foreground so the
    // strip follows a transparent bar's sampled contrast color.
    property color pillColor: theme.textPrimary
    // A hairline: thin enough to read as part of the bar's edge rather than
    // as a widget of its own. 2 px is the floor that survives the 1.1 scale
    // this panel runs at — a 1 px rail lands on a fractional physical pixel
    // and greys out to half its color.
    property int thickness: 2

    // The width of the screen the layout scrolls along — the axis pills are
    // scaled against, whichever edge the bar is on. The host reads it off its
    // own bar surface.
    property real screenWidth: 0

    // The workspace this screen is showing. is_active, not is_focused: every
    // output shows one, and only one of them is also focused.
    readonly property int workspaceId: {
        for (const w of niri.workspaces) {
            if (screenName !== "" && w.output !== screenName)
                continue;
            if (w.is_active)
                return w.id;
        }
        return -1;
    }

    property var columns: []

    function rebuild() {
        const next = Model.build(niri.windows, workspaceId, screenWidth, budget);
        // Every window event bumps windowsRevision — a terminal retitling
        // itself is one — and re-assigning an equal strip would destroy and
        // rebuild every delegate for nothing (Workspaces' sameIds rule).
        if (!Model.same(next, columns))
            columns = next;
    }

    onWorkspaceIdChanged: rebuild()
    onScreenWidthChanged: rebuild()
    onBudgetChanged: rebuild()
    Component.onCompleted: rebuild()

    Connections {
        target: strip.niri
        function onWindowsRevisionChanged() {
            strip.rebuild();
        }
    }

    visible: columns.length > 0
    implicitWidth: vertical ? thickness : rail.implicitWidth
    implicitHeight: vertical ? rail.implicitHeight : thickness

    // Grids rather than a Row: one delegate set that lays the rail out along
    // whichever way the bar is turned (the Workspaces trick). Two gap sizes,
    // so a column holding two tiles still reads as one column.
    Grid {
        id: rail

        columns: strip.vertical ? 1 : Math.max(1, strip.columns.length)
        columnSpacing: strip.vertical ? 0 : Model.COLUMN_GAP
        rowSpacing: strip.vertical ? Model.COLUMN_GAP : 0

        Repeater {
            model: strip.columns

            delegate: Grid {
                id: columnGroup

                required property var modelData

                columns: strip.vertical ? 1 : Math.max(1, modelData.tiles.length)
                columnSpacing: strip.vertical ? 0 : Model.TILE_GAP
                rowSpacing: strip.vertical ? Model.TILE_GAP : 0

                Repeater {
                    model: columnGroup.modelData.tiles

                    delegate: Rectangle {
                        id: pill

                        required property var modelData

                        readonly property bool focused: strip.niri.focusedWindowId === pill.modelData.id

                        width: strip.vertical ? strip.thickness : pill.modelData.length
                        height: strip.vertical ? pill.modelData.length : strip.thickness
                        radius: strip.thickness / 2
                        color: pill.focused ? strip.theme.accent : strip.pillColor
                        opacity: pill.focused ? 1 : 0.35

                        Behavior on color {
                            ColorAnimation {
                                duration: strip.theme.motion.standard
                                easing.type: strip.theme.motion.easing
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: strip.theme.motion.standard
                                easing.type: strip.theme.motion.easing
                            }
                        }
                    }
                }
            }
        }
    }
}
