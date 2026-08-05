import QtQuick
import "../components"
import "AiModel.js" as Model

// Claude Code usage panel — port of omarchy's model-usage Panel.qml in our
// tokens: a hero naming the tool and the plan it is paid for, the LIMITS
// section with a meter and a reset countdown per window, then the local
// numbers (today, tokens by day, tokens by model) from bin/claude-usage-scan.
//
// Their panel refreshes on a background interval; ours refreshes when it opens
// and when the refresh button is pressed, in line with this shell's
// no-polling rule.
BarPanel {
    id: panel

    required property var usage

    panelTitle: ""
    cardWidth: 380

    // Countdowns read this instead of Date.now() so the panel keeps telling
    // the truth while it sits open.
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

    // r refreshes, as their key catcher does.
    onContentKey: event => {
        if (event.key === Qt.Key_R) {
            panel.usage.refresh();
            event.accepted = true;
        }
    }

    function fmt(n) {
        return Model.formatTokenCount(n);
    }

    function modelTotal(m) {
        return m.inputTokens + m.outputTokens + m.cacheReadInputTokens + m.cacheCreationInputTokens;
    }

    // ------------------------------------------------------------- hero row
    Item {
        width: parent.width
        height: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, refreshButton.height)

        OpticalGlyph {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰚩"
            color: panel.usage.alarming ? panel.theme.error : panel.theme.textPrimary
            pixelSize: 28
        }

        Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: panel.theme.space(3)
            anchors.right: refreshButton.left
            anchors.rightMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(0.5)

            Text {
                width: parent.width
                text: "Claude Code"
                color: panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(1.083)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: {
                    if (panel.usage.limitStatus !== "")
                        return panel.usage.limitStatus.toUpperCase();
                    return (panel.usage.tierLabel || "Subscription").toUpperCase();
                }
                color: panel.usage.limitStatus !== "" ? panel.theme.warn : panel.theme.textMuted
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
                    running: panel.usage.probing || panel.usage.scanning
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

    // -------------------------------------------------------------- limits
    Rectangle {
        visible: panel.usage.limitWindows.length > 0
        width: parent.width
        height: 1
        color: panel.theme.surface3
    }

    Column {
        visible: panel.usage.limitWindows.length > 0
        width: parent.width
        spacing: panel.theme.space(2.5)

        SectionHeader {
            text: "LIMITS"
        }

        Repeater {
            model: panel.usage.limitWindows

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

    Text {
        visible: panel.usage.limitWindows.length === 0
        width: parent.width
        text: panel.usage.limitStatus !== "" ? panel.usage.limitStatus + " Local Claude Code stats are still shown." : "Reading Anthropic's usage limits…"
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.833)
        wrapMode: Text.WordWrap
    }

    Rectangle {
        width: parent.width
        height: 1
        color: panel.theme.surface3
    }

    // --------------------------------------------------------------- today
    Text {
        visible: panel.usage.stats === null
        text: "Scanning ~/.claude sessions…"
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.917)
    }

    Row {
        visible: panel.usage.stats !== null
        width: parent.width
        spacing: panel.theme.space(4)

        Repeater {
            model: panel.usage.stats === null ? [] : [
                {
                    label: "prompts today",
                    value: String(panel.usage.stats.todayPrompts)
                },
                {
                    label: "sessions",
                    value: String(panel.usage.stats.todaySessions)
                },
                {
                    label: "tokens today",
                    value: panel.fmt(panel.usage.stats.todayTotalTokens)
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
        visible: panel.usage.stats !== null
        width: parent.width
        spacing: panel.theme.space(1)

        SectionHeader {
            text: "TOKENS BY DAY"
        }

        Repeater {
            model: panel.usage.stats === null ? [] : panel.usage.stats.dailyActivity

            Item {
                id: dayRow

                required property var modelData

                readonly property real peak: {
                    let max = 1;
                    for (const d of panel.usage.stats.dailyActivity)
                        max = Math.max(max, d.messageCount);
                    return max;
                }
                readonly property bool isToday: modelData.date === Qt.formatDate(new Date(panel.nowMs), "yyyy-MM-dd")

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
                        width: parent.width * Math.max(0, Math.min(1, dayRow.modelData.messageCount / dayRow.peak))
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
                    text: panel.fmt(dayRow.modelData.messageCount)
                    color: dayRow.isToday ? panel.theme.textPrimary : panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                }
            }
        }
    }

    // ----------------------------------------------------- tokens by model
    Column {
        visible: panel.modelRows.length > 0
        width: parent.width
        spacing: panel.theme.space(1)

        SectionHeader {
            text: "TOKENS BY MODEL"
        }

        Repeater {
            model: panel.modelRows

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

    // Top four models by total tokens, each scaled to the heaviest — the same
    // scale-to-peak the day chart uses.
    readonly property var modelRows: {
        if (usage.stats === null)
            return [];
        const usageByModel = usage.stats.modelUsage || {};
        const rows = [];
        for (const id in usageByModel) {
            rows.push({
                name: Model.friendlyModelName(id),
                total: modelTotal(usageByModel[id])
            });
        }
        rows.sort((a, b) => b.total - a.total);
        const top = rows.slice(0, 4);
        const peak = Math.max(1, top.length > 0 ? top[0].total : 1);
        for (let i = 0; i < top.length; i++)
            top[i].share = top[i].total / peak;
        return top;
    }

    component SectionHeader: Text {
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.75)
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }
}
