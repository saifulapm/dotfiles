import QtQuick
import "../../components"
import "../../components/FilterKeys.js" as FilterKeys

// Which release to play — the hub's answer to the CLI's release menu. Every
// release from every indexer, best first, with quality, size, seeders and
// audio on each row; typing filters the list (`hindi`, `dual`, `1080p`), the
// same way the terminal menu does. The first row keeps the old behaviour —
// let dekho measure and decide — so one extra Enter is the whole cost of the
// screen when you don't care.
Item {
    id: releases

    required property var theme
    // The hub's module-local type scale (Dekho.qml `fonts`).
    required property var fonts
    property real edgePad: 24
    property string label: ""
    // Rows from `dekho api releases`: {hash, title, quality, size, seeders, audio}.
    property var items: []
    property bool loading: false
    property string error: ""
    // Wrong-title strangers the guard dropped before this list was made.
    property int dropped: 0

    // null means "let dekho decide"; otherwise the chosen row's info hash.
    signal picked(var hash)
    signal dismissed

    property string filter: ""
    property int cursor: 0

    readonly property var rows: {
        const all = items || [];
        const needle = filter.trim().toLowerCase();
        if (!needle)
            return all;
        return all.filter(r => (String(r.quality) + " " + String(r.audio) + " " + String(r.title)).toLowerCase().indexOf(needle) !== -1);
    }
    // +1: the "let dekho decide" row sits above the releases and is exempt
    // from the filter — it must never be typed away.
    readonly property int rowCount: rows.length + 1

    onRowsChanged: {
        if (cursor >= rowCount)
            cursor = Math.max(0, rowCount - 1);
    }
    onCursorChanged: list.positionViewAtIndex(cursor, ListView.Contain)

    function activate() {
        if (loading)
            return;
        if (cursor === 0) {
            releases.picked(null);
            return;
        }
        const r = rows[cursor - 1];
        if (r && r.hash)
            releases.picked(String(r.hash));
    }

    function handleKey(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        switch (event.key) {
        case Qt.Key_Up:
            cursor = Math.max(0, cursor - 1);
            return true;
        case Qt.Key_Down:
            cursor = Math.min(rowCount - 1, cursor + 1);
            return true;
        case Qt.Key_PageUp:
            cursor = Math.max(0, cursor - 10);
            return true;
        case Qt.Key_PageDown:
            cursor = Math.min(rowCount - 1, cursor + 10);
            return true;
        case Qt.Key_Home:
            cursor = 0;
            return true;
        case Qt.Key_End:
            cursor = rowCount - 1;
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activate();
            return true;
        case Qt.Key_Backspace:
            if (filter)
                filter = FilterKeys.erased(filter, ctrl);
            return true;
        }
        if (ctrl && event.key === Qt.Key_U) {
            filter = "";
            return true;
        }
        if (FilterKeys.printable(event)) {
            filter += event.text;
            // Land on the first actual release the filter kept — the Auto row
            // is not what anyone typing "hindi" is aiming for.
            cursor = Math.min(1, rowCount - 1);
            return true;
        }
        return false;
    }

    Column {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Math.round(parent.height * 0.06)
        anchors.bottomMargin: releases.theme.space(6)
        width: Math.min(Math.round(parent.width * 0.72), releases.fonts.heroBody * 72)
        spacing: releases.theme.space(4)

        Row {
            width: parent.width
            spacing: releases.theme.space(4)

            GlyphButton {
                anchors.verticalCenter: parent.verticalCenter
                width: releases.theme.space(11)
                height: releases.theme.space(10)
                theme: releases.theme
                glyph: "󰁍"
                glyphSize: releases.fonts.heroMeta
                hint: "Back (Esc)"
                onActivated: releases.dismissed()
            }

            StyledText {
                width: parent.width - releases.theme.space(15)
                anchors.verticalCenter: parent.verticalCenter
                theme: releases.theme
                font.pixelSize: releases.fonts.railTitle
                font.weight: Font.Bold
                elide: Text.ElideRight
                text: "Which release? — " + releases.label
            }
        }

        StyledText {
            width: parent.width
            theme: releases.theme
            font.pixelSize: releases.fonts.meta
            color: releases.error ? releases.theme.error : releases.theme.textMuted
            elide: Text.ElideRight
            text: {
                if (releases.error)
                    return releases.error;
                if (releases.loading)
                    return "Asking the indexers…";
                const n = (releases.items || []).length;
                let line = n + " release" + (n === 1 ? "" : "s") + " · type to filter — hindi, dual, 1080p";
                if (releases.dropped > 0)
                    line += " · " + releases.dropped + " wrong-title ignored";
                return line;
            }
        }

        StyledText {
            width: parent.width
            visible: releases.filter !== ""
            theme: releases.theme
            font.pixelSize: releases.fonts.meta
            color: releases.theme.accent
            text: "filter: " + releases.filter + "  (" + releases.rows.length + " match" + (releases.rows.length === 1 ? "" : "es") + ")"
        }

        ListView {
            id: list

            width: parent.width
            height: parent.height - y
            clip: true
            model: releases.loading ? 0 : releases.rowCount
            spacing: Math.round(releases.theme.space(1) / 2)

            delegate: Rectangle {
                id: row

                required property int index

                readonly property bool isAuto: index === 0
                readonly property var rel: isAuto ? null : releases.rows[index - 1]
                readonly property bool current: index === releases.cursor

                width: list.width
                height: releases.theme.space(9)
                radius: releases.theme.radius(0.5)
                color: current ? releases.theme.alpha(releases.theme.accent, 0.16) : "transparent"
                border.width: current ? releases.theme.borderWidth : 0
                border.color: releases.theme.alpha(releases.theme.accent, 0.5)

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        releases.cursor = row.index;
                        releases.activate();
                    }
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: releases.theme.space(3)
                    anchors.rightMargin: releases.theme.space(3)
                    spacing: releases.theme.space(4)

                    StyledText {
                        width: releases.fonts.meta * 4
                        anchors.verticalCenter: parent.verticalCenter
                        theme: releases.theme
                        font.pixelSize: releases.fonts.meta
                        font.weight: Font.Bold
                        color: releases.theme.accent
                        text: row.isAuto ? "auto" : String(row.rel.quality || "")
                    }

                    StyledText {
                        width: releases.fonts.meta * 5
                        anchors.verticalCenter: parent.verticalCenter
                        theme: releases.theme
                        font.pixelSize: releases.fonts.meta
                        horizontalAlignment: Text.AlignRight
                        text: row.isAuto ? "" : String(row.rel.size || "?")
                    }

                    StyledText {
                        width: releases.fonts.meta * 7
                        anchors.verticalCenter: parent.verticalCenter
                        theme: releases.theme
                        font.pixelSize: releases.fonts.meta
                        color: releases.theme.textMuted
                        text: row.isAuto ? "" : (Number(row.rel.seeders) || 0) + " seeders"
                    }

                    StyledText {
                        width: releases.fonts.meta * 11
                        anchors.verticalCenter: parent.verticalCenter
                        theme: releases.theme
                        font.pixelSize: releases.fonts.meta
                        elide: Text.ElideRight
                        // The dual-audio label is what someone scanning for
                        // Hindi is hunting; give it the ok green.
                        color: row.rel && String(row.rel.audio).indexOf("Dual") !== -1 ? releases.theme.okColor : releases.theme.textPrimary
                        text: row.isAuto ? "" : String(row.rel.audio || "")
                    }

                    StyledText {
                        // What is left after the fixed columns.
                        width: parent.width - releases.fonts.meta * 27 - releases.theme.space(16)
                        anchors.verticalCenter: parent.verticalCenter
                        theme: releases.theme
                        font.pixelSize: releases.fonts.meta
                        color: row.isAuto ? releases.theme.textPrimary : releases.theme.textMuted
                        elide: Text.ElideRight
                        text: row.isAuto ? "Let dekho decide — best release that proves it can stream" : String(row.rel.title || "")
                    }
                }
            }
        }
    }
}
