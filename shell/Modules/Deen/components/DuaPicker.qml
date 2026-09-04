import QtQuick
import QtQuick.Controls

// All 132 chapters of Hisn al-Muslim, in a sheet, with a search line.
//
// The same control the reader has and for the same reason: a book with 132
// chapters cannot be walked with ◀ and ▶, and the person using this does not
// know which number "when leaving the house" is. It searches the ENGLISH title
// first, because that is the question someone actually arrives with — "what do
// I say before eating" — and the Arabic title and the number after it.
//
// Deliberately not SurahPicker with different data: that one folds doubled
// letters to make `rahman` reach Ar-Rahmaan, which is exactly wrong for
// English prose, where it would fold "sleeping" and "seeping" together.
ModalSheet {
    id: picker

    // [{n, en, ar, count}] — the chapter table, with how many duas each holds.
    required property var chapters
    property int current: 1

    signal picked(int chapter)

    preferredFocus: search

    function fold(s) {
        return String(s).toLowerCase().replace(/[ً-ْٰ]/g, "").replace(/[^a-z0-9؀-ۿ]/g, "");
    }

    readonly property var filtered: {
        const rows = picker.chapters || [];
        const raw = String(search.text).trim();
        const q = picker.fold(raw);
        if (q === "")
            return rows;
        const digits = /^\d+$/.test(raw) ? raw : "";
        return rows.filter(row => (digits !== "" && String(row.n).indexOf(digits) === 0) || picker.fold(row.en).indexOf(q) >= 0 || picker.fold(row.ar).indexOf(q) >= 0);
    }

    function choose(n) {
        picker.picked(n);
        picker.dismissed();
    }

    onOpenChanged: {
        if (picker.open) {
            search.clear();
            Qt.callLater(() => list.positionViewAtIndex(Math.max(0, picker.current - 1), ListView.Center));
        }
    }

    SearchLine {
        id: search

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: picker.style.ui(38)
        style: picker.style
        placeholderText: "Search 132 chapters — waking, eating, travel, rain"
        onEscaped: picker.dismissed()
        onSteppedDown: list.forceActiveFocus()
        onAccepted: {
            if (picker.filtered.length > 0)
                picker.choose(picker.filtered[0].n);
        }
    }

    ListView {
        id: list

        anchors.top: search.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: picker.style.ui(14)
        clip: true
        spacing: picker.style.ui(2)
        model: picker.filtered
        currentIndex: -1

        ScrollBar.vertical: ScrollBar {}

        EmptyState {
            anchors.centerIn: parent
            visible: list.count === 0
            style: picker.style
            glyph: "⌕"
            title: "Nothing in the book by that name"
            message: "Try what you are about to do — `sleep`, `travel`, `wudu` — or a chapter number."
        }

        Keys.onReturnPressed: {
            if (list.currentIndex >= 0)
                picker.choose(picker.filtered[list.currentIndex].n);
        }

        delegate: Rectangle {
            id: row

            required property int index
            required property var modelData

            readonly property bool isCurrent: row.modelData.n === picker.current

            width: list.width - picker.style.ui(10)
            height: picker.style.ui(54)
            radius: picker.style.radiusSm
            color: row.isCurrent ? picker.style.alpha(picker.style.accent, 0.16) : rowHover.hovered || list.currentIndex === row.index ? picker.style.alpha(picker.style.fg, 0.09) : "transparent"

            HoverHandler {
                id: rowHover
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: picker.choose(row.modelData.n)
            }

            Text {
                id: number
                textFormat: Text.PlainText

                anchors.left: parent.left
                anchors.leftMargin: picker.style.ui(14)
                anchors.verticalCenter: parent.verticalCenter
                width: picker.style.ui(30)
                horizontalAlignment: Text.AlignRight
                text: row.modelData.n
                color: row.isCurrent ? picker.style.accent : picker.style.muted
                font.family: picker.style.fontFamily
                font.pixelSize: picker.style.type(12)
                font.weight: Font.DemiBold
            }

            Column {
                anchors.left: number.right
                anchors.leftMargin: picker.style.ui(14)
                anchors.right: arabic.left
                anchors.rightMargin: picker.style.ui(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: picker.style.ui(2)

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.modelData.en
                    color: picker.style.brightFg
                    font.family: picker.style.fontFamily
                    font.pixelSize: picker.style.type(13)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.modelData.count === 1 ? "1 dua" : (row.modelData.count + " duas")
                    color: picker.style.muted
                    font.family: picker.style.fontFamily
                    font.pixelSize: picker.style.type(10)
                    elide: Text.ElideRight
                }
            }

            Text {
                id: arabic
                textFormat: Text.PlainText

                anchors.right: parent.right
                anchors.rightMargin: picker.style.ui(14)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, row.width * 0.34)
                horizontalAlignment: Text.AlignRight
                text: row.modelData.ar
                color: picker.style.alpha(picker.style.fg, 0.85)
                font.family: picker.style.arabicFamily
                font.pixelSize: picker.style.type(15)
                elide: Text.ElideLeft
            }
        }
    }
}
