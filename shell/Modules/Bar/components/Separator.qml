import QtQuick

// Section divider hairline. Defaults to its parent's width, which is the
// content column in every panel that used to declare its own copy.
Rectangle {
    required property var theme
    width: parent ? parent.width : 0
    height: 1
    color: theme.surface3
}
