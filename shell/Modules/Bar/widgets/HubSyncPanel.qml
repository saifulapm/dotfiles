import QtQuick
import "../components"
import "../../../components"
import "HubSyncModel.js" as Model

// Sync panel — the Dropbox hub's six units, in the family's visual language:
// a hero of the sync mark over a one-line verdict, the headline reason when
// something is wrong, and one row per unit saying what it carries and when it
// last actually worked.
//
// The whole point of this panel is the three questions the old notification
// could not answer — what is synced, when, and which one broke — plus the one
// thing it never offered at all: a way to try again. Every row retries on
// click; the footer button runs the whole round. Both go through
// bin/qshell-sync, which holds a flock, so a click during the timer's own
// round is a no-op rather than a collision.
//
// The ssh row is the one that can ask a question back. Key material cannot be
// merged, so when two machines have both changed ~/.ssh the unit stops and
// says so, and the row grows a pair of buttons naming the two answers. That
// is also the state a machine sits in the FIRST time it meets a populated hub
// — which is exactly when you want to be asked rather than obeyed.
//
// The cursor model is the family's single-highlight one: j/k and the arrows
// walk the rows, Enter retries the selected unit, s syncs everything, y
// copies the re-auth command. The first arrow press only reveals the cursor.
BarPanel {
    id: panel

    required property var sync

    panelTitle: ""
    cardWidth: theme.space(92)

    readonly property var units: sync.units || []
    readonly property string headline: Model.headlineError(sync.status)
    readonly property bool authBroken: {
        const failed = Model.failedUnits(sync.status);
        for (var i = 0; i < failed.length; i++) {
            if (failed[i].errorKind === "auth")
                return true;
        }
        return false;
    }

    // -------------------------------------------------------------- cursor
    property int unitIndex: 0
    property bool cursorActive: false

    function moveCursor(dy) {
        cursorActive = true;
        if (units.length === 0)
            return;
        unitIndex = Math.max(0, Math.min(units.length - 1, unitIndex + dy));
    }

    function selectedUnit() {
        if (units.length === 0)
            return null;
        return units[Math.max(0, Math.min(unitIndex, units.length - 1))];
    }

    function activateCursor() {
        if (!cursorActive) {
            cursorActive = true;
            return;
        }
        const unit = selectedUnit();
        if (unit)
            panel.sync.retry(unit.id);
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
        case Qt.Key_S:
            panel.sync.syncAll();
            break;
        case Qt.Key_Y:
            panel.sync.copyReauthCommand();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------ lifecycle
    // No probe on open: status.json is watched, so what is on screen is
    // already current. Only the relative clock is re-stamped, so a panel
    // opened an hour after the last round does not say "just now".
    onPanelOpened: {
        panel.cursorActive = false;
        panel.unitIndex = 0;
        panel.sync.nowMs = Date.now();
    }

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Sync"
        meta: Model.heroMeta(panel.sync.status, panel.sync.nowMs)
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)
        metaColor: panel.sync.anyFailing ? panel.theme.error : panel.theme.textMuted

        icon: OpticalGlyph {
            id: heroGlyph
            text: "󰓦" // md-sync
            pixelSize: panel.theme.fontPx(1.6)
            color: panel.sync.anyFailing ? panel.theme.error : panel.theme.textPrimary
            opacity: panel.sync.running ? 1.0 : 0.85

            // Turns only while a round is actually in flight — the animation
            // is the progress indicator, so it must never spin idle.
            RotationAnimator on rotation {
                running: panel.sync.running
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1400
            }
            onRotationChanged: if (!panel.sync.running && rotation !== 0)
                rotation = 0
        }

        // "Sync everything" lives in the hero rather than the footer: it is
        // the panel's primary action, and the header is where this family
        // puts the one control that acts on the whole card (the AI panel's
        // refresh, the bluetooth and audio master switches). It also keeps
        // the rows and the footer note free of a button that competes with
        // the per-row retries.
        trailing: GlyphButton {
            anchors.verticalCenter: parent.verticalCenter
            theme: panel.theme
            glyph: "󰓦" // md-sync
            hint: panel.sync.running ? "Syncing…" : "Sync everything now"
            enabled: !panel.sync.running
            onActivated: panel.sync.syncAll()
        }
    }

    // ------------------------------------------------------------- headline
    Text {
        visible: panel.headline !== ""
        width: parent.width
        text: panel.headline
        color: panel.theme.error
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.833)
        wrapMode: Text.WordWrap
    }

    // The one failure the shell cannot fix for itself: OAuth re-consent is a
    // browser flow, so the panel hands over the command instead of pretending
    // it can run it (the tailscale panel's authorize-row precedent).
    InfoPair {
        visible: panel.authBroken
        width: parent.width
        theme: panel.theme
        label: "Re-authorize"
        value: panel.sync.reauthCommand
        copyValue: panel.sync.reauthCommand
        onCopyRequested: panel.sync.copyReauthCommand()
    }

    Text {
        visible: panel.sync.lastError !== ""
        width: parent.width
        text: panel.sync.lastError
        color: panel.theme.error
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.833)
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
            label: "WHAT SYNCS"
            value: panel.units.length === 0 ? "NEVER RUN" : panel.sync.okCount + "/" + panel.units.length + " OK"
            valueColor: panel.sync.anyFailing ? panel.theme.error : panel.theme.textPrimary
        }

        Column {
            id: rowColumn

            width: parent.width
            spacing: panel.theme.space(0.5)

            Repeater {
                model: panel.units

                UnitRow {
                    required property var modelData
                    required property int index

                    width: rowColumn.width
                    unit: modelData
                    rowIndex: index
                }
            }
        }

        // Before the first round there are no rows at all, and an empty panel
        // explains nothing.
        Text {
            visible: panel.units.length === 0
            width: parent.width
            text: "No sync has finished on this machine yet. Run one to fill this in."
            color: panel.theme.textMuted
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.792)
            wrapMode: Text.WordWrap
        }
    }

    Separator {
        theme: panel.theme
    }

    // --------------------------------------------------------------- footer
    Text {
        width: parent.width
        text: panel.sync.actionStatus !== "" ? panel.sync.actionStatus : (panel.sync.status.machine !== "" ? "This machine is " + panel.sync.status.machine + " · every 15 min · click a row to sync just that one" : "every 15 min")
        color: panel.sync.actionStatus !== "" ? panel.theme.textPrimary : panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.75)
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    component UnitRow: CursorSurface {
        id: row

        theme: panel.theme

        property var unit: null
        property int rowIndex: 0

        readonly property string state: Model.unitState(row.unit, panel.sync.status)
        readonly property bool rowSelected: panel.cursorActive && panel.unitIndex === rowIndex
        readonly property bool isFailed: state === "failed" || state === "conflict"
        readonly property bool isBusy: state === "running"
        readonly property bool isConflict: state === "conflict"

        hasCursor: rowSelected
        current: state === "ok"
        implicitHeight: rowContent.implicitHeight + panel.theme.space(3)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: row.isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) {
                panel.cursorActive = true;
                panel.unitIndex = row.rowIndex;
            }
            // A conflict is not retryable — running the same round again just
            // re-detects it — so the row click does nothing and the two adopt
            // buttons are the only way forward.
            onClicked: if (!row.isConflict)
                panel.sync.retry(row.unit.id)
        }

        PanelHint {
            theme: panel.theme
            visible: rowMouse.containsMouse && !row.isBusy && !row.isConflict
            anchor: row
            above: true
            text: "Sync this now"
        }

        Item {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: Math.max(rowMark.implicitHeight, rowLabels.implicitHeight)

            OpticalGlyph {
                id: rowMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(5)
                text: Model.unitGlyph(row.unit ? row.unit.id : "")
                verticalInkCenter: true
                color: row.isFailed ? panel.theme.error : (row.state === "ok" || row.isBusy ? panel.theme.textPrimary : panel.theme.textMuted)
                pixelSize: panel.theme.fontPx(1.083)
            }

            Column {
                id: rowLabels

                anchors.left: rowMark.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                Text {
                    width: parent.width
                    text: row.unit ? row.unit.label : ""
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: Model.unitLine(row.unit, panel.sync.status, panel.sync.nowMs)
                    color: row.isFailed ? panel.theme.error : (row.state === "ok" || row.isBusy ? panel.theme.textPrimary : panel.theme.textMuted)
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                    elide: Text.ElideRight
                }

                // The transport's own words, kept for the failure that is not
                // one of the two named kinds — without it a row can only say
                // "failed" and the reason lives in a journal nobody opens.
                Text {
                    visible: row.isFailed && !row.isConflict && row.unit && row.unit.error !== ""
                    width: parent.width
                    text: row.unit ? row.unit.error : ""
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.708)
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                // Only the ssh unit can reach the conflict state, and only
                // there is a choice needed. Two buttons, both naming the side
                // that WINS, because "resolve" would not say which way.
                //
                // They sit under the sentence rather than beside it: to the
                // right they squeezed the label column down to "changed on
                // two …", which hid the one line explaining what the buttons
                // are even asking.
                //
                // PanelButton taps with a TapHandler, whose passive grab lets
                // the press fall through to the row's MouseArea underneath.
                // Harmless here and only here: these buttons exist ONLY in
                // the conflict state, which is exactly the state where the
                // row's own click is already a deliberate no-op.
                Item {
                    visible: row.isConflict
                    width: parent.width
                    implicitHeight: adoptRow.implicitHeight + panel.theme.space(1.5)

                    Row {
                        id: adoptRow

                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        spacing: panel.theme.space(1)

                        PanelButton {
                            theme: panel.theme
                            label: "Use this machine"
                            enabled: !panel.sync.running
                            onClicked: panel.sync.adoptSsh("local")
                        }

                        PanelButton {
                            theme: panel.theme
                            label: "Use the hub"
                            enabled: !panel.sync.running
                            onClicked: panel.sync.adoptSsh("remote")
                        }
                    }
                }
            }
        }
    }
}
