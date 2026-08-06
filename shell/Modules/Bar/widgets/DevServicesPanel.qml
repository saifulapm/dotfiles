import QtQuick
import "../components"
import "DevServicesModel.js" as Model

// Dev-services panel — the on-demand database rows, in the family's visual
// language: a hero of the cylinder mark over the running count, the error
// line, and one row per service showing its state sentence ("Running — port
// 3306", "Armed — wakes on port 5432", "Starting…").
//
// Clicking a row toggles it: start warms the container AND its proxy service
// (the proxy holds it up until the usual 10-minute idle exit), stop lowers
// both; the sockets stay armed either way, so a stopped database still wakes
// on its next connection. Mailpit's row carries a web-UI button — a MouseArea
// layered over the full-row MouseArea (the BluetoothPanel ForgetButton
// precedent: a TapHandler's passive grab would let the press fall through
// and toggle the row too), and the web socket wakes mailpit by itself, so it
// works while armed.
//
// The cursor model is the family's single-highlight one: j/k and the arrows
// walk the rows, Enter toggles, o opens the selected row's web UI, r
// re-probes. The first arrow press only reveals the cursor.
BarPanel {
    id: panel

    required property var devservices

    panelTitle: ""
    cardWidth: theme.space(85)

    readonly property var services: devservices.services || []

    // -------------------------------------------------------------- cursor
    property int serviceIndex: 0
    property bool cursorActive: false

    function moveCursor(dy) {
        cursorActive = true;
        if (services.length === 0)
            return;
        serviceIndex = Math.max(0, Math.min(services.length - 1, serviceIndex + dy));
    }

    function selectedService() {
        if (services.length === 0)
            return null;
        return services[Math.max(0, Math.min(serviceIndex, services.length - 1))];
    }

    function activateCursor() {
        if (!cursorActive) {
            cursorActive = true;
            return;
        }
        panel.devservices.toggleService(selectedService());
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            panel.moveCursor(panel.cursorActive ? 1 : 0);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            panel.moveCursor(panel.cursorActive ? -1 : 0);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            panel.activateCursor();
            break;
        case Qt.Key_R:
            panel.devservices.refresh();
            break;
        case Qt.Key_O:
            panel.devservices.openWeb(panel.selectedService());
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------ lifecycle
    // Probe-on-open: one `podman ps` snapshot squares the rows with reality;
    // everything after that arrives through the events follower.
    onPanelOpened: {
        panel.cursorActive = false;
        panel.serviceIndex = 0;
        panel.devservices.refresh();
    }

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Dev Services"
        meta: Model.heroMeta(panel.devservices.runningCount, panel.devservices.serviceCount)
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: DevServicesIcon {
            iconSize: panel.theme.fontPx(1.6)
            color: panel.devservices.runningCount > 0 ? panel.theme.textPrimary : panel.theme.textMuted
            opacity: panel.devservices.runningCount > 0 ? 1.0 : 0.6
        }
    }

    // ---------------------------------------------------------------- error
    Text {
        visible: panel.devservices.lastError !== ""
        width: parent.width
        text: panel.devservices.lastError
        color: panel.theme.error
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.833)
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
    }

    // ----------------------------------------------------------------- rows
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "SERVICES"
            value: panel.devservices.runningCount > 0 ? panel.devservices.runningCount + " RUNNING" : "ARMED"
        }

        Column {
            id: rowColumn

            width: parent.width
            spacing: panel.theme.space(0.5)

            Repeater {
                model: panel.services

                ServiceRow {
                    required property var modelData
                    required property int index

                    width: rowColumn.width
                    svc: modelData
                    rowIndex: index
                }
            }
        }
    }

    // --------------------------------------------------------------- footer
    Text {
        width: parent.width
        text: "First connection wakes a service; ten idle minutes stop it. The ports stay armed either way."
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.75)
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    component ServiceRow: CursorSurface {
        id: row

        theme: panel.theme

        property var svc: null
        property int rowIndex: 0

        readonly property bool rowSelected: panel.cursorActive && panel.serviceIndex === rowIndex
        readonly property bool isRunning: !!(svc && svc.running)
        readonly property bool busy: svc ? svc.pending !== "" : false
        readonly property bool hasWeb: svc ? svc.webUrl !== "" : false

        hasCursor: rowSelected
        current: isRunning
        implicitHeight: rowContent.implicitHeight + panel.theme.space(3)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: row.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) {
                panel.cursorActive = true;
                panel.serviceIndex = row.rowIndex;
            }
            onClicked: panel.devservices.toggleService(row.svc)
        }

        PanelHint {
            theme: panel.theme
            visible: rowMouse.containsMouse && !row.busy && !webMouse.containsMouse
            anchor: row
            text: row.isRunning ? "Stop" : "Start"
        }

        Item {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: Math.max(rowMark.implicitHeight, rowLabels.implicitHeight, webButton.implicitHeight)

            DevServicesIcon {
                id: rowMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconSize: panel.theme.fontPx(1.083)
                color: row.isRunning || row.busy ? panel.theme.textPrimary : panel.theme.textMuted
            }

            Column {
                id: rowLabels

                anchors.left: rowMark.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: webButton.visible ? webButton.left : parent.right
                anchors.rightMargin: webButton.visible ? panel.theme.space(2) : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                Text {
                    width: parent.width
                    text: row.svc ? row.svc.label : ""
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: Model.stateText(row.svc)
                    color: row.isRunning || row.busy ? panel.theme.textPrimary : panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                    elide: Text.ElideRight
                }
            }

            // Their PanelActionButton shape: a bordered square holding one
            // glyph (md-web renders under the Symbols Nerd Font fallback).
            Rectangle {
                id: webButton

                visible: row.hasWeb
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: panel.theme.space(8)
                implicitHeight: panel.theme.space(7)
                radius: panel.theme.radius(0.75)
                color: webMouse.containsMouse ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2
                border.width: panel.theme.borderWidth
                border.color: panel.theme.surface3

                OpticalGlyph {
                    anchors.centerIn: parent
                    text: "󰖟"
                    color: panel.theme.textPrimary
                    pixelSize: panel.theme.fontPx(1.0)
                }

                // A MouseArea rather than a TapHandler: the row underneath
                // has its own full-fill MouseArea, and a TapHandler's passive
                // grab would let the press fall through — one click on the
                // globe would open the web UI AND toggle the service.
                MouseArea {
                    id: webMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.devservices.openWeb(row.svc)
                }

                PanelHint {
                    theme: panel.theme
                    visible: webMouse.containsMouse
                    anchor: webButton
                    text: row.isRunning ? "Open web UI" : "Open web UI — wakes Mailpit"
                }
            }
        }
    }
}
