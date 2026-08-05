import QtQuick

// Fixed gap for the bar layout arrays: a width on a horizontal bar, a height
// on a vertical one (omarchy's spacer swaps the same way).
Item {
    required property var theme
    property var bar: null
    property int size: 12

    readonly property bool vertical: bar ? bar.vertical === true : false
    readonly property int barSize: bar ? bar.barSize : theme.barHeight
    readonly property int span: theme.space(size / 4)

    implicitWidth: bar && bar.vertical === true ? barSize : span
    implicitHeight: bar && bar.vertical === true ? span : barSize
}
