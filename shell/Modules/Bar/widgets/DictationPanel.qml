import QtQuick
import "../components"
import "../../../components"
import "DictationModel.js" as Model

// Dictation panel — what voxtype is doing, what it is doing it with, and what
// it has heard.
//
// Upstream ships a settings panel of its own (peteonrails/voxtype's
// omarchy-plugin/) that renders all 95 keys of `config schema --json`. This is
// deliberately not that. A panel that lists every setting is a TUI with worse
// ergonomics, and `voxtype configure` already is the TUI — it is one chip
// away in the header. What is here instead is the handful of things worth
// having in a bar panel: the state, the two knobs that change day to day
// (model and language), and the two questions voxtype itself cannot answer
// because it keeps no record — what did I dictate, and how much do I dictate.
//
// The facts line follows upstream's rule and it is the rule worth copying:
// every reading is measured, and one that could not be taken is left out
// rather than guessed, so a missing item means "not known" and never "zero".
//
// r toggles recording, d starts or stops the daemon, / searches the history,
// c copies the selected transcript, p pins it.
BarPanel {
    id: panel

    required property DictationService dictation

    panelTitle: ""
    cardWidth: theme.space(92)

    // The history list scrolls rather than growing the card past the screen.
    readonly property real listCap: theme.space(60)

    property string query: ""
    property int cursorIndex: -1

    readonly property var rows: Model.pinnedFirst(panel.dictation.history.filter(row => Model.matches(row, panel.query)), panel.dictation.pins)

    readonly property var selected: cursorIndex >= 0 && cursorIndex < rows.length ? rows[cursorIndex] : null

    readonly property var badge: dictation.accelBadge

    // The panel is the only thing that wants the history files watched or the
    // facts taken, so it says so on the way in and takes it back on the way
    // out. A shell whose dictation panel is never opened pays for none of it.
    onPanelOpened: {
        panel.dictation.panelOpen = true;
        panel.dictation.refreshFacts();
    }
    onPanelClosed: {
        panel.dictation.panelOpen = false;
        panel.query = "";
        panel.cursorIndex = -1;
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_R:
            panel.dictation.toggleRecording();
            break;
        case Qt.Key_D:
            if (panel.dictation.unitActive)
                panel.dictation.stopDaemon();
            else
                panel.dictation.startDaemon();
            break;
        case Qt.Key_Slash:
            searchField.forceFocus();
            break;
        case Qt.Key_C:
            if (panel.selected)
                panel.dictation.copyText(panel.selected.text);
            break;
        case Qt.Key_P:
            if (panel.selected)
                panel.dictation.togglePin(panel.selected.id);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------------ hero
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Dictation"
        meta: Model.heroMeta(panel.dictation.dictationState, panel.dictation.unitActive)
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)
        metaColor: panel.dictation.recording ? panel.theme.accent : panel.theme.textMuted

        icon: OpticalGlyph {
            // md-microphone, md-timer_sand while the transcript is made — the
            // same pair the bar indicator uses, so the panel and the glyph
            // that opened it never disagree.
            text: panel.dictation.dictationState === "transcribing" ? "󰔟" : "󰍬"
            pixelSize: panel.theme.fontPx(1.6)
            color: panel.dictation.recording ? panel.theme.accent : panel.theme.textPrimary
            opacity: panel.dictation.busy ? 1.0 : 0.6
        }

        trailing: StyledText {
            theme: panel.theme
            role: StyledText.Caption
            mono: true

            visible: panel.badge !== null
            text: panel.badge ? panel.badge.text : ""
            color: panel.badge && panel.badge.urgent ? panel.theme.error : panel.theme.textMuted
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        mono: true
        muted: true

        width: parent.width
        text: panel.dictation.factsLine
        elide: Text.ElideRight
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: text !== ""
        width: parent.width
        // Ranked, loudest first. A failed unit beats everything because it
        // reports no daemon state at all and every other reading on the card
        // goes quiet with it; a stale daemon beats a stray command error
        // because it means the settings below describe a build that is not
        // the one running.
        text: panel.dictation.unitFailed ? "voxtype.service failed — check `systemctl --user status voxtype`" : panel.dictation.daemonStale ? "Running daemon is " + (panel.dictation.facts.daemonVersion || "an older build") + ", the binary is " + (panel.dictation.facts.version || "newer") + " — restart to apply." : panel.dictation.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        visible: text !== ""
        width: parent.width
        text: panel.dictation.actionStatus
    }

    Separator {
        theme: panel.theme
    }

    // -------------------------------------------------------------- controls
    Row {
        id: controlRow
        width: parent.width
        spacing: panel.theme.space(1.5)

        readonly property real cellWidth: (width - spacing * 3) / 4

        ActionChip {
            width: controlRow.cellWidth
            glyph: panel.dictation.recording ? "󰓛" : "󰑊" // stop / record
            label: panel.dictation.recording ? "Stop" : "Record"
            lit: panel.dictation.recording
            onActivated: panel.dictation.toggleRecording()
        }

        ActionChip {
            width: controlRow.cellWidth
            glyph: "󰐥"
            label: panel.dictation.unitActive ? "Daemon on" : "Daemon off"
            lit: panel.dictation.unitActive
            // Refusing rather than racing: stopping the daemon out from under
            // a recording throws away the utterance being spoken, which is
            // exactly what bin/voxtype-idle-stop refuses to do for the same
            // reason.
            allowed: !panel.dictation.busy
            onActivated: panel.dictation.unitActive ? panel.dictation.stopDaemon() : panel.dictation.startDaemon()
        }

        ActionChip {
            width: controlRow.cellWidth
            glyph: "󰑐"
            label: "Restart"
            allowed: panel.dictation.unitActive && !panel.dictation.busy
            onActivated: panel.dictation.restartDaemon()
        }

        ActionChip {
            width: controlRow.cellWidth
            glyph: "󰒓"
            label: "Settings"
            onActivated: panel.dictation.openConfigurator()
        }
    }

    // The resting state of this microphone is muted, which is the right one
    // for a laptop and the reason bin/voxtype-mic-gate exists. Saying so
    // plainly beats leaving someone to wonder why the Mic widget shows a
    // crossed-out mic while dictation works fine.
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        visible: panel.dictation.micMuted === true && !panel.dictation.recording
        width: parent.width
        text: "Microphone is muted at rest — dictation opens it for the length of a take."
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
    }

    // --------------------------------------------------------------- meeting
    // Long-form continuous recording, which is a different thing from
    // dictation and says so: no text is typed anywhere, a transcript
    // accumulates on disk instead. It gets its own row because the state is
    // invisible otherwise — a meeting records for an hour with nothing on
    // screen, which is exactly the kind of thing a panel should show.
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "MEETING"
            value: panel.dictation.meetingActive ? panel.dictation.meetingState.toUpperCase() : ""
            valueColor: panel.dictation.meetingRecording ? panel.theme.error : panel.theme.textPrimary
        }

        Row {
            id: meetingRow
            width: parent.width
            spacing: panel.theme.space(1.5)

            readonly property real cellWidth: (width - spacing * 2) / 3

            ActionChip {
                width: meetingRow.cellWidth
                glyph: panel.dictation.meetingActive ? "󰓛" : "󰑊" // stop / record
                label: panel.dictation.meetingActive ? "Stop" : "Start"
                lit: panel.dictation.meetingRecording
                onActivated: panel.dictation.meeting(panel.dictation.meetingActive ? "stop" : "start")
            }

            ActionChip {
                width: meetingRow.cellWidth
                glyph: panel.dictation.meetingState === "paused" ? "󰐊" : "󰏤" // play / pause
                label: panel.dictation.meetingState === "paused" ? "Resume" : "Pause"
                allowed: panel.dictation.meetingActive
                onActivated: panel.dictation.meeting(panel.dictation.meetingState === "paused" ? "resume" : "pause")
            }

            ActionChip {
                width: meetingRow.cellWidth
                glyph: "󰈙" // md-file-document
                label: "Transcripts"
                // A list of past meetings is a reading task, not a panel one —
                // the CLI already prints it well and can export and summarise.
                onActivated: panel.dictation.openMeetings()
            }
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Caption
            muted: true

            width: parent.width
            text: panel.dictation.meetingActive ? "Recording to ~/.local/share/voxtype/meetings — nothing is typed." : "Long-form recording with timestamps, both sides of a call. Mod+Alt+M."
            wrapMode: Text.WordWrap
        }
    }

    Separator {
        theme: panel.theme
    }

    // ----------------------------------------------------------------- model
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "MODEL"
            value: panel.dictation.engine
        }

        // Only what is on disk. Offering a model that is not downloaded would
        // be offering a switch that silently stops transcription until a
        // 466 MB fetch nobody asked for finishes.
        Flow {
            id: modelFlow
            width: parent.width
            spacing: panel.theme.space(1)

            readonly property var installed: panel.dictation.models.filter(m => m.installed)

            Repeater {
                model: modelFlow.installed

                ChoiceChip {
                    required property var modelData
                    text: modelData.name
                    chosenValue: modelData.name === panel.dictation.model
                    onActivated: panel.dictation.setModel(modelData.name)
                }
            }

            StyledText {
                theme: panel.theme
                role: StyledText.Caption
                muted: true
                visible: modelFlow.installed.length < 2
                text: "Only one model on disk — `voxtype setup model` downloads others."
            }
        }
    }

    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "LANGUAGE"
            value: panel.dictation.language
        }

        Flow {
            width: parent.width
            spacing: panel.theme.space(1)

            Repeater {
                // The schema's own enum, so the panel can never offer a value
                // `config set` would reject.
                model: panel.dictation.languages

                ChoiceChip {
                    required property string modelData
                    text: modelData
                    chosenValue: modelData === panel.dictation.language
                    onActivated: panel.dictation.setLanguage(modelData)
                }
            }
        }
    }

    Separator {
        theme: panel.theme
    }

    // ------------------------------------------------------------- talk time
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "TALK TIME"
            value: Model.talkTimeText(panel.dictation.totals.secs)
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Small
            muted: panel.dictation.totals.takes === 0

            width: parent.width
            text: Model.summaryText(panel.dictation.totals)
            elide: Text.ElideRight
        }

        // Bars rather than a line: fourteen daily totals are counts, and a
        // line between them would draw slopes through days that never
        // happened. Every day in the window is drawn, including the empty
        // ones — a chart that skipped them would compress a fortnight of not
        // dictating into yesterday.
        Row {
            id: chartRow
            // An all-empty chart is fourteen invisible stubs under fourteen
            // day letters, i.e. a block of nothing where the sentence above
            // has already said there is nothing. It appears with the first
            // dictation.
            visible: panel.dictation.totals.takes > 0
            width: parent.width
            height: visible ? panel.theme.space(11) : 0
            spacing: panel.theme.space(0.75)

            readonly property real barWidth: (width - spacing * (panel.dictation.bars.length - 1)) / panel.dictation.bars.length

            Repeater {
                model: panel.dictation.bars

                Item {
                    required property var modelData

                    width: chartRow.barWidth
                    height: chartRow.height

                    Rectangle {
                        anchors.bottom: dayLabel.top
                        anchors.bottomMargin: panel.theme.space(0.75)
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        // A day with any dictation at all keeps a visible stub
                        // rather than rounding to nothing: "a little" and
                        // "none" must not draw the same.
                        height: modelData.takes === 0 ? 1 : Math.max(2, modelData.ratio * (chartRow.height - panel.theme.space(4)))
                        radius: 2
                        color: modelData.today ? panel.theme.accent : panel.theme.textPrimary
                        opacity: modelData.takes === 0 ? 0.18 : (modelData.today ? 1.0 : 0.45)

                        Behavior on height {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    StyledText {
                        id: dayLabel
                        theme: panel.theme
                        role: StyledText.Caption
                        muted: !modelData.today

                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        color: modelData.today ? panel.theme.accent : panel.theme.textPrimary
                    }

                    HoverHandler {
                        id: barHover
                    }

                    PanelHint {
                        theme: panel.theme
                        visible: barHover.hovered
                        anchor: parent
                        above: true
                        text: modelData.date + " · " + (modelData.takes === 0 ? "nothing" : Model.durationText(modelData.secs) + ", " + modelData.words + " words")
                    }
                }
            }
        }

        // Where the words actually went. Buckets, not app names: a list of
        // every binary that ever received a dictation answers nothing.
        Row {
            width: parent.width
            spacing: panel.theme.space(2)
            visible: panel.dictation.destinations.length > 0

            Repeater {
                model: panel.dictation.destinations

                StyledText {
                    required property var modelData
                    theme: panel.theme
                    role: StyledText.Caption
                    muted: true
                    text: modelData.name + " " + modelData.count
                }
            }
        }
    }

    Separator {
        theme: panel.theme
    }

    // --------------------------------------------------------------- history
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "HISTORY"
            value: panel.dictation.capturePaused ? "PAUSED" : String(panel.dictation.history.length)
            valueColor: panel.dictation.capturePaused ? panel.theme.error : panel.theme.textPrimary
        }

        PanelTextField {
            id: searchField

            theme: panel.theme
            width: parent.width
            visible: panel.dictation.history.length > 0
            inputFont: panel.theme.fontUi
            placeholder: "Search what you have dictated"

            onTextEdited: text => {
                panel.query = text;
                panel.cursorIndex = text === "" ? -1 : 0;
            }
            onMoveRequested: delta => {
                if (panel.rows.length === 0)
                    return;
                panel.cursorIndex = Math.max(0, Math.min(panel.rows.length - 1, panel.cursorIndex + delta));
            }
            onAccepted: if (panel.selected)
                panel.dictation.copyText(panel.selected.text)
            onCancelled: {
                // Narrowest thing first: the query, then the panel.
                if (panel.query !== "") {
                    text = "";
                    panel.query = "";
                    panel.cursorIndex = -1;
                } else {
                    panel.close();
                }
            }
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Small
            muted: true

            visible: panel.rows.length === 0
            width: parent.width
            text: panel.dictation.history.length === 0 ? "Nothing yet. Every finished dictation lands here — it never leaves this machine." : "No dictation matches that."
            wrapMode: Text.WordWrap
        }

        ListView {
            id: historyList

            width: parent.width
            height: Math.min(contentHeight, panel.listCap)
            spacing: panel.theme.space(1)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            model: panel.rows
            currentIndex: panel.cursorIndex
            onCurrentIndexChanged: if (currentIndex >= 0)
                Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.Contain))

            delegate: ChipSurface {
                id: historyRow

                required property var modelData
                required property int index

                theme: panel.theme
                width: ListView.view.width
                implicitHeight: rowColumn.implicitHeight + panel.theme.space(2.5)
                hasCursor: panel.cursorIndex === index
                pointerOver: rowHover.hovered

                Column {
                    id: rowColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.rightMargin: panel.theme.space(2)
                    spacing: panel.theme.space(0.25)

                    StyledText {
                        theme: panel.theme
                        width: parent.width
                        text: historyRow.modelData.text
                        // Two lines: enough to recognise a paragraph, not so
                        // much that six of them fill the card.
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        // A dropped hallucination is kept but never typed, so
                        // it reads as a ghost of a row: still legible, still
                        // copyable, visibly not something that happened.
                        muted: historyRow.modelData.dropped === true
                    }

                    Row {
                        spacing: panel.theme.space(1)

                        StyledText {
                            theme: panel.theme
                            role: StyledText.Caption
                            mono: true
                            muted: true
                            text: {
                                const parts = [Model.relativeAt(historyRow.modelData.at)];
                                const dur = Model.durationText(historyRow.modelData.secs);
                                if (dur !== "")
                                    parts.push(dur);
                                if (historyRow.modelData.app)
                                    parts.push(historyRow.modelData.app);
                                // Said rather than shown with an icon: "not
                                // typed" is the whole story of the row, and it
                                // has to be unambiguous that nothing reached
                                // the window.
                                if (historyRow.modelData.dropped === true)
                                    parts.push("not typed");
                                return parts.join(" · ");
                            }
                        }

                        OpticalGlyph {
                            visible: panel.dictation.isPinned(historyRow.modelData.id)
                            text: "󰐃" // md-pin
                            pixelSize: panel.theme.fontPx(0.75)
                            color: panel.theme.accent
                        }
                    }
                }

                HoverHandler {
                    id: rowHover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered)
                        panel.cursorIndex = historyRow.index
                }

                // Right-click pins, left-click copies — the two things wanted
                // often enough not to be behind a menu.
                //
                // One handler per button, which is what BarButton does and
                // now for a measured reason: a single handler taking both and
                // branching on `eventPoint.event.button` throws "Cannot read
                // property 'button' of undefined" on this Qt, and a throwing
                // onTapped silently does NOTHING — the row looked inert under
                // both buttons while its hover highlight worked perfectly,
                // which is a confusing thing to debug from the outside.
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: panel.dictation.copyText(historyRow.modelData.text)
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: panel.dictation.togglePin(historyRow.modelData.id)
                }
            }
        }
    }

    // ---------------------------------------------------------------- footer
    Item {
        width: parent.width
        implicitHeight: footerText.implicitHeight

        StyledText {
            id: footerText
            theme: panel.theme
            role: StyledText.Caption
            muted: true

            anchors.left: parent.left
            anchors.right: footerChips.left
            anchors.rightMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            text: "Click a line to copy it, right-click to pin. Pinned lines survive Clear."
            wrapMode: Text.WordWrap
        }

        Row {
            id: footerChips

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(1)

            ActionChip {
                width: panel.theme.space(8)
                compact: true
                glyph: panel.dictation.capturePaused ? "󰐊" : "󰏤" // play / pause
                hint: panel.dictation.capturePaused ? "Resume logging" : "Pause logging"
                onActivated: panel.dictation.capture([panel.dictation.capturePaused ? "resume" : "pause"])
            }

            ActionChip {
                width: panel.theme.space(8)
                compact: true
                glyph: "󰩹" // md-delete-outline
                hint: "Clear unpinned history"
                allowed: panel.dictation.history.length > 0
                onActivated: panel.dictation.capture(["clear"])
            }
        }
    }

    // ------------------------------------------------------------ components
    // A control that does something, as opposed to one that picks a value.
    component ActionChip: ChipSurface {
        id: actionChip

        property string glyph: ""
        property string label: ""
        property string hint: ""
        property bool lit: false
        property bool allowed: true
        property bool compact: false

        signal activated

        theme: panel.theme
        implicitHeight: compact ? panel.theme.space(7) : actionContent.implicitHeight + panel.theme.space(3)
        chosen: actionChip.lit
        pointerOver: actionHover.hovered
        // Disabled while a write is in flight as well as when the action makes
        // no sense: two `voxtype config set` calls racing would leave the panel
        // reporting whichever finished last.
        interactive: actionChip.allowed && !panel.dictation.pending

        Column {
            id: actionContent
            anchors.centerIn: parent
            spacing: panel.theme.space(0.5)

            OpticalGlyph {
                anchors.horizontalCenter: parent.horizontalCenter
                text: actionChip.glyph
                pixelSize: panel.theme.fontPx(1.333)
                color: actionChip.lit ? panel.theme.accent : panel.theme.textPrimary
                opacity: actionChip.interactive ? 1.0 : 0.4
            }

            StyledText {
                theme: panel.theme
                role: StyledText.Small

                visible: !actionChip.compact && actionChip.label !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                text: actionChip.label
                color: actionChip.lit ? panel.theme.accent : panel.theme.textPrimary
                opacity: actionChip.interactive ? 1.0 : 0.4
            }
        }

        HoverHandler {
            id: actionHover
            enabled: actionChip.interactive
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            enabled: actionChip.interactive
            onTapped: actionChip.activated()
        }

        PanelHint {
            theme: panel.theme
            visible: actionHover.hovered && actionChip.hint !== ""
            anchor: actionChip
            above: true
            text: actionChip.hint
        }
    }

    // A control that picks one value out of a set.
    component ChoiceChip: ChipSurface {
        id: choiceChip

        property alias text: choiceLabel.text
        property bool chosenValue: false

        signal activated

        theme: panel.theme
        implicitWidth: choiceLabel.implicitWidth + panel.theme.space(4)
        implicitHeight: panel.theme.space(6)
        chosen: choiceChip.chosenValue
        pointerOver: choiceHover.hovered
        interactive: !panel.dictation.pending

        StyledText {
            id: choiceLabel
            theme: panel.theme
            role: StyledText.Small
            anchors.centerIn: parent
            color: choiceChip.chosenValue ? panel.theme.accent : panel.theme.textPrimary
            opacity: choiceChip.interactive ? 1.0 : 0.4
        }

        HoverHandler {
            id: choiceHover
            enabled: choiceChip.interactive
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            enabled: choiceChip.interactive
            onTapped: choiceChip.activated()
        }
    }
}
