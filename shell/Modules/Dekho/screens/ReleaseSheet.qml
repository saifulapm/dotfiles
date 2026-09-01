import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

// Which release? — omakade's link dialog (qml/Main.qml:970–1125), which is the
// same question in a different domain: a headline, a line saying what the list
// is, a TextField that filters it, a ListView of focusable rows, and a CLOSE.
//
// IT IS A SHEET NOW, NOT A SCREEN. The old one was a nav-stack entry, which
// meant choosing a release pushed and popped two screens to get to playback and
// Escape had to unwind both. A release choice is a question about the title you
// are looking at, so it belongs over that title — which is also what puts it in
// omakade's Escape cascade (sheet → screen → query → grid) rather than beside it.
//
// `style` is NOT redeclared here. It is ModalSheet's own required property and
// is inherited; a second `required property var style` on the derived type
// SHADOWS the base one, so the assignment in Dekho.qml lands on the derived
// property and the base stays uninitialised — which is a load failure, not a
// warning ("Required property style was not initialized", measured 2026-09-01).
ModalSheet {
    id: sheet

    property string label: ""
    property var items: []
    property bool loading: false
    property string error: ""
    // Releases filed under this title's IMDB id whose names say they are a
    // different production entirely. dekho drops them before ranking; saying
    // how many is what stops a short list looking like a broken one.
    property int dropped: 0

    signal picked(var hash)

    readonly property var rows: {
        const all = sheet.items || [];
        const needle = filterField.text.trim().toLowerCase();
        if (!needle)
            return all;
        return all.filter(r => (String(r.quality) + " " + String(r.audio) + " " + String(r.title)).toLowerCase().indexOf(needle) !== -1);
    }

    preferredFocus: filterField

    onOpenChanged: {
        if (sheet.open)
            filterField.text = "";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: sheet.style.ui(12)

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "WHICH RELEASE?"
                color: sheet.style.brightFg
                font.family: sheet.style.fontFamily
                font.pixelSize: sheet.style.type(15)
                font.weight: Font.Bold
            }
            Item {
                Layout.fillWidth: true
            }
            GlassButton {
                style: sheet.style
                compact: true
                text: "CLOSE"
                onClicked: sheet.dismissed()
            }
        }

        Text {
            Layout.fillWidth: true
            text: {
                if (sheet.error)
                    return sheet.error;
                if (sheet.loading)
                    return "Asking the indexers…";
                const n = (sheet.items || []).length;
                let line = sheet.label + " · " + n + " release" + (n === 1 ? "" : "s");
                if (sheet.dropped > 0)
                    line += " · " + sheet.dropped + " wrong-title ignored";
                return line;
            }
            color: sheet.error ? sheet.style.red : sheet.style.muted
            font.family: sheet.style.fontFamily
            font.pixelSize: sheet.style.type(10)
            wrapMode: Text.Wrap
        }

        TextField {
            id: filterField

            Layout.fillWidth: true
            placeholderText: "Filter — hindi, dual, 1080p"
            color: sheet.style.fg
            placeholderTextColor: sheet.style.alpha(sheet.style.fg, 0.42)
            font.family: sheet.style.fontFamily
            font.pixelSize: sheet.style.type(11)
            selectByMouse: true

            Keys.onDownPressed: event => {
                if (candidates.count > 0) {
                    candidates.currentIndex = 0;
                    const first = candidates.itemAtIndex(0);
                    if (first)
                        first.forceActiveFocus(Qt.TabFocusReason);
                    event.accepted = true;
                }
            }

            background: Rectangle {
                radius: sheet.style.radiusSm
                color: sheet.style.alpha(sheet.style.fg, 0.05)
                border.width: filterField.activeFocus ? sheet.style.ui(2) : sheet.style.hairline
                border.color: filterField.activeFocus ? sheet.style.accent : sheet.style.alpha(sheet.style.fg, 0.18)
            }
        }

        ListView {
            id: candidates

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: sheet.style.ui(7)
            boundsBehavior: Flickable.StopAtBounds
            // +1: the "let dekho decide" row sits above the releases and is
            // exempt from the filter — it must never be typed away.
            model: sheet.loading ? 0 : sheet.rows.length + 1

            delegate: Button {
                id: row

                required property int index

                readonly property bool isAuto: row.index === 0
                readonly property var rel: row.isAuto ? null : sheet.rows[row.index - 1]

                width: candidates.width
                height: sheet.style.ui(58)
                focusPolicy: Qt.StrongFocus
                Accessible.name: row.isAuto ? "Let dekho decide" : String(row.rel.title || "")

                onClicked: sheet.picked(row.isAuto ? null : String(row.rel.hash))
                onActiveFocusChanged: {
                    if (row.activeFocus) {
                        candidates.currentIndex = row.index;
                        candidates.positionViewAtIndex(row.index, ListView.Contain);
                    }
                }

                background: Rectangle {
                    radius: sheet.style.radiusSm
                    color: row.down || row.hovered || row.activeFocus ? sheet.style.alpha(sheet.style.fg, 0.09) : sheet.style.alpha(sheet.style.fg, 0.04)
                    border.width: row.activeFocus ? sheet.style.ui(2) : sheet.style.hairline
                    border.color: row.activeFocus ? sheet.style.accent : sheet.style.alpha(sheet.style.fg, 0.14)
                }

                contentItem: Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: sheet.style.ui(13)
                    spacing: sheet.style.ui(4)

                    Text {
                        width: parent.width
                        text: row.isAuto ? "Let dekho decide" : String(row.rel.title || "")
                        color: sheet.style.brightFg
                        font.family: sheet.style.fontFamily
                        font.pixelSize: sheet.style.type(11)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: row.isAuto ? "BEST RELEASE THAT PROVES IT CAN STREAM" : String(row.rel.quality || "").toUpperCase() + "  ·  " + String(row.rel.size || "?") + "  ·  " + (Number(row.rel.seeders) || 0) + " SEEDERS" + (row.rel.audio ? "  ·  " + String(row.rel.audio).toUpperCase() : "")
                        // The dual-audio label is what someone scanning for
                        // Hindi is hunting; give it the ok green.
                        color: row.rel && String(row.rel.audio).indexOf("Dual") !== -1 ? sheet.style.green : sheet.style.accent
                        font.family: sheet.style.fontFamily
                        font.pixelSize: sheet.style.type(9)
                        elide: Text.ElideRight
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !sheet.loading && sheet.rows.length === 0 && filterField.text !== ""
                text: "No release matched that filter"
                color: sheet.style.muted
                font.family: sheet.style.fontFamily
                font.pixelSize: sheet.style.type(11)
            }
        }
    }
}
