import QtQuick
import "../DekhoModel.js" as Model

// omakade's qml/components/LibraryView.qml: the grid, its key handling, its
// animated wheel and its empty state.
//
// NOT its scroll track. omakade draws a permanent 16 px bar down the right edge
// of the list; on a page that is nothing but artwork that is a grey stripe over
// every screen, and the user's call was to take it out rather than to fade it.
// What replaces it is the notch below being big enough that you are never far
// from either end.
//
// THE ROW FILLS THE ROW. `columns` is derived from a TARGET cell width and the
// cell is then the row divided by that count — which is exactly the fix doc §13
// records against the old grids ("rows should fill whole column automatically"),
// arrived at independently by omakade and kept here verbatim.
//
// One cursor, shared by the pointer and the keyboard, and it is REAL Qt FOCUS
// rather than an index the module maintains: the delegate is focusable, focus
// writes currentIndex back, and a click takes the focus before it activates. So
// Tab walks the grid, `nextItemInFocusChain` can find its cards, and the hover
// -steal doc §10 had to guard against cannot happen — hovering a card here
// scales it and nothing else.
Item {
    id: root

    required property var style
    // A plain array of `dekho api` rows: {id, kind, title, year, poster, …}.
    required property var items
    // The flat colour behind the cards. PosterCard paints its corner cover in
    // this, so it must be the page's real colour.
    required property color pageColor

    // The w342 cache directory and the set of files known to be in it. A map
    // rather than a per-listing "ready" flag, because every poster this module
    // fetches lands in the SAME directory (doc §12 found the same thing about
    // w780 backdrops) — so "is this one on disk yet" is a question about the
    // file, and a flag about the batch answers it wrong in both directions. It
    // is also what makes LOAD MORE free: appending a page cannot blank the
    // page above it while a second prefetch runs.
    property string posterDir: ""
    property var posterDone: ({})

    function coverFor(path) {
        if (!path || !root.posterDir)
            return "";
        return root.posterDone[path] === true ? root.posterDir + "/" + String(path).replace(/^\/+/, "") : "";
    }

    property string emptyGlyph: "◇"
    property string emptyTitle: "Nothing here"
    property string emptyMessage: ""
    property string emptyAction: ""
    // The bottom of a `discover` result is not the bottom of the catalog. A
    // footer button rather than an infinite scroll: it is reachable by Tab, it
    // cannot run away, and it says how far in you are.
    property bool canLoadMore: false
    property string loadMoreText: "LOAD MORE"

    property alias currentIndex: grid.currentIndex
    readonly property int count: grid.count
    readonly property bool gridFocused: grid.activeFocus

    signal activated(int index)
    signal loadMoreRequested
    signal emptyActionRequested

    function focusGrid() {
        if (grid.count > 0) {
            grid.forceActiveFocus();
            grid.focusCurrent();
        }
    }

    Accessible.name: "Films and series"
    Accessible.role: Accessible.List

    GridView {
        id: grid

        readonly property int columns: Math.max(2, Math.min(8, Math.floor(width / root.style.ui(210))))
        property real wheelTargetY: contentY

        anchors.fill: parent
        clip: true
        model: root.items
        boundsBehavior: Flickable.StopAtBounds
        // OFF, and every arrow handled below instead. GridView's built-in
        // navigation moves `currentIndex` and nothing else — the ring follows
        // it, but the KEYBOARD does not, because active focus is still on the
        // card it was on. Tab then jumps back there, which is the pointer and
        // the keyboard disagreeing about what is lit — the exact thing this
        // redesign replaced a hand-rolled cursor to stop. Measured: eight Downs
        // then five Tabs landed on card five.
        keyNavigationEnabled: false
        highlightFollowsCurrentItem: true
        highlightMoveDuration: root.style.normal
        cacheBuffer: height * 0.25
        reuseItems: true
        focus: true

        cellWidth: width / columns
        // The poster plus omakade's 64 px of caption room. Reserved whether or
        // not the caption has landed, so nothing reflows when a title arrives.
        cellHeight: Math.round(cellWidth * 1.5) + root.style.ui(64)

        // A NOTCH IS MORE THAN A PAGE, and there is no scrollbar to show you
        // where you are. omakade steps a cell and a half, which on a grid this
        // tall is a dozen notches to the bottom — "scrolling very slow", the
        // same sentence doc §13 records against the rails ("Make it like single
        // page"). A page was the answer there and was still not enough here, so
        // a notch is a page and a half.
        //
        // Accumulated against the animation's TARGET so spinning the wheel does
        // not throw away the distance an in-flight step has not covered yet.
        NumberAnimation {
            id: wheelScrollAnimation

            target: grid
            property: "contentY"
            duration: root.style.normal
            easing.type: root.style.easing
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            blocking: true

            onWheel: event => {
                const travel = event.pixelDelta.y !== 0 ? event.pixelDelta.y * 2.5 : event.angleDelta.y / 120 * grid.height * 1.5;
                if (travel === 0)
                    return;
                const maximumY = Math.max(0, grid.contentHeight - grid.height);
                const startingY = wheelScrollAnimation.running ? grid.wheelTargetY : grid.contentY;
                grid.wheelTargetY = Math.max(0, Math.min(maximumY, startingY - travel));
                wheelScrollAnimation.stop();
                wheelScrollAnimation.from = grid.contentY;
                wheelScrollAnimation.to = grid.wheelTargetY;
                wheelScrollAnimation.start();
                event.accepted = true;
            }
        }

        // The one place the cursor moves: set the index, bring it into view,
        // and give it the keyboard. Nothing else may write currentIndex except
        // a delegate that has just BEEN focused (by a click or by Tab), which
        // is the other direction and cannot loop.
        function focusCurrent() {
            grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
            const cell = grid.itemAtIndex(grid.currentIndex);
            if (cell)
                cell.focusCard();
        }

        function step(delta) {
            const next = grid.currentIndex + delta;
            if (next < 0 || next >= grid.count)
                return;
            grid.currentIndex = next;
            grid.focusCurrent();
        }

        Keys.onReturnPressed: event => {
            if (grid.currentIndex >= 0) {
                root.activated(grid.currentIndex);
                event.accepted = true;
            }
        }
        Keys.onEnterPressed: event => {
            if (grid.currentIndex >= 0) {
                root.activated(grid.currentIndex);
                event.accepted = true;
            }
        }
        Keys.onSpacePressed: event => {
            if (grid.currentIndex >= 0) {
                root.activated(grid.currentIndex);
                event.accepted = true;
            }
        }
        // Left and Right cross row boundaries, so the grid is one order under
        // the arrows as well as under Tab; Up and Down stop at the ends rather
        // than clamping, which is omakade's behaviour and the one that does not
        // silently jump you a whole row.
        Keys.onLeftPressed: event => {
            grid.step(-1);
            event.accepted = true;
        }
        Keys.onRightPressed: event => {
            grid.step(1);
            event.accepted = true;
        }
        Keys.onUpPressed: event => {
            grid.step(-grid.columns);
            event.accepted = true;
        }
        Keys.onDownPressed: event => {
            grid.step(grid.columns);
            event.accepted = true;
        }

        delegate: Item {
            id: cell

            required property var modelData
            required property int index

            // What `focusCurrent` reaches for. The wrapper exists to hold
            // omakade's cell margins and is not focusable itself, so the grid
            // needs a name for the card inside it.
            function focusCard() {
                card.forceActiveFocus();
            }

            width: grid.cellWidth
            height: grid.cellHeight

            PosterCard {
                id: card

                anchors.fill: parent
                anchors.leftMargin: root.style.ui(8)
                anchors.rightMargin: root.style.ui(8)
                anchors.topMargin: root.style.ui(7)
                anchors.bottomMargin: root.style.ui(7)

                style: root.style
                pageColor: root.pageColor
                title: cell.modelData.title || ""
                subtitle: cell.modelData.year ? String(cell.modelData.year) : ""
                detail: Model.kindLabel(cell.modelData.kind)
                progress: Model.progressOf(cell.modelData)
                status: Model.statusPill(cell.modelData)
                coverPath: root.coverFor(cell.modelData.poster)
                current: grid.currentIndex === cell.index
                focus: current

                onActiveFocusChanged: {
                    if (activeFocus)
                        grid.currentIndex = cell.index;
                }
                onActivated: root.activated(cell.index)
            }
        }

        footer: Item {
            width: grid.width
            height: root.canLoadMore ? root.style.ui(72) : 0
            visible: root.canLoadMore

            GlassButton {
                anchors.centerIn: parent
                style: root.style
                text: root.loadMoreText
                compact: true
                onClicked: root.loadMoreRequested()
            }
        }

        // omakade writes this as a self-referential binding on currentIndex,
        // which is dead code the moment anything assigns to it — and its own
        // delegate assigns on every focus change. So the clamp lives here, where
        // it also has to cover the other direction: switching from a hundred
        // discover results to a dozen history rows leaves the cursor past the
        // end of the list, and GridView does not pull it back by itself.
        onCountChanged: {
            if (count === 0)
                currentIndex = -1;
            else if (currentIndex < 0 || currentIndex >= count)
                currentIndex = Math.max(0, Math.min(currentIndex, count - 1));
        }
    }

    EmptyState {
        anchors.centerIn: parent
        visible: grid.count === 0
        style: root.style
        glyph: root.emptyGlyph
        title: root.emptyTitle
        message: root.emptyMessage
        action: root.emptyAction
        onActionRequested: root.emptyActionRequested()
    }
}
