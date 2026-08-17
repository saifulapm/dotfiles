import QtQuick
import Quickshell
import "../components"
import "../../../components"
import "ClockModel.js" as Model

// Month calendar under the clock — omarchy's clock panel, our card. Hero
// date over a year-progress rail, an optional memento-mori rail (double-tap
// the year bar to set a birth year, double-tap the life bar to clear it),
// then the month grid with ISO week numbers down a gutter column. The grid
// is a read-out rather than a picker: today is the only marked day, and the
// only thing that moves is which month is on screen — chevrons, the scroll
// wheel, and the arrow keys all step it.
BarPanel {
    id: panel

    // Injected by the clock widget: the widget itself (which owns settings
    // persistence) and its inline shell.json entry.
    property var host: null
    property var settings: ({})

    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function persistSettings(values) {
        if (host && typeof host.persistSettings === "function")
            host.persistSettings(values);
    }

    // ---- Today. SystemClock keeps this honest across midnight so the
    //      highlight rolls over without the panel being reopened.
    property date today: new Date()
    readonly property string todayKey: Model.keyForDate(today)

    // The month on screen. Stepping moves this and nothing else: there is
    // no per-day cursor to keep in sync.
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    readonly property date viewDate: new Date(viewYear, viewMonth, 1)
    readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

    // Pinned to today, not to the month being browsed — stepping through the
    // calendar does not change how much of the year is gone.
    readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
    readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

    // Memento mori. A birth year rather than an age, so it keeps counting on
    // its own. Without one the bar stays hidden.
    readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
    readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
    readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
    readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
    readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
    property bool editingLife: false

    // Unset falls through to the locale's own first day, so a fresh install
    // matches the rest of the desktop rather than a hardcoded convention.
    // Clicking the grid's "W" heading writes the choice back to shell.json.
    readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
    readonly property var weekdays: Model.weekdayOrder(weekStart)
    readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

    onPanelOpened: refresh()
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    onPanelClosed: {
        if (editingLife)
            cancelEditingLife();
    }

    function refresh() {
        today = new Date();
        goToToday();
    }

    function goToToday() {
        viewYear = today.getFullYear();
        viewMonth = today.getMonth();
    }

    function shiftMonth(delta) {
        const next = Model.stepMonth(viewYear, viewMonth, delta);
        viewYear = next.year;
        viewMonth = next.month;
    }

    function shiftYear(delta) {
        shiftMonth(delta * 12);
    }

    function setWeekStart(day) {
        const next = Model.normalizedWeekStart(day, weekStart);
        if (next === weekStart)
            return;
        persistSettings({
            weekStartDay: Model.weekStartSettingName(next)
        });
    }

    function toggleWeekStart() {
        setWeekStart(Model.toggledWeekStart(weekStart));
    }

    // Locale short day names, trimmed of the trailing period some locales
    // carry ("man." -> "MAN") so the header row stays a clean band of caps.
    function weekdayLabel(weekday) {
        return String(Qt.locale().dayName(weekday, Locale.ShortFormat)).replace(/\.$/, "").toUpperCase();
    }

    function startEditingLife() {
        editingLife = true;
        Qt.callLater(() => {
            bornField.input.text = panel.birthYear > 0 ? String(panel.birthYear) : "";
            expectancyField.input.text = String(panel.lifeExpectancy);
            bornField.input.selectAll();
            bornField.input.forceActiveFocus();
        });
    }

    function cancelEditingLife() {
        editingLife = false;
        refocusKeys();
    }

    function commitLife() {
        const born = Model.parseBirthYear(bornField.input.text, today.getFullYear());
        const span = Model.parseLifeExpectancy(expectancyField.input.text);
        if (born !== birthYear || span !== lifeExpectancy)
            persistSettings({
                birthYear: born,
                lifeExpectancy: span
            });
        cancelEditingLife();
    }

    // Double-tapping the life bar puts it away again. The expectancy stays
    // in the config so setting a birth year again brings your own number
    // back rather than the default.
    function clearLife() {
        if (birthYear <= 0)
            return;
        persistSettings({
            birthYear: 0
        });
    }

    // Shared by both fields: Tab hops to the other one, Enter commits the
    // pair, Escape drops the lot.
    function handleLifeKey(event, other) {
        if (event.key === Qt.Key_Escape) {
            cancelEditingLife();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            commitLife();
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            other.input.selectAll();
            other.input.forceActiveFocus();
            event.accepted = true;
        }
    }

    onContentKey: event => {
        if (editingLife)
            return;
        if (event.key === Qt.Key_Left) {
            shiftMonth(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            shiftMonth(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            shiftYear(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            shiftYear(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            goToToday();
            event.accepted = true;
        } else if (event.text === "[") {
            shiftMonth(-1);
            event.accepted = true;
        } else if (event.text === "]") {
            shiftMonth(1);
            event.accepted = true;
        } else if (event.text === "{") {
            shiftYear(-1);
            event.accepted = true;
        } else if (event.text === "}") {
            shiftYear(1);
            event.accepted = true;
        } else if (event.text === "t" || event.text === "T") {
            goToToday();
            event.accepted = true;
        } else if (event.text === "w" || event.text === "W") {
            toggleWeekStart();
            event.accepted = true;
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        onDateChanged: {
            if (Model.keyForDate(clock.date) === panel.todayKey)
                return;
            const followToday = panel.viewingCurrentMonth;
            panel.today = clock.date;
            if (followToday)
                panel.goToToday();
        }
    }

    component LifeField: Rectangle {
        property alias input: input
        property string placeholder: ""
        width: panel.theme.space(12)
        height: panel.theme.space(7)
        radius: panel.theme.radius(0.75)
        color: panel.theme.surface2
        border.width: panel.theme.borderWidth
        border.color: input.activeFocus ? panel.theme.accent : panel.theme.surface3

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            color: panel.theme.textPrimary
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(1.0)
            inputMethodHints: Qt.ImhDigitsOnly

            Text {
                anchors.centerIn: parent
                visible: input.text === ""
                text: parent.parent.placeholder
                color: panel.theme.textMuted
                font.family: panel.theme.fontMono
                font.pixelSize: panel.theme.fontPx(0.917)
            }
        }
    }

    // ------------------------------------------------------- hero: today
    // Once the view has stepped away it is also the way home — clicking the
    // date you are looking for beats hunting for a reset button.
    Item {
        width: parent.width
        height: heroRow.height

        Row {
            id: heroRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: panel.theme.space(3)

            OpticalGlyph {
                // Not baseline-anchored like omarchy's: OpticalGlyph is an
                // Item wrapper whose "baseline" is its top edge, which would
                // sink the icon below the date.
                anchors.verticalCenter: parent.verticalCenter
                text: "󰃭" // calendar
                color: heroMouse.containsMouse ? panel.theme.accent : panel.theme.textPrimary
                pixelSize: panel.theme.fontPx(2.0)
            }

            Text {
                id: heroDate
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(panel.today, "MMMM d")
                color: heroMouse.containsMouse ? panel.theme.accent : panel.theme.textPrimary
                font.family: panel.theme.fontMono
                font.pixelSize: panel.theme.fontPx(2.333)
                font.weight: Font.Bold
            }
        }

        MouseArea {
            id: heroMouse
            x: heroRow.x
            y: heroRow.y
            width: heroRow.width
            height: heroRow.height
            enabled: !panel.viewingCurrentMonth
            hoverEnabled: enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.goToToday()
        }
    }

    // ---------------------------------------------------- year progress
    // Doubles as the rule under the hero. Double-tap opens the memento-mori
    // editor in its place.
    Item {
        width: parent.width
        height: panel.theme.space(8)

        TapHandler {
            enabled: !panel.editingLife
            onDoubleTapped: panel.startEditingLife()
        }

        Row {
            visible: panel.editingLife
            anchors.centerIn: parent
            spacing: panel.theme.space(2)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "BORN"
                color: panel.theme.textMuted
                font.family: panel.theme.fontMono
                font.pixelSize: panel.theme.fontPx(0.75)
                font.letterSpacing: 1
            }

            LifeField {
                id: bornField
                anchors.verticalCenter: parent.verticalCenter
                placeholder: "year"
                input.Keys.onPressed: event => panel.handleLifeKey(event, expectancyField)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: panel.theme.space(1)
                text: "LIVE TO"
                color: panel.theme.textMuted
                font.family: panel.theme.fontMono
                font.pixelSize: panel.theme.fontPx(0.75)
                font.letterSpacing: 1
            }

            LifeField {
                id: expectancyField
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(10)
                placeholder: "90"
                input.Keys.onPressed: event => panel.handleLifeKey(event, bornField)
            }
        }

        Text {
            id: yearLabel
            visible: !panel.editingLife
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.today.getFullYear()
            color: panel.theme.textMuted
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.917)
        }

        Text {
            id: yearPercent
            visible: !panel.editingLife
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: panel.yearDonePercent + "%"
            color: panel.theme.textPrimary
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.917)
        }

        Item {
            visible: !panel.editingLife
            anchors.left: yearLabel.right
            anchors.right: yearPercent.left
            anchors.leftMargin: panel.theme.space(3)
            anchors.rightMargin: panel.theme.space(3)
            anchors.verticalCenter: parent.verticalCenter
            height: panel.theme.space(1.5)

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: panel.theme.surface3
            }

            Rectangle {
                width: Math.round(parent.width * panel.yearDone)
                height: parent.height
                radius: height / 2
                color: panel.theme.textPrimary

                Behavior on width {
                    NumberAnimation {
                        duration: panel.theme.time(1)
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    // ------------------------------------------------------ memento mori
    // Only here once someone has gone looking and given a birth year; the
    // same rail as the year above it, measured against a nominal lifetime.
    Item {
        visible: panel.birthYear > 0
        width: parent.width
        height: visible ? panel.theme.space(6) : 0

        TapHandler {
            onDoubleTapped: panel.clearLife()
        }

        Text {
            id: lifeLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "LIFE"
            color: panel.theme.textMuted
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.917)
            font.letterSpacing: 1
        }

        Text {
            id: lifePercent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: panel.lifeDonePercent + "%"
            color: panel.theme.textPrimary
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.917)
        }

        Item {
            anchors.left: lifeLabel.right
            anchors.right: lifePercent.left
            anchors.leftMargin: panel.theme.space(3)
            anchors.rightMargin: panel.theme.space(3)
            anchors.verticalCenter: parent.verticalCenter
            height: panel.theme.space(1.5)

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: panel.theme.surface3
            }

            Rectangle {
                width: Math.round(parent.width * panel.lifeDone)
                height: parent.height
                radius: height / 2
                color: panel.theme.textPrimary

                Behavior on width {
                    NumberAnimation {
                        duration: panel.theme.time(1)
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------- grid
    Column {
        id: gridBlock
        width: parent.width

        WheelHandler {
            onWheel: event => {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0)
                    return;
                panel.shiftMonth(event.angleDelta.y > 0 ? -1 : 1);
            }
        }

        Grid {
            columns: 8
            width: parent.width

            // The week-number heading doubles as the week-start toggle.
            Item {
                width: parent.width / 8
                height: panel.theme.space(7)

                Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartHover.hovered ? panel.theme.accent : panel.theme.textMuted
                    opacity: weekStartHover.hovered ? 1 : 0.6
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                    font.letterSpacing: 1
                    font.weight: Font.DemiBold
                }

                HoverHandler {
                    id: weekStartHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: panel.toggleWeekStart()
                }
            }

            Repeater {
                model: panel.weekdays

                Item {
                    required property var modelData
                    width: parent.width / 8
                    height: panel.theme.space(7)

                    Text {
                        anchors.centerIn: parent
                        text: panel.weekdayLabel(parent.modelData)
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontMono
                        font.pixelSize: panel.theme.fontPx(0.75)
                        font.letterSpacing: 1
                    }
                }
            }
        }

        Repeater {
            model: panel.weeks

            Row {
                id: weekRow

                required property var modelData

                width: parent.width

                Item {
                    width: parent.width / 8
                    height: panel.theme.space(8)

                    Text {
                        anchors.centerIn: parent
                        text: weekRow.modelData.week
                        color: panel.theme.textMuted
                        opacity: 0.6
                        font.family: panel.theme.fontMono
                        font.pixelSize: panel.theme.fontPx(0.833)
                    }
                }

                Repeater {
                    model: weekRow.modelData.days

                    Item {
                        required property var modelData
                        width: parent.width / 8
                        height: panel.theme.space(8)

                        Rectangle {
                            anchors.centerIn: parent
                            width: panel.theme.space(7)
                            height: width
                            radius: panel.theme.radius(0.5)
                            color: "transparent"
                            border.width: parent.modelData.today ? panel.theme.borderWidth : 0
                            border.color: panel.theme.accent
                        }

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.day
                            color: parent.modelData.today ? panel.theme.accent : (parent.modelData.inMonth ? (parent.modelData.weekend ? panel.theme.textMuted : panel.theme.textPrimary) : panel.theme.textMuted)
                            opacity: parent.modelData.inMonth || parent.modelData.today ? 1 : 0.5
                            font.family: panel.theme.fontMono
                            font.pixelSize: panel.theme.fontPx(1.0)
                            font.weight: parent.modelData.today ? Font.Bold : Font.Normal
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- footer
    Row {
        width: parent.width

        PanelButton {
            id: prevBtn
            theme: panel.theme
            label: "‹"
            onClicked: panel.shiftMonth(-1)
        }

        Text {
            width: parent.width - prevBtn.width - nextBtn.width
            height: prevBtn.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: Qt.formatDate(panel.viewDate, "MMMM yyyy").toUpperCase()
            color: monthHover.hovered && !panel.viewingCurrentMonth ? panel.theme.accent : panel.theme.textMuted
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.917)
            font.letterSpacing: 2

            HoverHandler {
                id: monthHover
                cursorShape: panel.viewingCurrentMonth ? Qt.ArrowCursor : Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: panel.goToToday()
            }
        }

        PanelButton {
            id: nextBtn
            theme: panel.theme
            label: "›"
            onClicked: panel.shiftMonth(1)
        }
    }
}
