import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "EmojiSearch.js" as EmojiSearch

// Emoji picker: fullscreen overlay layer with a centered card, a query line
// and a grid of glyphs. Ported from omarchy's emojis plugin (CREDITS.md) —
// their flat grid (no group headers, no recents, no ranking), their key model
// (←/→ by one, ↑/↓ by a row, PageUp/PageDown by a screen, Enter to take the
// cursor's emoji, Escape clearing the query before it closes) and their
// substring filter in EmojiSearch.js. The chrome is our launcher/menu
// language: scrim, surface1 card, accent cursor fill.
//
// Enter inserts the emoji into the focused window, as upstream does, through
// `bin/emoji-insert` — a port of their omarchy-menu-emoji-insert whose paste
// mechanism had to change: their `wtype -M shift -k Insert` pastes the PRIMARY
// selection in foot and does nothing at all in GTK3 apps, so ours types the
// emoji instead (their own other branch). The script explains the measurement.
// Shift+Enter is ours: it copies without typing, which is what this picker did
// before wtype existed and the way out if an application refuses the keystroke.
//
// LazyLoader-gated — nothing here exists until first summoned via IPC.
Scope {
    id: emojisRoot

    required property var theme

    property bool opened: false
    property string filterText: ""
    property int selectedIndex: 0
    // False before anything has been pointed at: matches upstream, where the
    // grid draws no cursor until a key or the mouse picks a cell.
    property bool cursorActive: false
    property var emojis: []

    // ------------------------------------------------------------ geometry
    readonly property int cardMargin: theme.space(4)
    readonly property int headerHeight: theme.space(10)
    readonly property int contentSpacing: theme.space(3)
    // Upstream's 44px cells, expressed in our spacing scale so a denser theme
    // tightens the grid with everything else.
    readonly property int cellSize: theme.space(11)
    // Upstream clamps the card to the screen; small displays get the margin
    // back rather than a card hanging off the edge. The panel measures 0
    // before it is first mapped, hence the guard.
    readonly property int cardWidth: panel.width > 0 ? Math.min(theme.space(120), panel.width - theme.space(8) * 2) : theme.space(120)
    readonly property int cardHeight: panel.height > 0 ? Math.min(theme.space(130), panel.height - theme.space(8) * 2) : theme.space(130)
    readonly property int columns: Math.max(1, Math.floor((cardWidth - cardMargin * 2) / cellSize))

    // ---------------------------------------------------------- open/close
    function show() {
        filterText = "";
        selectedIndex = 0;
        cursorActive = true;
        opened = true;
        rebuildDisplay();
    }

    function hide() {
        opened = false;
        filterText = "";
    }

    function toggle() {
        if (opened)
            hide();
        else
            show();
    }

    // ------------------------------------------------------------- display
    ListModel {
        id: displayModel
    }

    function loadEmojis(raw) {
        emojis = EmojiSearch.parseEmojis(raw);
        if (opened)
            rebuildDisplay();
    }

    function rebuildDisplay() {
        const out = EmojiSearch.filterEmojis(emojis, filterText, 1000);

        displayModel.clear();
        for (let i = 0; i < out.length; i++)
            displayModel.append({
                emoji: out[i].e
            });

        if (displayModel.count === 0)
            selectedIndex = 0;
        else if (selectedIndex >= displayModel.count)
            selectedIndex = displayModel.count - 1;
        else if (selectedIndex < 0)
            selectedIndex = 0;
        cursorActive = displayModel.count > 0;

        Qt.callLater(() => {
            if (displayModel.count > 0)
                grid.positionViewAtIndex(selectedIndex, GridView.Contain);
        });
    }

    function setFilter(next) {
        filterText = next;
        selectedIndex = 0;
        cursorActive = true;
        rebuildDisplay();
    }

    // ---------------------------------------------------------- navigation
    // The three movers share upstream's rule: the first press with no cursor
    // parks on the first (or last, moving backwards) cell instead of stepping.
    function select(delta) {
        if (displayModel.count === 0)
            return;
        if (!cursorActive) {
            cursorActive = true;
            selectedIndex = delta < 0 ? displayModel.count - 1 : 0;
        } else {
            selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count;
        }
        grid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }

    function selectBy(step) {
        if (displayModel.count === 0)
            return;
        if (!cursorActive) {
            cursorActive = true;
            selectedIndex = step < 0 ? displayModel.count - 1 : 0;
        } else {
            selectedIndex = Math.max(0, Math.min(displayModel.count - 1, selectedIndex + step));
        }
        grid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }

    function selectRow(delta) {
        selectBy(delta * columns);
    }

    function selectPage(delta) {
        const visibleRows = Math.max(1, Math.floor(grid.height / cellSize));
        selectBy(delta * columns * visibleRows);
    }

    // ------------------------------------------------------------ activate
    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"

    function activateIndex(index) {
        if (index < 0 || index >= displayModel.count)
            return;
        applySelected(displayModel.get(index).emoji);
    }

    function copyIndex(index) {
        if (index < 0 || index >= displayModel.count)
            return;
        copySelected(displayModel.get(index).emoji);
    }

    function applySelected(emoji) {
        if (!emoji)
            return;
        // Close first: the helper waits out the keyboard handover, and it can
        // only type into the application once this layer surface lets go.
        hide();
        Quickshell.execDetached([binDir + "emoji-insert", String(emoji)]);
    }

    function copySelected(emoji) {
        if (!emoji)
            return;
        hide();
        // A plain (daemonizing) wl-copy: nothing is going to paste it, so the
        // copy has to outlive this call.
        Quickshell.execDetached(["wl-copy", "--type", "text/plain", String(emoji)]);
        Quickshell.execDetached(["notify-send", "-a", "qshell", "-t", "2000", "Copied " + emoji, "On the clipboard — paste with Ctrl+V"]);
    }

    FileView {
        path: Quickshell.shellDir + "/Modules/Emojis/emojis.json"
        onLoaded: emojisRoot.loadEmojis(text())
        onLoadFailed: console.warn("Emojis: emojis.json failed to load")
    }

    PanelWindow {
        id: panel

        visible: emojisRoot.opened
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qshell-emojis"
        WlrLayershell.keyboardFocus: emojisRoot.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // Card-shaped compositor blur behind the glass fill; the scrim
        // around it stays a plain dim (see BarPanel.qml).
        BackgroundEffect.blurRegion: emojisRoot.theme.blurActive && emojisRoot.opened ? cardBlurRegion : null

        Region {
            id: cardBlurRegion
            item: card
            radius: card.radius
        }

        Rectangle {
            anchors.fill: parent
            color: emojisRoot.theme.alpha(emojisRoot.theme.surface0, 0.5)

            MouseArea {
                anchors.fill: parent
                onClicked: emojisRoot.hide()
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: emojisRoot.cardWidth
            height: emojisRoot.cardHeight
            radius: emojisRoot.theme.radius(1.5)
            color: emojisRoot.theme.glass(emojisRoot.theme.surface1)
            border.width: emojisRoot.theme.borderWidth
            border.color: emojisRoot.theme.surface3

            opacity: emojisRoot.opened ? 1 : 0
            scale: emojisRoot.opened ? 1 : 0.96
            Behavior on opacity {
                NumberAnimation {
                    duration: emojisRoot.theme.time(0.8)
                    easing.type: emojisRoot.theme.easing
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: emojisRoot.theme.time(0.8)
                    easing.type: emojisRoot.theme.easing
                }
            }

            MouseArea {
                // Swallow clicks so they don't fall through to the scrim.
                anchors.fill: parent
            }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true

                // Typing owns the keyboard — every printable key is query
                // text, so navigation lives on the arrows and page keys only.
                Keys.onPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

                    if (event.key === Qt.Key_Escape) {
                        if (emojisRoot.filterText)
                            emojisRoot.setFilter("");
                        else
                            emojisRoot.hide();
                    } else if (event.key === Qt.Key_Backspace) {
                        // Plain backspace drops a character, Ctrl+Backspace a
                        // word, Ctrl+U the lot — upstream's Util.editsFilter.
                        if (!emojisRoot.filterText)
                            return;
                        emojisRoot.setFilter(ctrl ? emojisRoot.filterText.replace(/\s+$/, "").replace(/\S+$/, "") : emojisRoot.filterText.slice(0, -1));
                    } else if (ctrl && event.key === Qt.Key_U) {
                        emojisRoot.setFilter("");
                    } else if (event.key === Qt.Key_Left) {
                        emojisRoot.select(-1);
                    } else if (event.key === Qt.Key_Right) {
                        emojisRoot.select(1);
                    } else if (event.key === Qt.Key_Up) {
                        emojisRoot.selectRow(-1);
                    } else if (event.key === Qt.Key_Down) {
                        emojisRoot.selectRow(1);
                    } else if (event.key === Qt.Key_PageUp) {
                        emojisRoot.selectPage(-1);
                    } else if (event.key === Qt.Key_PageDown) {
                        emojisRoot.selectPage(1);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (emojisRoot.cursorActive && (event.modifiers & Qt.ShiftModifier))
                            emojisRoot.copyIndex(emojisRoot.selectedIndex);
                        else if (emojisRoot.cursorActive)
                            emojisRoot.activateIndex(emojisRoot.selectedIndex);
                        else if (displayModel.count > 0)
                            emojisRoot.cursorActive = true;
                    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                        emojisRoot.setFilter(emojisRoot.filterText + event.text);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: emojisRoot.cardMargin
                    spacing: emojisRoot.contentSpacing

                    // Query line in the launcher's search-field frame. Not a
                    // TextInput: the grid needs the arrow keys, so the key
                    // catcher above owns every keystroke.
                    Rectangle {
                        width: parent.width
                        height: emojisRoot.headerHeight
                        radius: emojisRoot.theme.radius(1)
                        color: emojisRoot.theme.surface2
                        border.width: emojisRoot.theme.borderWidth
                        border.color: emojisRoot.filterText ? emojisRoot.theme.accent : emojisRoot.theme.surface3

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: emojisRoot.theme.space(3)
                            anchors.rightMargin: emojisRoot.theme.space(3)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: emojisRoot.filterText || "search emojis"
                            color: emojisRoot.filterText ? emojisRoot.theme.textPrimary : emojisRoot.theme.textMuted
                            font.family: emojisRoot.theme.fontUi
                            font.pixelSize: emojisRoot.theme.fontPx(1.1)
                        }
                    }

                    Item {
                        width: parent.width
                        height: parent.height - y

                        GridView {
                            id: grid
                            anchors.fill: parent
                            clip: true
                            model: displayModel
                            cellWidth: emojisRoot.cellSize
                            cellHeight: emojisRoot.cellSize
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: cell

                                required property int index
                                required property string emoji

                                readonly property bool hasCursor: emojisRoot.cursorActive && cell.index === emojisRoot.selectedIndex

                                width: emojisRoot.cellSize
                                height: emojisRoot.cellSize
                                radius: emojisRoot.theme.radius(0.75)
                                color: cell.hasCursor ? emojisRoot.theme.alpha(emojisRoot.theme.accent, 0.18) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: cell.emoji
                                    // No font.family on purpose: the glyphs
                                    // come from whatever emoji font
                                    // fontconfig resolves, not from the UI
                                    // font (which has no emoji coverage).
                                    font.pixelSize: emojisRoot.theme.fontPx(1.833)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: {
                                        emojisRoot.cursorActive = true;
                                        emojisRoot.selectedIndex = cell.index;
                                    }
                                    onClicked: {
                                        emojisRoot.cursorActive = true;
                                        emojisRoot.selectedIndex = cell.index;
                                        emojisRoot.activateIndex(cell.index);
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: displayModel.count === 0
                            horizontalAlignment: Text.AlignHCenter
                            text: emojisRoot.filterText ? "No matches for “" + emojisRoot.filterText + "”" : "No emojis loaded"
                            color: emojisRoot.theme.textMuted
                            font.family: emojisRoot.theme.fontUi
                            font.pixelSize: emojisRoot.theme.fontPx(1.0)
                        }
                    }
                }
            }
        }
    }
}
