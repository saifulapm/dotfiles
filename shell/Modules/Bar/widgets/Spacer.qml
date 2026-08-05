import QtQuick

// Fixed-width gap for the bar layout arrays.
Item {
    required property var theme
    property int size: 12

    implicitWidth: theme.space(size / 4)
    implicitHeight: parent ? parent.height : 1
}
