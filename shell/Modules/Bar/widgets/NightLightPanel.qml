import QtQuick
import "../components"
import "../../../components"
import "NightLightModel.js" as Model

// Night-light panel — the three modes as rows, in the family's visual
// language: a hero naming the current colour temperature by mood, the error
// line, one row per mode with the active one filled, and a temperature nudge
// under them.
//
// The rows are a RADIO, not three toggles: Auto, Day and Night are the same
// question answered three ways, and exactly one is true. Clicking the active
// row does nothing rather than releasing it — the way back from a hold is
// Auto, which is on screen, and a row that turned itself off would leave the
// panel briefly showing no answer at all.
//
// The cursor model is the family's single-highlight one: j/k and the arrows
// walk the rows, Enter chooses, r re-probes. The first arrow press only
// reveals the cursor. [ and ] nudge the night temperature, which is the one
// setting worth reaching without opening a config file.
BarPanel {
    id: panel

    required property var nightlight

    panelTitle: ""
    cardWidth: theme.space(85)

    readonly property var modes: Model.MODES
    readonly property string activeKey: nightlight.modeKey
    readonly property bool running: nightlight.running

    // -------------------------------------------------------------- cursor
    property int modeIndex: 0
    property bool cursorActive: false

    function moveCursor(dy) {
        cursorActive = true;
        if (modes.length === 0)
            return;
        modeIndex = Math.max(0, Math.min(modes.length - 1, modeIndex + dy));
    }

    function selectedMode() {
        if (modes.length === 0)
            return null;
        return modes[Math.max(0, Math.min(modeIndex, modes.length - 1))];
    }

    function activateCursor() {
        if (!cursorActive) {
            cursorActive = true;
            return;
        }
        const mode = selectedMode();
        if (mode)
            panel.nightlight.setMode(mode.key);
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            panel.moveCursor(panel.cursorActive ? 1 : 0);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            panel.moveCursor(panel.cursorActive ? -1 : 0);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            panel.activateCursor();
            break;
        case Qt.Key_R:
            panel.nightlight.refresh();
            break;
        case Qt.Key_BracketLeft:
            panel.nightlight.nudgeNightTemp(-100);
            break;
        case Qt.Key_BracketRight:
            panel.nightlight.nudgeNightTemp(100);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------ lifecycle
    // Probe-on-open: one snapshot squares the rows with reality and re-arms a
    // follower that gave up while the daemon was down. Everything after that
    // arrives on the stream.
    onPanelOpened: {
        panel.cursorActive = false;
        panel.modeIndex = Math.max(0, panel.modes.findIndex(m => m.key === panel.activeKey));
        panel.nightlight.refresh();
    }

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Night Light"
        meta: panel.nightlight.heroMeta
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            text: panel.nightlight.warm ? "󰖔" : "󰖙"
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.running ? (panel.nightlight.forced ? panel.theme.accent : panel.theme.textPrimary) : panel.theme.textMuted
            opacity: panel.running ? 1.0 : 0.6
        }
    }

    // ---------------------------------------------------------------- error
    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.nightlight.lastError !== ""
        width: parent.width
        text: panel.nightlight.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
    }

    // ----------------------------------------------------------------- rows
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "MODE"
            // The schedule's next move, where there is one. A hold has none,
            // and says so rather than showing a stale time.
            value: panel.running ? (panel.nightlight.nextText !== "" ? panel.nightlight.nextText.toUpperCase() : "HELD") : "OFF"
        }

        Column {
            id: rowColumn

            width: parent.width
            spacing: panel.theme.space(0.5)

            Repeater {
                model: panel.modes

                ModeRow {
                    required property var modelData
                    required property int index

                    width: rowColumn.width
                    mode: modelData
                    rowIndex: index
                }
            }
        }
    }

    // ------------------------------------------------------ night temperature
    // Hidden under a day hold: the control would still write the config, but
    // nothing on the glass would move, and a slider that does nothing is
    // worse than no slider.
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)
        visible: panel.running && panel.activeKey !== "day"

        Separator {
            theme: panel.theme
        }

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "NIGHT WARMTH"
            value: Model.kelvinText(panel.nightlight.dayTemp) + " NEUTRAL"
        }

        Item {
            width: parent.width
            implicitHeight: Math.max(warmerButton.implicitHeight, nudgeLabel.implicitHeight)

            NudgeButton {
                id: coolerButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰍶" // md-minus-circle-outline
                hint: "Cooler"
                delta: 100
            }

            StyledText {
                id: nudgeLabel

                theme: panel.theme
                anchors.centerIn: parent
                text: Model.moodName(panel.nightlight.temp)
                color: panel.theme.textPrimary
                elide: Text.ElideRight
            }

            NudgeButton {
                id: warmerButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰐗" // md-plus-circle-outline
                hint: "Warmer"
                delta: -100
            }
        }
    }

    // --------------------------------------------------------------- footer
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        width: parent.width
        text: panel.running ? "Auto follows sunrise and sunset for this machine's location. A hold stays until you give the schedule back." : "sunsetr is not running — choose a mode to start it."
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    component ModeRow: CursorSurface {
        id: row

        theme: panel.theme

        property var mode: null
        property int rowIndex: 0

        readonly property bool rowSelected: panel.cursorActive && panel.modeIndex === rowIndex
        readonly property bool isActive: panel.running && !!mode && mode.key === panel.activeKey

        hasCursor: rowSelected
        current: isActive
        implicitHeight: rowContent.implicitHeight + panel.theme.space(3)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) {
                panel.cursorActive = true;
                panel.modeIndex = row.rowIndex;
            }
            // A radio, not a toggle: re-choosing the active mode is a no-op.
            onClicked: if (!row.isActive)
                panel.nightlight.setMode(row.mode.key)
        }

        PanelHint {
            theme: panel.theme
            visible: rowMouse.containsMouse && !row.isActive
            anchor: row
            above: true
            text: row.mode ? row.mode.detail : ""
        }

        Item {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: Math.max(rowMark.implicitHeight, rowLabels.implicitHeight, rowCheck.implicitHeight)

            // Fixed-width slot so the label column lines up across rows
            // whatever each glyph's ink width is — the devservices row's
            // arrangement.
            OpticalGlyph {
                id: rowMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(5)
                text: row.mode ? row.mode.glyph : ""
                verticalInkCenter: true
                color: row.isActive ? panel.theme.textPrimary : panel.theme.textMuted
                pixelSize: panel.theme.fontPx(1.083)
            }

            Column {
                id: rowLabels

                anchors.left: rowMark.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: rowCheck.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                StyledText {
                    theme: panel.theme

                    width: parent.width
                    text: row.mode ? row.mode.label : ""
                    elide: Text.ElideRight
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true

                    width: parent.width
                    // The active row states the fact; the others state the
                    // offer. "Auto" showing its next transition is the one
                    // line in this panel that changes on its own.
                    text: {
                        if (!row.mode)
                            return "";
                        if (!row.isActive)
                            return row.mode.detail;
                        if (row.mode.key === "auto")
                            return panel.nightlight.nextText !== "" ? panel.nightlight.nextText : row.mode.detail;
                        return "Held — " + Model.kelvinText(panel.nightlight.temp);
                    }
                    color: row.isActive ? panel.theme.textPrimary : panel.theme.textMuted
                    elide: Text.ElideRight
                }
            }

            OpticalGlyph {
                id: rowCheck
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(4)
                text: row.isActive ? "󰄬" // md-check
                : ""
                verticalInkCenter: true
                color: panel.theme.accent
                pixelSize: panel.theme.fontPx(1.0)
            }
        }
    }

    // A bordered square holding one glyph — the devservices web button's
    // shape. `delta` is signed the way sunsetr counts: LOWER kelvin is
    // warmer, so the "warmer" button carries a negative step.
    component NudgeButton: ChipSurface {
        id: chip

        property string glyph: ""
        property string hint: ""
        property int delta: 0

        theme: panel.theme
        implicitWidth: panel.theme.space(8)
        implicitHeight: panel.theme.space(7)
        // An action, not a choice — `chosen` never fires.
        pointerOver: chipMouse.containsMouse

        OpticalGlyph {
            anchors.centerIn: parent
            text: chip.glyph
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(1.0)
        }

        // A MouseArea rather than a TapHandler, for the reason the
        // devservices web button documents: a TapHandler's passive grab lets
        // the press fall through to anything underneath.
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.nightlight.nudgeNightTemp(chip.delta)
        }

        PanelHint {
            theme: panel.theme
            visible: chipMouse.containsMouse
            anchor: chip
            above: true
            text: chip.hint
        }
    }
}
