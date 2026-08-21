import QtQuick
import "../components"
import "../../../components"
import "PassModel.js" as Model

// Password panel — type a few letters, press Enter, the password is on the
// clipboard and clears itself 45 seconds later.
//
// The matching is subsequence rather than substring, so `ghb` finds
// `web/github.com`. That is the behaviour worth having in a store organized
// into folders: the thing you remember is rarely the path.
//
// The keys, and what each one is for:
//
//   Enter              copy the password        (pass -c, self-clearing)
//   Alt+U              copy the username
//   Alt+O              copy a fresh TOTP code   (needs pass-otp)
//   Ctrl+Enter         type the password into the window you came from
//   Ctrl+Shift+Enter   type the username
//   Alt+E              open the entry in `pass edit`
//   Alt+N              capture a 2FA QR off the screen (needs screenshot-qr)
//
// The typing pair exists because a clipboard is a shared surface every other
// application can read; typing goes straight into the focused window and
// leaves nothing behind. Both are offered only where wtype is installed, and
// the OTP row only where pass-otp is — an action that could only report a
// missing package does not appear.
//
// NOTHING HERE EVER HOLDS A SECRET. Every key runs one bin/pass-store verb,
// which hands the work to `pass`; this panel knows names.
//
// THE CAPTURED MODE, which is the second thing this panel does. Alt+N (or the
// QR chip in the hero) closes the panel, takes a region of the screen, decodes
// the QR in it, and reopens here showing what the code SAYS IT IS — issuer,
// account, type, digit count, and never the secret, which goes from the
// clipboard into `pass` without passing through this process at all. Then it
// asks the only question left: which entry does it belong to? An existing one,
// found the same way every other entry is found here, or a new one at a path
// you can edit. Escape discards the code and gives the ordinary list back.
BarPanel {
    id: panel

    required property var pass

    panelTitle: ""
    cardWidth: theme.space(92)

    readonly property int maxRows: 8

    property string query: ""
    readonly property var rows: pass.ranked(query)
    readonly property var visibleRows: rows.slice(0, maxRows)
    readonly property int hiddenCount: Math.max(0, rows.length - maxRows)

    // "" is the ordinary list; "destination" asks where a captured code goes;
    // "new" is the editable path for a code that is getting its own entry.
    property string captureMode: ""
    readonly property bool captured: captureMode !== ""

    // The last row of the destination list rather than the first: the common
    // case is filing a code against an entry that already exists, and a
    // synthetic row at the top would cost that case an arrow key every time.
    readonly property var newEntryRow: ({
            isNew: true,
            name: "",
            leaf: "Create a new entry",
            folder: ""
        })
    readonly property var listRows: captureMode === "destination" ? visibleRows.concat([newEntryRow]) : visibleRows

    // Names only — the same list the panel already draws. It is here so that
    // "that entry already exists" can be said while the field still has
    // focus; bin/pass-store refuses it as well, and that refusal is the one
    // that actually protects the entry.
    readonly property var entryNames: (pass.entries || []).map(entry => entry.name)
    property string newPath: ""
    readonly property string newPathState: Model.pathState(newPath, entryNames)

    property int rowIndex: 0

    function moveCursor(dy) {
        if (listRows.length === 0)
            return;
        rowIndex = Math.max(0, Math.min(listRows.length - 1, rowIndex + dy));
    }

    function selected() {
        if (listRows.length === 0)
            return null;
        return listRows[Math.max(0, Math.min(rowIndex, listRows.length - 1))];
    }

    // Every action closes the panel. A password manager that stayed open
    // after handing something over would leave the entry list on screen
    // while the user turned to the window they were filling in.
    function run(verb) {
        // The captured screens are about one code, not about the store; the
        // copy/type keys would be acting on a row the user is aiming at for a
        // completely different reason.
        if (panel.captured)
            return;
        const entry = selected();
        if (!entry || entry.isNew)
            return;
        switch (verb) {
        case "copy":
            panel.pass.copyPassword(entry);
            break;
        case "user":
            panel.pass.copyUsername(entry);
            break;
        case "otp":
            if (!panel.pass.canOtp)
                return;
            panel.pass.copyOtp(entry);
            break;
        case "type":
            if (!panel.pass.canType)
                return;
            panel.pass.typePassword(entry);
            break;
        case "type-user":
            if (!panel.pass.canType)
                return;
            panel.pass.typeUsername(entry);
            break;
        case "edit":
            panel.pass.edit(entry);
            break;
        default:
            return;
        }
        panel.close();
    }

    onQueryChanged: rowIndex = 0

    // ------------------------------------------------------- capturing a QR
    //
    // THE PANEL CLOSES FIRST, AND THAT IS THE WHOLE SEQUENCING PROBLEM. This
    // window holds WlrKeyboardFocus.Exclusive while it is open, and
    // screenshot-qr runs wayfreeze and then slurp — a fullscreen frozen
    // overlay and a region selection, both of which need the pointer and the
    // keyboard. With the panel up, slurp gets neither and there is nothing to
    // decode.
    //
    // Closing is not enough on its own either: close() starts a fade, and the
    // surface stays mapped until it finishes. wayfreeze screenshots the
    // screen the moment it starts, so a capture launched on the keypress
    // freezes a picture of the panel sitting over the QR. The launch
    // therefore waits for `visible` to go false, which is when the window is
    // actually gone — an event, not a guessed delay.
    property bool captureArmed: false
    // Only the panel that asked for a capture reopens for it. There is one
    // service for the whole bar but a panel per screen, and every one of them
    // hears captureReady.
    property bool captureOwner: false

    // A capture already waiting takes the press too: startCapture abandons it
    // and takes its place. Refusing was worse than useless — a selection the
    // user never noticed made both the chip and this chord silently dead, and
    // a greyed-out button was the whole of the explanation (reported
    // 2026-08-21).
    function beginCapture() {
        if (!panel.opened || !panel.pass.canQr)
            return;
        panel.captureArmed = true;
        panel.close();
    }

    onVisibleChanged: {
        if (panel.visible || !panel.captureArmed)
            return;
        panel.captureArmed = false;
        panel.captureOwner = true;
        panel.pass.startCapture();
    }

    Connections {
        target: panel.pass

        function onCaptureReady() {
            if (!panel.captureOwner)
                return;
            panel.captureOwner = false;
            // onPanelOpened reads pass.capture and opens in captured mode.
            panel.open();
        }

        function onCaptureCancelled() {
            panel.captureOwner = false;
        }

        function onCaptureFailed() {
            // The failure has already been notified — by screenshot-qr for
            // "no QR code here", by the service for anything else. Reopening
            // to show an error the user is already reading would be a third
            // copy of it.
            panel.captureOwner = false;
        }
    }

    function setMode(mode) {
        panel.captureMode = mode;
        panel.rowIndex = 0;
        panel.query = "";
        searchField.text = "";
        // focusWhen only acts on a change, so it is always driven from false —
        // otherwise going new -> destination -> new would leave the keyboard
        // in the field that is no longer on screen.
        if (mode === "new") {
            searchField.focusWhen = false;
            pathField.focusWhen = false;
            pathField.focusWhen = true;
        } else {
            pathField.focusWhen = false;
            searchField.focusWhen = false;
            searchField.focusWhen = true;
        }
    }

    // Escape in the destination list. The code is thrown away rather than
    // kept, because a capture that survived an explicit Escape would ambush
    // the next person to open the panel.
    function discardCapture() {
        panel.pass.clearCapture();
        panel.setMode("");
    }

    function fileCapture() {
        const row = panel.selected();
        if (!row)
            return;
        if (row.isNew) {
            panel.setMode("new");
            return;
        }
        panel.pass.saveCapture("append", row.name);
        panel.close();
    }

    function createCapture() {
        if (panel.newPathState !== "ok")
            return;
        panel.pass.saveCapture("insert", String(panel.newPath).trim());
        panel.close();
    }

    // The chords, claimed BEFORE the search field can eat them.
    //
    // They cannot be handled at the card's key catcher, which is where every
    // other panel's keys live: the field has focus, and a TextInput inserts
    // Alt+<letter> as text rather than ignoring it, so the event is accepted
    // and never bubbles. PanelTextField.chord fires ahead of that; this
    // function is what it and the card's catcher both call, so a chord works
    // whether or not the field happens to hold focus.
    function handleChord(event) {
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        // Alt+N is "new" in both places it appears: a new code in the
        // ordinary list, a new entry for the one just captured. It is
        // swallowed in the path field as well — an unclaimed Alt chord types
        // its letter, and a stray "n" in a store path is a bad way to find
        // that out.
        if (alt && event.key === Qt.Key_N) {
            if (panel.captureMode === "")
                panel.beginCapture();
            else if (panel.captureMode === "destination")
                panel.setMode("new");
            event.accepted = true;
            return;
        }

        if (alt && event.key === Qt.Key_U) {
            panel.run("user");
        } else if (alt && event.key === Qt.Key_O) {
            panel.run("otp");
        } else if (alt && event.key === Qt.Key_E) {
            panel.run("edit");
        } else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            panel.run(shift ? "type-user" : "type");
        } else {
            return;
        }
        event.accepted = true;
    }

    onContentKey: event => panel.handleChord(event)

    // ------------------------------------------------------------ lifecycle
    onPanelOpened: {
        panel.query = "";
        panel.rowIndex = 0;
        panel.pass.refresh();
        searchField.text = "";
        // A code waiting to be filed is why this panel reopened, so it opens
        // on that rather than on the ordinary list. It also survives a failed
        // save and a panel closed by accident — the capture is only cleared
        // when it lands in the store or when Escape throws it away.
        panel.captureMode = panel.pass.capture ? "destination" : "";
        pathField.text = panel.pass.capture ? Model.suggestedPath(panel.pass.capture) : "";
        searchField.focusWhen = true;
    }

    onPanelClosed: {
        searchField.focusWhen = false;
        pathField.focusWhen = false;
    }

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: panel.captured ? Model.captureTitle(panel.pass.capture) : "Passwords"
        meta: panel.captured ? Model.captureMeta(panel.pass.capture) : Model.heroMeta(panel.pass.entryCount, panel.rows.length, panel.query)
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            // md-qrcode while a code is waiting to be filed, md-key-variant
            // otherwise: the hero says which of the two panels this is.
            text: panel.captured ? "󰐲" : "󰌆"
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.theme.textPrimary
        }

        trailing: [
            // The whole feature, in the corner of the card it belongs to.
            // Hidden rather than dimmed where the chain is not installed, the
            // way the OTP key hint is: there is nothing to explain to someone
            // who has never had zbar.
            GlyphButton {
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰐲" // md-qrcode
                visible: panel.pass.canQr && !panel.captured
                // Never disabled while a capture is waiting: a control that
                // dims itself and says nothing is how this looked broken.
                hint: panel.pass.capturing ? "Start the region selection over (Alt+N)" : "Scan a 2FA QR code (Alt+N)"
                onActivated: panel.beginCapture()
            }
        ]
    }

    // Said once, on the screen where someone is deciding whether to trust
    // this with a 2FA seed.
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        visible: panel.captured
        width: parent.width
        text: "Those four fields are all the shell was told. The code itself goes from the clipboard into `pass`."
        wrapMode: Text.WordWrap
    }

    // The capture happens with this panel shut, so opening it again is the
    // one moment there is to explain why nothing appears to have happened.
    // Without this the state was invisible: a selection waiting on another
    // part of the screen, and a chip that looked broken.
    InfoNote {
        theme: panel.theme
        visible: panel.pass.capturing && !panel.captured
        text: "A region selection is waiting — drag a box round the QR code, or press Alt+N to start it over."
    }

    PanelTextField {
        id: searchField

        theme: panel.theme
        width: parent.width
        visible: panel.captureMode !== "new"
        inputFont: panel.theme.fontUi
        placeholder: panel.captured ? "Search for the entry it belongs to" : "Search the store"

        onTextEdited: text => panel.query = text
        onChord: event => panel.handleChord(event)
        onAccepted: {
            if (panel.captureMode === "destination")
                panel.fileCapture();
            else
                panel.run("copy");
        }
        onMoveRequested: delta => panel.moveCursor(delta)
        onCancelled: {
            // Narrowest thing first, the way the card's key catcher hands
            // Escape to its content first: the query, then the capture, then
            // the panel.
            if (panel.query !== "") {
                text = "";
                panel.query = "";
            } else if (panel.captured) {
                panel.discardCapture();
            } else {
                panel.close();
            }
        }
    }

    // The other destination: a path of its own. Mono, because it is a path,
    // and prefilled from the code's own label so that the common case is a
    // glance and Enter.
    PanelTextField {
        id: pathField

        theme: panel.theme
        width: parent.width
        visible: panel.captureMode === "new"
        placeholder: "Where in the store"

        onTextEdited: text => panel.newPath = text
        onChord: event => panel.handleChord(event)
        onAccepted: panel.createCapture()
        onCancelled: panel.setMode("destination")
    }

    InfoNote {
        theme: panel.theme
        visible: panel.captureMode === "new" && text !== ""
        text: Model.pathNotice(panel.newPathState, panel.newPath)
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.pass.lastError !== ""
        width: parent.width
        text: panel.pass.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------------- rows
    Column {
        id: rowColumn

        width: parent.width
        spacing: panel.theme.space(0.5)
        visible: panel.captureMode !== "new" && panel.listRows.length > 0

        Repeater {
            model: panel.listRows

            EntryRow {
                required property var modelData
                required property int index

                width: rowColumn.width
                entry: modelData
                rowIndex: index
            }
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small
        muted: true

        visible: panel.captureMode !== "new" && panel.listRows.length === 0
        width: parent.width
        text: panel.pass.entryCount === 0 ? "The store is empty." : "Nothing matches “" + panel.query + "”."
        wrapMode: Text.WordWrap
    }

    // --------------------------------------------------------------- footer
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        width: parent.width
        text: {
            if (panel.captured) {
                // Both, and joined rather than swapped: this store hides 13 of
                // its 21 entries behind the row limit, so a footer that showed
                // the count instead of the keys would never once mention
                // Escape on the screen that needs it most.
                const hints = Model.captureHints(panel.captureMode);
                if (panel.captureMode === "destination" && panel.hiddenCount > 0)
                    return panel.hiddenCount + " more · " + hints;
                return hints;
            }
            return panel.hiddenCount > 0 ? panel.hiddenCount + " more — keep typing to narrow" : panel.pass.hints();
        }
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    component EntryRow: CursorSurface {
        id: entryRow

        theme: panel.theme

        property var entry: null
        property int rowIndex: 0

        readonly property bool rowSelected: panel.rowIndex === rowIndex
        readonly property bool isNew: !!entry && entry.isNew === true

        hasCursor: rowSelected
        bordered: false
        current: rowSelected
        implicitHeight: rowContent.implicitHeight + panel.theme.space(2.5)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse)
                panel.rowIndex = entryRow.rowIndex
            onClicked: {
                panel.rowIndex = entryRow.rowIndex;
                if (panel.captureMode === "destination")
                    panel.fileCapture();
                else
                    panel.run("copy");
            }
        }

        PanelHint {
            theme: panel.theme
            visible: rowMouse.containsMouse
            anchor: entryRow
            above: true
            text: {
                if (entryRow.isNew)
                    return "Give the code an entry of its own";
                if (panel.captureMode === "destination")
                    return "Add the code to this entry";
                return "Copy the password";
            }
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
                // md-plus-circle-outline for the synthetic row, md-key-variant
                // for a real entry.
                text: entryRow.isNew ? "󰐗" : "󰌆"
                verticalInkCenter: true
                color: entryRow.rowSelected ? panel.theme.textPrimary : panel.theme.textMuted
                pixelSize: panel.theme.fontPx(1.0)
            }

            Column {
                id: rowLabels

                anchors.left: rowMark.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                // The leaf is the name; the folder is where it lives. Two
                // lines rather than one path, because the leaf is what is
                // being looked for and the folder is context.
                StyledText {
                    theme: panel.theme

                    width: parent.width
                    text: entryRow.entry ? entryRow.entry.leaf : ""
                    elide: Text.ElideRight
                }

                // Under the new-entry row this is the path the code would get.
                // It follows the FIELD rather than the suggestion, so a path
                // edited and then backed out of is still what this row
                // promises — they differ only once someone has typed.
                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true

                    visible: text !== ""
                    width: parent.width
                    text: {
                        if (!entryRow.entry)
                            return "";
                        if (entryRow.isNew)
                            return panel.newPath;
                        return entryRow.entry.folder;
                    }
                    color: panel.theme.textMuted
                    elide: Text.ElideRight
                }
            }
        }
    }
}
