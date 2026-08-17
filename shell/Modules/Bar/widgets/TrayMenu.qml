import QtQuick
import QtQuick.Controls
import Quickshell
import "../components"
import "../../../components"

// A tray item's own menu, drawn by us.
//
// Port of omarchy's tray menu popup (5b2c02d). We had no popup at
// all: Tray.qml called SystemTrayItem.display(), which builds a
// PlatformMenuEntry, and quickshell refuses that unless the root QML sets
// `//@ pragma UseQApplication` (src/core/platformmenu.cpp) — shell.qml does
// not, so every tray menu was a silent no-op. Adding the pragma is the wrong
// fix and upstream says why: it switches the whole shell from QGuiApplication
// to QApplication, drags QtWidgets into the process, and renders an unstyled
// platform menu beside our own panels anyway.
//
// So the menu renders here instead. A DBusMenu handle feeds a QsMenuOpener,
// whose children are the rows; a child entry inherits QsMenuHandle, so it can
// feed a NESTED opener and drill down in place. Each level keeps its own live
// opener on a stack — a child entry is owned by its parent opener's model, so
// collapsing to one reassigned opener would destroy the very entry being
// displayed and the submenu would come up empty.
BarPanel {
    id: panel

    // The SystemTrayItem whose menu is on screen.
    property var trayItem: null

    readonly property string itemTitle: trayItem ? String(trayItem.title || trayItem.id || "") : ""

    // [{opener, title}], outermost first. Empty at the root.
    property var submenuStack: []
    readonly property int submenuDepth: submenuStack.length
    readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
    readonly property var currentChildren: submenuDepth > 0 ? submenuStack[submenuDepth - 1].opener.children : rootOpener.children

    // Changing level rebuilds the row delegates synchronously, so a fresh row
    // lands under a cursor that has not moved. Submenu clicks used to be
    // silent no-ops here, which trains a double click, and that second click
    // would now fire whatever entry took the spot. A deliberate follow-up
    // click is slower than 250 ms; a double click is not.
    property bool levelSettling: false

    // Narrower than a bar panel's default: this is a context menu, not a card
    // of controls.
    cardWidth: theme.space(60)
    readonly property int maxRowsHeight: theme.space(105)
    readonly property int rowHeight: theme.space(7)
    readonly property int separatorRowHeight: theme.space(3)

    // The card fades out over one theme tick and the window stays mapped for
    // all of it (BarPanel's `visible: opened || card.opacity > 0`), so
    // resetting on close() would swap a live submenu for the root menu
    // mid-fade — a visible flash, and a resize if the two differ in height.
    // Wait for the fade to actually finish. Switching to another tray item
    // still resets immediately, from Tray.qml's openMenuFor().
    onVisibleChanged: if (!visible)
        panel.resetMenu()

    function settleLevel() {
        levelSettling = true;
        settleTimer.restart();
    }

    function resetMenu() {
        levelSettling = false;
        settleTimer.stop();
        // Flickable keeps its offset across a model swap whenever the new
        // content is still tall enough to hold it, so a menu dismissed while
        // scrolled would otherwise reopen part-way down.
        rowsFlick.contentY = 0;
        // Clear the reactive stack BEFORE tearing anything down, so no binding
        // can read a half-destroyed opener while this runs. Then destroy
        // deepest first: an inner opener's entry is owned by its parent's
        // children model, so destroying a parent first would invalidate an
        // entry a still-live child opener references.
        const openers = submenuStack;
        submenuStack = [];
        for (let i = openers.length - 1; i >= 0; i--)
            openers[i].opener.destroy();
    }

    function enterSubmenu(entry, title) {
        const opener = openerComponent.createObject(panel, {
            menu: entry
        });
        if (!opener)
            return;
        const stack = submenuStack.slice();
        stack.push({
            opener: opener,
            title: title
        });
        submenuStack = stack;
        settleLevel();
    }

    function leaveSubmenu() {
        if (submenuStack.length === 0)
            return;
        const stack = submenuStack.slice();
        const top = stack.pop();
        submenuStack = stack;
        top.opener.destroy();
        settleLevel();
    }

    // Escape walks out one level before it closes the card — the same key
    // that leaves a submenu everywhere else. BarPanel offers content the key
    // first and closes only on one nobody claimed.
    onContentKey: event => {
        if (event.key === Qt.Key_Escape && panel.submenuDepth > 0) {
            rowsFlick.contentY = 0;
            panel.leaveSubmenu();
            event.accepted = true;
        }
    }

    QsMenuOpener {
        id: rootOpener

        menu: panel.trayItem ? panel.trayItem.menu : null
    }

    Component {
        id: openerComponent

        QsMenuOpener {}
    }

    Timer {
        id: settleTimer

        interval: 250
        onTriggered: panel.levelSettling = false
    }

    // Where we are, and the way back out. Pinned above the rows rather than
    // scrolling with them, so the way back stays reachable in a submenu taller
    // than the card — exactly the long list this drill-down exists for.
    Item {
        visible: panel.submenuDepth > 0
        width: parent.width
        height: visible ? panel.rowHeight : 0

        CursorSurface {
            anchors.fill: parent
            theme: panel.theme
            // A menu row highlights under the pointer only; there is no
            // separate keyboard cursor here to outline.
            bordered: false
            current: backMouse.containsMouse
        }

        Text {
            id: backGlyph

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: panel.theme.space(1.5)
            text: "󰅁"
            color: panel.theme.textPrimary
            font.family: "Symbols Nerd Font"
            font.pixelSize: panel.theme.fontPx(0.917)
        }

        StyledText {
            theme: panel.theme

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: backGlyph.right
            anchors.leftMargin: panel.theme.space(1.5)
            anchors.right: parent.right
            anchors.rightMargin: panel.theme.space(2)
            text: panel.currentTitle
            elide: Text.ElideRight
        }

        MouseArea {
            id: backMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (panel.levelSettling)
                    return;
                // Reset the offset before the model swap, so the parent level
                // shows from the top (same ordering as the row delegate).
                rowsFlick.contentY = 0;
                panel.leaveSubmenu();
            }
        }
    }

    Rectangle {
        visible: panel.submenuDepth > 0
        width: parent.width
        height: panel.theme.borderWidth
        color: panel.theme.alpha(panel.theme.textPrimary, 0.2)
    }

    StyledText {
        theme: panel.theme
        muted: true

        // currentChildren is an ObjectModel, not a JS array: it counts through
        // `values`, and `.length` on the model itself is undefined — which
        // would leave this row permanently invisible rather than erroring.
        visible: panel.trayItem !== null && panel.currentChildren && panel.currentChildren.values ? panel.currentChildren.values.length === 0 : false
        width: parent.width
        text: "This icon reports no menu."
        font.italic: true
    }

    Flickable {
        id: rowsFlick

        width: parent.width
        height: Math.min(rowsColumn.implicitHeight, panel.maxRowsHeight)
        contentWidth: width
        contentHeight: rowsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: rowsColumn

            width: rowsFlick.width
            spacing: 0

            Repeater {
                model: panel.currentChildren

                delegate: Item {
                    id: menuRow

                    required property var modelData
                    required property int index

                    readonly property string rowText: String(modelData.text || "")
                    // Both only ever describe the root menu; inside a submenu
                    // the first rows are real entries and must not be
                    // swallowed. A DBusMenu commonly opens with the app's own
                    // name and a rule under it, which is the popup's title
                    // twice over.
                    readonly property bool atRoot: panel.submenuDepth === 0
                    readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === panel.itemTitle.toLowerCase()
                    readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
                    readonly property bool hiddenRow: rootTitleEntry || leadingSeparator

                    visible: !hiddenRow
                    width: rowsColumn.width
                    implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? panel.separatorRowHeight : panel.rowHeight)
                    opacity: modelData.enabled ? 1 : 0.45

                    Rectangle {
                        visible: menuRow.modelData.isSeparator
                        anchors.left: parent.left
                        anchors.leftMargin: panel.theme.space(1.5)
                        anchors.right: parent.right
                        anchors.rightMargin: panel.theme.space(1.5)
                        anchors.verticalCenter: parent.verticalCenter
                        height: panel.theme.borderWidth
                        color: panel.theme.alpha(panel.theme.textPrimary, 0.2)
                    }

                    CursorSurface {
                        visible: !menuRow.modelData.isSeparator
                        anchors.fill: parent
                        theme: panel.theme
                        bordered: false
                        current: rowMouse.containsMouse && menuRow.modelData.enabled
                    }

                    Text {
                        id: checkGlyph

                        visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        width: panel.theme.space(5)
                        horizontalAlignment: Text.AlignHCenter
                        text: menuRow.modelData.checkState === Qt.Checked ? "󰄬" : ""
                        color: panel.theme.textPrimary
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: panel.theme.fontPx(0.917)
                    }

                    Image {
                        id: rowIcon

                        visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: panel.theme.space(5.5)
                        width: panel.theme.space(4)
                        height: panel.theme.space(4)
                        fillMode: Image.PreserveAspectFit
                        // Decode at physical pixels: the logical size leaves
                        // PNG icons upscaled and blurry on HiDPI displays.
                        sourceSize.width: width * Screen.devicePixelRatio
                        sourceSize.height: height * Screen.devicePixelRatio
                        source: menuRow.modelData.icon
                    }

                    StyledText {
                        theme: panel.theme

                        visible: !menuRow.modelData.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: rowIcon.visible ? panel.theme.space(10.5) : (checkGlyph.visible ? panel.theme.space(6) : panel.theme.space(2))
                        anchors.right: submenuGlyph.left
                        anchors.rightMargin: panel.theme.space(2)
                        text: menuRow.rowText
                        elide: Text.ElideRight
                    }

                    Text {
                        id: submenuGlyph

                        visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: panel.theme.space(1.5)
                        text: "󰅂"
                        color: panel.theme.textPrimary
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: panel.theme.fontPx(0.917)
                    }

                    MouseArea {
                        id: rowMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (panel.levelSettling)
                                return;
                            if (menuRow.modelData.hasChildren) {
                                // Reset scroll BEFORE swapping the model: the
                                // swap destroys this delegate synchronously
                                // and ids stop resolving after it.
                                rowsFlick.contentY = 0;
                                panel.enterSubmenu(menuRow.modelData, menuRow.rowText);
                            } else {
                                menuRow.modelData.triggered();
                                panel.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
