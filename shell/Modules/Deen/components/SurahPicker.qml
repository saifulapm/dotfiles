import QtQuick
import QtQuick.Controls

// All 114, in a sheet, with a search line.
//
// The reader could only be walked one surah at a time with ◀ and ▶, which is
// 111 presses to reach An-Nas and no way at all to answer "which number is
// Ar-Rahman". That is the whole reason this exists: the hub is for someone
// relearning, and someone relearning does not know the numbers yet — so the
// list is searchable by NAME, in any of the three the data carries, and by
// number for when you do know it.
ModalSheet {
    id: picker

    // [{n, ar, en, tr, count, type}] — the table `api surahs` answers with.
    required property var surahs
    property int current: 1

    signal picked(int surah)

    preferredFocus: search

    // Fold both sides to the same shape before comparing.
    //
    // Punctuation goes, and then DOUBLED LETTERS COLLAPSE, which is the part
    // that matters. The transliterations in the data spell long vowels out —
    // `Ar-Rahmaan`, `Al-Ikhlaas`, `As-Saaffaat`, `An-Naas` — and nobody types
    // them that way. A plain substring match on `rahman` found nothing at all
    // in a list that contains Ar-Rahmaan. Collapsing runs makes both sides
    // `arahman`, and `saffat`/`safat` both reach As-Saaffaat.
    //
    // Arabic harakat go for the same reason: the Arabic names are fully
    // vowelled and nobody types the marks.
    //
    // Not a fuzzy match beyond that: the list is 114 items long and a piece of
    // a word is enough to get to any of them.
    function fold(s) {
        return String(s).toLowerCase().replace(/[ً-ْٰ]/g, "").replace(/[^a-z0-9؀-ۿ]/g, "").replace(/(.)\1+/g, "$1");
    }

    readonly property var filtered: {
        const rows = picker.surahs || [];
        const raw = String(search.text).trim();
        const q = picker.fold(raw);
        if (q === "")
            return rows;
        // The number is matched against the RAW text, not the folded one:
        // collapsing runs turns "11" into "1", which would answer surah 11
        // with every surah whose number starts with a one.
        const digits = /^\d+$/.test(raw) ? raw : "";
        return rows.filter(row => (digits !== "" && String(row.n).indexOf(digits) === 0) || picker.fold(row.en).indexOf(q) >= 0 || picker.fold(row.tr).indexOf(q) >= 0 || picker.fold(row.ar).indexOf(q) >= 0);
    }

    function choose(n) {
        picker.picked(n);
        picker.dismissed();
    }

    onOpenChanged: {
        if (picker.open) {
            search.clear();
            // Land on the surah you are reading rather than at the top: the
            // list is 114 long and the one you came from is the one you are
            // most likely navigating relative to.
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
        placeholderText: "Search 114 surahs — name or number"
        onEscaped: picker.dismissed()
        onSteppedDown: list.forceActiveFocus()
        // Enter takes the top match, which is what a one-line search is for.
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

        // A query that matches nothing used to leave a tall empty box that
        // looked like the list had failed to load.
        EmptyState {
            anchors.centerIn: parent
            visible: list.count === 0
            style: picker.style
            glyph: "⌕"
            title: "No surah by that name"
            message: "Try part of the name — `nas`, `kahf`, `rahman` — or its number."
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
                    text: row.modelData.tr + " · " + row.modelData.count + " ayat · " + row.modelData.type
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
                text: row.modelData.ar
                color: picker.style.alpha(picker.style.fg, 0.85)
                font.family: picker.style.arabicFamily
                font.pixelSize: picker.style.type(17)
            }
        }
    }
}
