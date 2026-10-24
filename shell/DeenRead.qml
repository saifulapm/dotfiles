import QtQuick
import QtQuick.Layouts

// Deen's Read section; its own task draws it.
FocusScope {
    id: page

    required property var deen

    function state() {
        return {};
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
        DeenKeys {
            Layout.fillWidth: true
            deen: page.deen
            pairs: [["tab", "section"], ["esc", "close"]]
        }
    }
}
