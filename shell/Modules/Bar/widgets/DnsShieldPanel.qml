import QtQuick
import "../components"
import "../../../components"
import "DnsShieldModel.js" as Model

// DNS Shield panel — a control surface, not a dashboard. Two sections:
//
//   FILTERS   one switch per uBlockDNS category, plus chips that open one for
//             a fixed stretch and close it again by themselves.
//   ALLOWED   the `@@||domain^` exceptions, with a box to add one and a
//             button to take it back out. These beat all 46 blocklists, which
//             is why they are listed rather than merely counted.
//
// The switches ARE one-click, and that is the point (2026-09-06): the only way
// to watch something used to be pointing the whole machine at Google, which
// unfiltered everything, helped one device, and left the caches lying. A
// category toggle writes the account profile that the home router, the office
// mini and every roaming client all resolve through.
//
// The five CHAIN diagnosis rows were removed on request the same day. The one
// fact worth keeping from them — is THIS machine actually resolving through
// the filter, or did somebody switch it to Google — is now the verdict on the
// header's trailing edge, which is where you look first anyway.
//
// r re-probes, o opens the uBlockDNS dashboard (the query log and anything
// finer-grained lives there), 1-4 toggle a category. All of them yield to the
// allow box while it has focus, the way any text field takes plain keys.
BarPanel {
    id: panel

    required property var dnsshield

    panelTitle: ""
    cardWidth: theme.space(85)

    readonly property var categories: dnsshield.categories
    readonly property var allowed: Model.allowedList(dnsshield.filters)
    // A write is in flight. `pending` carries whichever category id or domain
    // is being changed, so one property drives both the global "hold on" and
    // the per-row dimming.
    readonly property bool busy: dnsshield.pending !== ""

    // The two offered durations. Anything else is a CLI call away
    // (`dns-filter off youtube 45m`) and did not earn a third chip.
    readonly property var durations: [
        {
            label: "30m",
            seconds: 1800
        },
        {
            label: "2h",
            seconds: 7200
        }
    ]

    function submitAllow() {
        const value = allowField.text.trim();
        if (value === "")
            return;
        panel.dnsshield.allowDomain(value);
        allowField.text = "";
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_R:
            panel.dnsshield.refresh();
            break;
        case Qt.Key_O:
            panel.dnsshield.openDashboard();
            break;
        case Qt.Key_1:
        case Qt.Key_2:
        case Qt.Key_3:
        case Qt.Key_4:
            {
                const idx = event.key - Qt.Key_1;
                if (idx < panel.categories.length)
                    panel.dnsshield.toggleCategory(panel.categories[idx].id);
                break;
            }
        default:
            return;
        }
        event.accepted = true;
    }

    // Probe-on-open: one snapshot squares the switches with reality. The box
    // is cleared too — the panel's loader outlives a close, so a half-typed
    // domain from last time was still sitting there on the next open.
    onPanelOpened: {
        panel.dnsshield.refresh();
        allowField.text = "";
    }

    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "DNS Shield"
        meta: Model.heroMeta(panel.dnsshield.state)
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            text: "󰞀"
            pixelSize: panel.theme.fontPx(1.6)
            color: panel.dnsshield.healthy ? panel.theme.textPrimary : panel.theme.textMuted
            opacity: panel.dnsshield.healthy ? 1.0 : 0.6
        }

        // This device's own verdict. Red for anything that is not "filtered":
        // a bypassed machine is browsing unfiltered right now, and that is
        // worth the same colour as an error even though nothing is broken.
        trailing: StyledText {
            theme: panel.theme
            role: StyledText.Caption
            mono: true

            anchors.verticalCenter: parent.verticalCenter
            text: panel.dnsshield.deviceStatus.label
            color: panel.dnsshield.deviceStatus.ok ? panel.theme.textPrimary : panel.theme.error
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.dnsshield.lastError !== ""
        width: parent.width
        text: panel.dnsshield.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.dnsshield.filtersError !== ""
        width: parent.width
        text: panel.dnsshield.filtersError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
    }

    // ---------------------------------------------------------------- filters
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "FILTERS"
            value: panel.dnsshield.filtersRefreshing && panel.categories.length === 0 ? "READING" : Model.categoriesSummary(panel.dnsshield.filters)
        }

        Column {
            id: categoryColumn

            width: parent.width
            spacing: panel.theme.space(0.5)

            Repeater {
                model: panel.categories

                CategoryRow {
                    required property var modelData

                    width: categoryColumn.width
                    cat: modelData
                }
            }
        }
    }

    Separator {
        theme: panel.theme
    }

    // ---------------------------------------------------------------- allowed
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "ALLOWED"
            value: panel.allowed.length === 0 ? "NONE" : String(panel.allowed.length)
        }

        // Add a domain. Enter or the + chip both submit; the field takes plain
        // keys while it is focused, which is why the panel's 1-4 shortcuts are
        // only live when it is not.
        Item {
            width: parent.width
            implicitHeight: allowField.implicitHeight

            PanelTextField {
                id: allowField

                theme: panel.theme
                anchors.left: parent.left
                anchors.right: addChip.left
                anchors.rightMargin: panel.theme.space(1.5)
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: panel.theme.space(7)
                inputMargin: panel.theme.space(2)
                placeholder: "Allow a domain — e.g. t.co"
                enabled: !panel.busy

                onAccepted: panel.submitAllow()
                onCancelled: {
                    // Escape clears a half-typed domain first and only closes
                    // the panel on a second press, so a typo does not cost you
                    // the whole panel.
                    if (text !== "")
                        text = "";
                    else
                        panel.close();
                }
            }

            ChipSurface {
                id: addChip

                theme: panel.theme
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: panel.theme.space(8)
                implicitHeight: panel.theme.space(7)
                pointerOver: addMouse.containsMouse
                opacity: panel.busy || allowField.text.trim() === "" ? 0.4 : 1

                OpticalGlyph {
                    anchors.centerIn: parent
                    text: "󰐕"
                    color: panel.theme.textPrimary
                    pixelSize: panel.theme.fontPx(1.0)
                }

                MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.submitAllow()
                }

                PanelHint {
                    theme: panel.theme
                    visible: addMouse.containsMouse
                    anchor: addChip
                    above: true
                    text: "Allow this domain through every blocklist"
                }
            }
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Caption
            muted: true

            visible: panel.allowed.length === 0
            width: parent.width
            leftPadding: panel.theme.space(2.5)
            text: "Nothing is punched through the blocklists."
        }

        Column {
            id: allowColumn

            width: parent.width
            spacing: panel.theme.space(0.5)

            Repeater {
                model: panel.allowed

                AllowRow {
                    required property var modelData

                    width: allowColumn.width
                    domain: String(modelData)
                }
            }
        }
    }

    // --------------------------------------------------------------- footer
    Item {
        width: parent.width
        implicitHeight: dashboardChip.implicitHeight

        ChipSurface {
            id: dashboardChip

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            theme: panel.theme
            implicitWidth: panel.theme.space(8)
            implicitHeight: panel.theme.space(7)
            pointerOver: dashboardMouse.containsMouse

            OpticalGlyph {
                anchors.centerIn: parent
                text: "󰖟"
                color: panel.theme.textPrimary
                pixelSize: panel.theme.fontPx(1.0)
            }

            MouseArea {
                id: dashboardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.dnsshield.openDashboard()
            }

            PanelHint {
                theme: panel.theme
                visible: dashboardMouse.containsMouse
                anchor: dashboardChip
                above: true
                text: "Open dashboard"
            }
        }
    }

    // ----------------------------------------------------------- components
    // A category, its state sentence, the chips that open it for a while, and
    // the switch. The whole row is the target for the plain on/off — the
    // switch alone is a small thing to hit — while each chip owns its own tap.
    //
    // MouseAreas throughout, not TapHandlers, and that is the AirPods lesson
    // (see AirPodsPanel's SwitchRow): pointer handlers do not consume a tap,
    // so a chip built on a TapHandler would fire the row's toggle as well and
    // the two would fight. A MouseArea declared after the row's grabs the
    // click and stops there. PanelSwitch's own TapHandler stays unconnected
    // for the same reason — it is the indicator, not the control.
    component CategoryRow: CursorSurface {
        id: catRow

        property var cat: null

        readonly property bool rowBusy: catRow.cat && panel.dnsshield.pending === catRow.cat.id

        theme: panel.theme
        implicitHeight: catText.implicitHeight + panel.theme.space(3)
        hasCursor: catHover.hovered
        opacity: catRow.rowBusy ? 0.5 : 1

        Column {
            id: catText

            anchors.left: parent.left
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.right: chipRow.left
            anchors.rightMargin: panel.theme.space(1.5)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(0.25)

            StyledText {
                theme: panel.theme

                width: parent.width
                text: catRow.cat ? catRow.cat.label : ""
                elide: Text.ElideRight
            }

            StyledText {
                theme: panel.theme
                role: StyledText.Caption
                mono: true
                muted: true

                width: parent.width
                text: catRow.cat ? catRow.cat.caption : ""
                elide: Text.ElideRight
            }
        }

        // Only for a category that is currently blocked: "open it for a while"
        // is the whole question here, and a category that is already open has
        // nothing to offer but the switch back.
        Row {
            id: chipRow

            anchors.right: catSwitch.left
            anchors.rightMargin: panel.theme.space(1.5)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(1)
            visible: catRow.cat && catRow.cat.on

            Repeater {
                model: panel.durations

                ChipSurface {
                    id: chip

                    required property var modelData

                    theme: panel.theme
                    implicitWidth: panel.theme.space(7)
                    implicitHeight: panel.theme.space(5)
                    pointerOver: chipMouse.containsMouse

                    StyledText {
                        anchors.centerIn: parent
                        theme: panel.theme
                        role: StyledText.Caption
                        mono: true
                        text: chip.modelData.label
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.dnsshield.setCategory(catRow.cat.id, false, chip.modelData.seconds)
                    }

                    PanelHint {
                        theme: panel.theme
                        visible: chipMouse.containsMouse
                        anchor: chip
                        above: true
                        text: "Open for " + chip.modelData.label + ", then block again"
                    }
                }
            }
        }

        PanelSwitch {
            id: catSwitch

            theme: panel.theme
            anchors.right: parent.right
            anchors.rightMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            checked: catRow.cat ? catRow.cat.on : false
            hasCursor: catRow.hasCursor
            busy: catRow.rowBusy
        }

        HoverHandler {
            id: catHover
            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            anchors.fill: parent
            // Declared before chipRow's MouseAreas in stacking order, so a
            // click on a chip never reaches this.
            z: -1
            onClicked: {
                if (catRow.cat)
                    panel.dnsshield.toggleCategory(catRow.cat.id);
            }
        }
    }

    // One allowed domain and the button that takes it back out. No whole-row
    // gesture here on purpose: removing an exception re-blocks a domain
    // something depends on, so it wants a deliberate click on a small target,
    // not a click anywhere on a wide row.
    component AllowRow: CursorSurface {
        id: allowRow

        property string domain: ""

        readonly property bool rowBusy: panel.dnsshield.pending === allowRow.domain

        theme: panel.theme
        implicitHeight: panel.theme.space(7)
        hasCursor: allowHover.hovered
        opacity: allowRow.rowBusy ? 0.5 : 1

        StyledText {
            theme: panel.theme
            mono: true

            anchors.left: parent.left
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.right: removeChip.left
            anchors.rightMargin: panel.theme.space(1.5)
            anchors.verticalCenter: parent.verticalCenter
            text: allowRow.domain
            elide: Text.ElideRight
        }

        ChipSurface {
            id: removeChip

            theme: panel.theme
            anchors.right: parent.right
            anchors.rightMargin: panel.theme.space(1.5)
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: panel.theme.space(6)
            implicitHeight: panel.theme.space(5)
            pointerOver: removeMouse.containsMouse

            OpticalGlyph {
                anchors.centerIn: parent
                text: "󰅖"
                color: removeMouse.containsMouse ? panel.theme.error : panel.theme.textMuted
                pixelSize: panel.theme.fontPx(0.9)
            }

            MouseArea {
                id: removeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.dnsshield.unallowDomain(allowRow.domain)
            }

            PanelHint {
                theme: panel.theme
                visible: removeMouse.containsMouse
                anchor: removeChip
                above: true
                text: "Stop allowing " + allowRow.domain
            }
        }

        HoverHandler {
            id: allowHover
        }
    }
}
