import QtQuick
import "../components"
import "../../../components"

// Mail panel — the HEY boxes and what is waiting in each, in the family's
// visual language: a hero of the envelope over the state sentence with "sync
// now" as the headline control, then one row per box, count on the right.
//
// The boxes are listed in hey-notmuch.el's order, which is HEY's own, so this
// card and the notmuch hello screen read alike. Clicking a row opens that box
// in the running Emacs daemon and raises its window — see MailService's
// openBox, which is where the emacsclient invocation and the reason it needs
// the compositor's help are written down.
//
// The cursor model is the family's single-highlight one: j/k and the arrows
// walk the rows, Enter opens, s syncs, m opens the hello screen, r re-reads the
// state file. The first arrow press only reveals the cursor.
BarPanel {
    id: panel

    required property var mail

    panelTitle: ""
    cardWidth: theme.space(85)

    readonly property var boxes: mail.boxes || []

    readonly property int boxesWithMail: {
        if (!panel.mail.haveCounts)
            return 0;
        let found = 0;
        for (const box of panel.boxes) {
            if (panel.mail.countOf(box.key) > 0)
                found++;
        }
        return found;
    }

    // -------------------------------------------------------------- cursor
    property int boxIndex: 0
    property bool cursorActive: false

    function moveCursor(dy) {
        cursorActive = true;
        if (boxes.length === 0)
            return;
        boxIndex = Math.max(0, Math.min(boxes.length - 1, boxIndex + dy));
    }

    function selectedBox() {
        if (boxes.length === 0)
            return null;
        return boxes[Math.max(0, Math.min(boxIndex, boxes.length - 1))];
    }

    function activateCursor() {
        if (!cursorActive) {
            cursorActive = true;
            return;
        }
        openRow(selectedBox());
    }

    // Raising Emacs puts a window over wherever this card is hanging, so the
    // card has to go with it: a panel left open would sit on top of the box it
    // just asked for.
    function openRow(box) {
        if (!box)
            return;
        panel.mail.openBox(box);
        panel.close();
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
            panel.mail.sync();
            break;
        case Qt.Key_M:
            panel.mail.openHome();
            panel.close();
            break;
        case Qt.Key_R:
            panel.mail.refresh();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------ lifecycle
    // Re-read on open rather than trust the watcher blindly: it costs one
    // failed-or-cheap read and it covers the one gap a FileView has, an inotify
    // event that landed while the shell was starting. `openedAtMs` is the
    // reference clock the footer's "last counted" line is measured against.
    onPanelOpened: {
        panel.cursorActive = false;
        panel.boxIndex = 0;
        panel.openedAtMs = Date.now();
        panel.mail.refresh();
    }

    property real openedAtMs: 0

    // How far behind the published counts are, as of the moment the card
    // opened. Stamped rather than ticked: the only question this answers is
    // "has the sync stopped happening", mail-sync.timer's own interval is 15
    // minutes, and a clock up to a minute stale cannot change that answer.
    // (HubSyncService keeps a 60-second tick for its "4 minutes ago" line
    // because it prints minutes; this prints a wall clock and so starts no
    // timer at all.)
    readonly property real syncAgeMs: {
        if (!panel.mail.haveCounts || panel.mail.updatedIso === "")
            return -1;
        const then = Date.parse(panel.mail.updatedIso);
        if (isNaN(then))
            return -1;
        return Math.max(0, panel.openedAtMs - then);
    }

    // Two missed timer intervals. Under IDLE the counts are seconds old and the
    // 15-minute timer is the floor even when IDLE has died quietly, so half an
    // hour of silence means the sync itself has stopped — which is exactly the
    // failure a push-only design hides by sitting there looking healthy.
    readonly property bool syncStale: syncAgeMs > 30 * 60 * 1000

    readonly property string syncLine: {
        if (panel.syncAgeMs < 0)
            return "No counts have been published on this machine yet — a sync writes them.";
        const stamp = new Date(Date.parse(panel.mail.updatedIso));
        const sameDay = Qt.formatDateTime(stamp, "yyyy-MM-dd") === Qt.formatDateTime(new Date(panel.openedAtMs), "yyyy-MM-dd");
        const when = Qt.formatDateTime(stamp, sameDay ? "HH:mm" : "d MMM HH:mm");
        return panel.syncStale ? "Last counted " + when + " — the 15-minute fallback sync has not run since, so something is wrong." : "Last counted " + when + ".";
    }

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Mail"
        // Terse on purpose. Two trailing controls leave the label column about
        // 31 characters wide at space(85), and the first draft ("1 unread in
        // your Imbox · 219 to screen") elided to "…219 to…" — the number the
        // sentence existed to report was the part that got cut.
        meta: {
            if (panel.mail.syncing)
                return "Syncing…";
            if (!panel.mail.haveCounts)
                return "No counts published yet";
            if (panel.mail.imbox === 0 && panel.mail.screener === 0)
                return "Nothing waiting";
            const head = panel.mail.imbox === 0 ? "Imbox clear" : panel.mail.imbox + " unread";
            return panel.mail.screener > 0 ? head + " · " + panel.mail.screener + " to screen" : head;
        }
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            text: "󰇮" // md-email
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.mail.imbox > 0 ? panel.theme.textPrimary : panel.theme.textMuted
            opacity: panel.mail.imbox > 0 ? 1.0 : 0.6
        }

        trailing: [
            // The hello screen, which is the one thing in mail.json that no row
            // below can reach: bundled senders are drawn there, one row per
            // sender, and have no box of their own.
            GlyphButton {
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰉋" // md-folder
                hint: "Open all boxes"
                onActivated: {
                    panel.mail.openHome();
                    panel.close();
                }
            },
            // bin/mail-sync, the same flock-serialised entry point imapnotify
            // and the timer call — so pressing this while a sync is running is
            // safe, and the button is disabled only while OUR invocation is in
            // flight.
            GlyphButton {
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰓦" // md-sync
                enabled: !panel.mail.syncing
                hint: "Sync now"
                onActivated: panel.mail.sync()
            }
        ]
    }

    // ---------------------------------------------------------- action/error
    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.mail.actionStatus !== "" || panel.mail.lastError !== ""
        width: parent.width
        text: panel.mail.lastError !== "" ? panel.mail.lastError : panel.mail.actionStatus
        color: panel.mail.lastError !== "" ? panel.theme.error : panel.theme.textMuted
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
            label: "BOXES"
            value: panel.mail.haveCounts ? (panel.boxesWithMail > 0 ? panel.boxesWithMail + " WITH MAIL" : "ALL CLEAR") : "NO COUNTS"
        }

        Column {
            id: rowColumn

            width: parent.width
            spacing: panel.theme.space(0.5)

            Repeater {
                model: panel.boxes

                BoxRow {
                    required property var modelData
                    required property int index

                    width: rowColumn.width
                    box: modelData
                    rowIndex: index
                }
            }
        }
    }

    // --------------------------------------------------------------- footer
    StyledText {
        theme: panel.theme
        role: StyledText.Caption

        width: parent.width
        text: panel.syncLine
        color: panel.syncStale ? panel.theme.error : panel.theme.textMuted
        wrapMode: Text.WordWrap
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        width: parent.width
        text: "The notmuch post-new hook publishes these after every sync — about a second after mail arrives, because a push connection holds the mailbox open. Click a box to open it in Emacs."
        wrapMode: Text.WordWrap
    }

    // The one count in mail.json with no row: a bundled sender's threads leave
    // the Imbox list and appear as one row per sender in the hello screen's
    // Bundles section, so there is no box to open and no honest row to draw.
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        visible: panel.mail.bundled > 0
        width: parent.width
        text: panel.mail.bundled + (panel.mail.bundled === 1 ? " unread message is" : " unread messages are") + " rolled up into Bundles, which lives on the hello screen rather than in a box."
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    // No per-row hover hint: every one of the nine rows does the same thing, so
    // nine copies of "Open in Emacs" would be noise, and a hint on the first or
    // last row has nowhere to hang that does not cover the header or the footer.
    // The pointer cursor and the footer sentence carry it instead.
    component BoxRow: CursorSurface {
        id: row

        theme: panel.theme

        property var box: null
        property int rowIndex: 0

        readonly property int boxCount: panel.mail.countOf(row.box ? row.box.key : "")
        readonly property bool rowSelected: panel.cursorActive && panel.boxIndex === row.rowIndex
        readonly property bool hasMail: panel.mail.haveCounts && row.boxCount > 0

        hasCursor: rowSelected
        // `current` is the family's "this is the active choice" fill, and none
        // of these is a choice — a box is a destination. The Imbox takes it when
        // it has unread mail, because that is the one row this widget exists
        // for; every other row carries its state in the count alone.
        current: row.hasMail && row.box && row.box.key === "imbox"
        implicitHeight: rowContent.implicitHeight + panel.theme.space(2.5)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) {
                panel.cursorActive = true;
                panel.boxIndex = row.rowIndex;
            }
            onClicked: panel.openRow(row.box)
        }

        Item {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: Math.max(rowLabel.implicitHeight, rowCount.implicitHeight)

            StyledText {
                id: rowLabel
                theme: panel.theme
                role: StyledText.BodyLarge

                anchors.left: parent.left
                anchors.right: rowCount.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                text: row.box ? row.box.label : ""
                color: row.hasMail ? panel.theme.textPrimary : panel.theme.textMuted
                elide: Text.ElideRight
            }

            StyledText {
                id: rowCount
                theme: panel.theme
                role: StyledText.BodyLarge
                mono: true

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                // An em-dash and not a 0 while nothing has been published: "the
                // hook has never run here" and "that box is empty" are
                // different answers, and one glyph for both is how a widget
                // starts lying quietly.
                text: panel.mail.haveCounts ? row.boxCount : "—"
                color: row.hasMail ? panel.theme.textPrimary : panel.theme.textMuted
            }
        }
    }
}
