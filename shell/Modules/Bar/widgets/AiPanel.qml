import QtQuick
import "../components"
import "AiModel.js" as Model

// Model-usage panel — port of omarchy's model-usage Panel.qml in our tokens:
// a hero of the provider's mark, its name and the plan it is paid for, the
// provider switch when more than one has numbers, the status card when a
// provider has something to say, the LIMITS meters with their reset
// countdowns, then the local numbers (today, tokens by day, tokens by model).
//
// Their panel refreshes on a background interval; ours refreshes when it opens
// and from the refresh button, in line with this shell's no-polling rule.
BarPanel {
    id: panel

    required property var usage

    panelTitle: ""
    cardWidth: 380

    readonly property var provider: usage.provider
    readonly property var limits: usage.limits
    readonly property var models: Model.modelRows(provider)
    readonly property var days: provider ? (provider.recentDays || []) : []
    readonly property real peak: Math.max(1, Model.weekPeak(provider))

    // Countdowns and the "today" row read this instead of Date.now() so the
    // panel keeps telling the truth while it sits open — including across
    // midnight.
    property double nowMs: Date.now()

    onPanelOpened: nowMs = Date.now()

    // Cheap enough to keep running while open: it only re-evaluates text
    // bindings, and a stale "resets in 2h" is worse than a timer.
    Timer {
        interval: 30000
        running: panel.opened
        repeat: true
        onTriggered: panel.nowMs = Date.now()
    }

    // Their key model: left/right switch provider, r refreshes.
    onContentKey: event => {
        if (event.key === Qt.Key_Left) {
            panel.usage.selectProvider(panel.usage.providerIndex - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            panel.usage.selectProvider(panel.usage.providerIndex + 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            panel.usage.refresh();
            event.accepted = true;
        }
    }

    function fmt(n) {
        return Model.formatTokenCount(n);
    }

    // ------------------------------------------------------------- hero row
    Item {
        width: parent.width
        height: Math.max(heroMark.height, heroLabels.implicitHeight, refreshButton.height)

        Image {
            id: heroMark
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            source: panel.provider ? panel.provider.markSource : ""
            width: 26
            height: 26
            sourceSize.width: 52
            sourceSize.height: 52
            fillMode: Image.PreserveAspectFit
        }

        Column {
            id: heroLabels
            anchors.left: heroMark.right
            anchors.leftMargin: panel.theme.space(3)
            anchors.right: refreshButton.left
            anchors.rightMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(0.5)

            Text {
                width: parent.width
                text: panel.provider ? panel.provider.providerName : "Model usage"
                color: panel.usage.alarming ? panel.theme.error : panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(1.083)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: Model.heroMeta(panel.provider).toUpperCase()
                color: panel.provider && String(panel.provider.usageStatusText || "") !== "" ? panel.theme.warn : panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.75)
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                elide: Text.ElideRight
            }
        }

        // Their refresh is a background interval; here it is a button (and r).
        Rectangle {
            id: refreshButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: panel.theme.space(8)
            height: width
            radius: panel.theme.radius(0.75)
            color: refreshHover.hovered ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : "transparent"
            border.width: panel.theme.borderWidth
            border.color: panel.theme.surface3

            OpticalGlyph {
                anchors.centerIn: parent
                text: "󰑐"
                color: panel.theme.textMuted
                pixelSize: 14

                RotationAnimator on rotation {
                    running: panel.usage.refreshing
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
            }

            HoverHandler {
                id: refreshHover
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: panel.usage.refresh()
            }
        }
    }

    // ------------------------------------------------------ provider switch
    Row {
        id: providerSwitch

        readonly property real cellWidth: panel.usage.providers.length > 0 ? (width - spacing * (panel.usage.providers.length - 1)) / panel.usage.providers.length : 0

        visible: panel.usage.providers.length > 1
        width: parent.width
        spacing: panel.theme.space(1.5)

        Repeater {
            model: panel.usage.providers

            Rectangle {
                id: providerTab

                required property var modelData
                required property int index

                readonly property bool selected: index === panel.usage.providerIndex

                width: providerSwitch.cellWidth
                implicitHeight: tabLabel.implicitHeight + panel.theme.space(3)
                radius: panel.theme.radius(0.75)
                color: selected ? panel.theme.alpha(panel.theme.accent, 0.25) : (tabHover.hovered ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2)
                border.width: panel.theme.borderWidth
                border.color: selected ? panel.theme.accent : panel.theme.surface3

                Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: providerTab.modelData.providerName
                    color: providerTab.selected ? panel.theme.accent : panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.833)
                }

                HoverHandler {
                    id: tabHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: panel.usage.selectProvider(providerTab.index)
                }
            }
        }
    }

    // -------------------------------------------------------------- status
    Rectangle {
        visible: !!panel.provider && String(panel.provider.usageStatusText || "") !== ""
        width: parent.width
        implicitHeight: statusText.implicitHeight + panel.theme.space(4)
        radius: panel.theme.radius(0.75)
        color: panel.theme.alpha(panel.theme.warn, 0.10)
        border.width: panel.theme.borderWidth
        border.color: panel.theme.alpha(panel.theme.warn, 0.35)

        Text {
            id: statusText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            text: panel.provider ? String(panel.provider.authHelpText || "") : ""
            color: panel.theme.textMuted
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.833)
            wrapMode: Text.WordWrap
        }
    }

    // -------------------------------------------------------------- limits
    Rectangle {
        visible: panel.limits.length > 0
        width: parent.width
        height: 1
        color: panel.theme.surface3
    }

    Column {
        visible: panel.limits.length > 0
        width: parent.width
        spacing: panel.theme.space(2.5)

        SectionHeader {
            text: "LIMITS"
        }

        Repeater {
            model: panel.limits

            Column {
                id: limitRow

                required property var modelData

                readonly property bool alarming: modelData.percent >= 0.9

                width: parent.width
                spacing: panel.theme.space(1.5)

                Item {
                    width: parent.width
                    height: limitLabel.implicitHeight

                    Row {
                        id: limitLabel
                        anchors.left: parent.left
                        spacing: panel.theme.space(1.5)

                        Text {
                            id: limitTitle
                            text: limitRow.modelData.title
                            color: panel.theme.textPrimary
                            font.family: panel.theme.fontUi
                            font.pixelSize: panel.theme.fontPx(0.917)
                        }

                        Text {
                            anchors.baseline: limitTitle.baseline
                            visible: text !== ""
                            text: limitRow.modelData.subtitle
                            color: panel.theme.textMuted
                            font.family: panel.theme.fontUi
                            font.pixelSize: panel.theme.fontPx(0.75)
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        text: Math.round(limitRow.modelData.percent * 100) + "%"
                        color: limitRow.alarming ? panel.theme.error : panel.theme.textPrimary
                        font.family: panel.theme.fontMono
                        font.pixelSize: panel.theme.fontPx(0.833)
                    }
                }

                // Rounded track showing the share of the allowance used.
                Item {
                    width: parent.width
                    height: panel.theme.space(1.5)

                    Rectangle {
                        id: meterTrack
                        anchors.fill: parent
                        radius: height / 2
                        color: panel.theme.surface3
                    }

                    Rectangle {
                        anchors.left: meterTrack.left
                        anchors.verticalCenter: meterTrack.verticalCenter
                        height: meterTrack.height
                        radius: meterTrack.radius
                        width: meterTrack.width * Math.max(0, Math.min(1, limitRow.modelData.percent))
                        color: limitRow.alarming ? panel.theme.error : panel.theme.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                Text {
                    text: {
                        const remaining = Model.resetMsFor(limitRow.modelData, panel.nowMs);
                        return remaining > 0 ? "Resets in " + Model.formatDuration(remaining) : "";
                    }
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.75)
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: panel.theme.surface3
    }

    // --------------------------------------------------------------- today
    Text {
        visible: !!panel.provider && !panel.provider.ready
        text: "Scanning sessions…"
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.917)
    }

    Row {
        visible: !!panel.provider && panel.provider.ready
        width: parent.width
        spacing: panel.theme.space(4)

        Repeater {
            model: panel.provider === null ? [] : [
                {
                    label: "prompts today",
                    value: String(panel.provider.todayPrompts)
                },
                {
                    label: "sessions",
                    value: String(panel.provider.todaySessions)
                },
                {
                    label: "tokens today",
                    value: panel.fmt(panel.provider.todayTotalTokens)
                }
            ]

            Column {
                id: todayStat

                required property var modelData

                Text {
                    text: todayStat.modelData.value
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(1.333)
                }

                Text {
                    text: todayStat.modelData.label
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.833)
                }
            }
        }
    }

    // ------------------------------------------------------- tokens by day
    Column {
        visible: panel.days.length > 0
        width: parent.width
        spacing: panel.theme.space(1)

        SectionHeader {
            text: "TOKENS BY DAY"
        }

        Repeater {
            model: panel.days

            Item {
                id: dayRow

                required property var modelData

                // By date, not by position: a scanner can hand us a window
                // that stops short of today.
                readonly property bool isToday: String(modelData.date || "") === Qt.formatDate(new Date(panel.nowMs), "yyyy-MM-dd")

                width: parent.width
                height: dayLabel.implicitHeight + panel.theme.space(1)

                Text {
                    id: dayLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel.theme.space(11)
                    text: dayRow.isToday ? "Today" : Model.dayName(dayRow.modelData.date)
                    color: dayRow.isToday ? panel.theme.textPrimary : panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.75)
                    font.weight: dayRow.isToday ? Font.DemiBold : Font.Normal
                }

                Rectangle {
                    id: dayTrack
                    anchors.left: dayLabel.right
                    anchors.right: dayValue.left
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.rightMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    height: panel.theme.space(1.5)
                    radius: height / 2
                    color: panel.theme.surface3

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * Math.max(0, Math.min(1, Number(dayRow.modelData.messageCount || 0) / panel.peak))
                        color: dayRow.isToday ? panel.theme.accent : panel.theme.alpha(panel.theme.accent, 0.55)

                        Behavior on width {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                Text {
                    id: dayValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel.theme.space(12)
                    horizontalAlignment: Text.AlignRight
                    text: panel.fmt(Number(dayRow.modelData.messageCount || 0))
                    color: dayRow.isToday ? panel.theme.textPrimary : panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                }
            }
        }
    }

    // ----------------------------------------------------- tokens by model
    Column {
        visible: panel.models.length > 0
        width: parent.width
        spacing: panel.theme.space(1)

        SectionHeader {
            text: "TOKENS BY MODEL"
        }

        Repeater {
            model: panel.models

            // The share bar fills the row behind the label instead of
            // stacking under it, which keeps the dashboard on one screen.
            Item {
                id: modelRow

                required property var modelData

                width: parent.width
                height: modelName.implicitHeight + panel.theme.space(3)

                Rectangle {
                    anchors.fill: parent
                    radius: panel.theme.radius(0.75)
                    color: panel.theme.alpha(panel.theme.textPrimary, 0.05)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, modelRow.modelData.share))
                    radius: panel.theme.radius(0.75)
                    color: panel.theme.alpha(panel.theme.accent, 0.18)

                    Behavior on width {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Text {
                    id: modelName
                    anchors.left: parent.left
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.right: modelTokens.left
                    anchors.rightMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelRow.modelData.name
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.833)
                    elide: Text.ElideRight
                }

                Text {
                    id: modelTokens
                    anchors.right: parent.right
                    anchors.rightMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.fmt(modelRow.modelData.total)
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.833)
                }
            }
        }
    }

    // Only speaks up when the numbers cover more than this machine.
    Text {
        readonly property string footer: {
            const sync = panel.usage.sync;
            if (sync && String(sync.statusText || "") !== "")
                return sync.statusText;
            if (panel.provider && panel.provider.syncEnabled && panel.provider.syncDeviceCount > 0)
                return "Merged from " + panel.provider.syncDeviceCount + " device" + (panel.provider.syncDeviceCount === 1 ? "" : "s");
            return "";
        }

        visible: footer !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: footer
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.75)
        elide: Text.ElideRight
    }

    component SectionHeader: Text {
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.75)
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }
}
