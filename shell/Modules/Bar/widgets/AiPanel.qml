import QtQuick
import "../components"
import "../../../components"
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
    cardWidth: theme.space(95)

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
    PanelHero {
        theme: panel.theme
        width: parent.width
        labelRightMargin: panel.theme.space(2)
        title: panel.provider ? panel.provider.providerName : "Model usage"
        titleColor: panel.usage.alarming ? panel.theme.error : panel.theme.textPrimary
        meta: Model.heroMeta(panel.provider).toUpperCase()
        metaColor: panel.provider && String(panel.provider.usageStatusText || "") !== "" ? panel.theme.warn : panel.theme.textMuted

        // Providers with a brand asset draw it; the rest fall back to a glyph.
        icon: Item {
            id: heroMark
            width: panel.theme.space(6.5)
            height: panel.theme.space(6.5)

            readonly property string markUrl: panel.provider ? String(panel.provider.markSource || "") : ""
            readonly property string glyph: panel.provider ? String(panel.provider.markGlyph || "") : ""

            Image {
                anchors.fill: parent
                visible: heroMark.glyph === ""
                source: heroMark.markUrl
                sourceSize.width: heroMark.width * 2
                sourceSize.height: heroMark.height * 2
                fillMode: Image.PreserveAspectFit
            }

            OpticalGlyph {
                anchors.centerIn: parent
                visible: heroMark.glyph !== ""
                text: heroMark.glyph
                color: panel.usage.alarming ? panel.theme.error : panel.theme.textPrimary
                pixelSize: panel.theme.fontPx(2)
            }
        }

        // Their refresh is a background interval; here it is a button (and r).
        trailing: Rectangle {
            id: refreshButton
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
                pixelSize: panel.theme.fontPx(1.167)

                RotationAnimator on rotation {
                    running: panel.usage.refreshing
                    from: 0
                    to: 360
                    duration: panel.theme.time(6)
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

            ChipSurface {
                id: providerTab

                required property var modelData
                required property int index

                readonly property bool selected: index === panel.usage.providerIndex

                theme: panel.theme
                width: providerSwitch.cellWidth
                implicitHeight: tabLabel.implicitHeight + panel.theme.space(3)
                chosen: providerTab.selected
                pointerOver: tabHover.hovered

                StyledText {
                    id: tabLabel
                    theme: panel.theme
                    role: StyledText.Small
                    anchors.centerIn: parent
                    text: providerTab.modelData.providerName
                    color: providerTab.selected ? panel.theme.accent : panel.theme.textPrimary
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

        StyledText {
            id: statusText
            theme: panel.theme
            role: StyledText.Small
            muted: true
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            text: panel.provider ? String(panel.provider.authHelpText || "") : ""
            wrapMode: Text.WordWrap
        }
    }

    // -------------------------------------------------------------- limits
    Separator {
        theme: panel.theme
        visible: panel.limits.length > 0
    }

    Column {
        visible: panel.limits.length > 0
        width: parent.width
        spacing: panel.theme.space(2.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "LIMITS"
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

                        StyledText {
                            id: limitTitle
                            theme: panel.theme
                            // A model-scoped window is titled after its model,
                            // and those names run long enough to reach the
                            // percentage, so the title gives way first. The
                            // subtitle keeps its full width — it is the shorter
                            // of the two and eliding "7-day" says nothing.
                            readonly property real available: limitValue.x - limitLabel.x - (limitSubtitle.visible ? limitSubtitle.implicitWidth + limitLabel.spacing : 0) - panel.theme.space(1.5)
                            width: Math.max(0, Math.min(implicitWidth, available))
                            elide: Text.ElideRight
                            text: limitRow.modelData.title
                        }

                        StyledText {
                            id: limitSubtitle
                            theme: panel.theme
                            role: StyledText.Caption
                            muted: true
                            anchors.baseline: limitTitle.baseline
                            visible: text !== ""
                            text: limitRow.modelData.subtitle
                        }
                    }

                    StyledText {
                        id: limitValue
                        theme: panel.theme
                        role: StyledText.Small
                        mono: true
                        anchors.right: parent.right
                        text: Math.round(limitRow.modelData.percent * 100) + "%"
                        color: limitRow.alarming ? panel.theme.error : panel.theme.textPrimary
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
                                duration: panel.theme.time(1)
                                easing.type: panel.theme.motion.easing
                            }
                        }
                    }
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    muted: true

                    text: {
                        const remaining = Model.resetMsFor(limitRow.modelData, panel.nowMs);
                        return remaining > 0 ? "Resets in " + Model.formatDuration(remaining) : "";
                    }
                }
            }
        }
    }

    Separator {
        theme: panel.theme
    }

    // --------------------------------------------------------------- today
    StyledText {
        theme: panel.theme
        muted: true

        visible: !!panel.provider && !panel.provider.ready
        text: "Scanning sessions…"
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

                StyledText {
                    theme: panel.theme
                    role: StyledText.Heading
                    mono: true

                    text: todayStat.modelData.value
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Small
                    muted: true

                    text: todayStat.modelData.label
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
            theme: panel.theme
            width: parent.width
            label: "TOKENS BY DAY"
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

                StyledText {
                    id: dayLabel
                    theme: panel.theme
                    role: StyledText.Caption
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel.theme.space(11)
                    text: dayRow.isToday ? "Today" : Model.dayName(dayRow.modelData.date)
                    color: dayRow.isToday ? panel.theme.textPrimary : panel.theme.textMuted
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
                                duration: panel.theme.time(1)
                                easing.type: panel.theme.motion.easing
                            }
                        }
                    }
                }

                StyledText {
                    id: dayValue
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel.theme.space(12)
                    horizontalAlignment: Text.AlignRight
                    text: panel.fmt(Number(dayRow.modelData.messageCount || 0))
                    color: dayRow.isToday ? panel.theme.textPrimary : panel.theme.textMuted
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
            theme: panel.theme
            width: parent.width
            label: "TOKENS BY MODEL"
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
                            duration: panel.theme.time(1)
                            easing.type: panel.theme.motion.easing
                        }
                    }
                }

                StyledText {
                    id: modelName
                    theme: panel.theme
                    role: StyledText.Small
                    anchors.left: parent.left
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.right: modelTokens.left
                    anchors.rightMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelRow.modelData.name
                    elide: Text.ElideRight
                }

                StyledText {
                    id: modelTokens
                    theme: panel.theme
                    role: StyledText.Small
                    mono: true
                    muted: true
                    anchors.right: parent.right
                    anchors.rightMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.fmt(modelRow.modelData.total)
                }
            }
        }
    }

    // Only speaks up when the numbers cover more than this machine.
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

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
        elide: Text.ElideRight
    }
}
