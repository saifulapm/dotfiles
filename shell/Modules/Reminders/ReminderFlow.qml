import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../components"
import "ReminderFlowModel.js" as ReminderFlowModel
import "../../components/FilterKeys.js" as FilterKeys

// Reminder capture flow: a fullscreen overlay with one centered input line,
// asked twice. Ported from omarchy's reminders plugin (CREDITS.md) — their
// two-step flow (minutes, then message), their prompts, their validation
// (`ReminderFlowModel.js`), their submit rules (an empty minutes line
// dismisses, an unparseable one notifies and stays put, an empty message is
// allowed and lets the CLI name the reminder) and their key model (Escape
// clears the line before it closes, every printable key is text). The chrome
// is our launcher/menu/emoji language: scrim, surface1 card, accent-lit input
// frame.
//
// One addition to theirs: a caption above the line, because the flow is two
// modal steps deep with nothing else on screen to say which one you are in —
// it names the step and, on the message step, the delay already chosen.
//
// Submitting shells out to `bin/reminder`, exactly as upstream shells out to
// `omarchy-reminder`: the CLI owns the store and the systemd timer that fires
// it. Nothing here schedules anything.
//
// LazyLoader-gated — nothing here exists until first summoned.
Scope {
    id: flowRoot

    required property var theme

    property bool opened: false
    // "minutes" → "message", upstream's two steps.
    property string step: "minutes"
    property string minutes: ""
    property string filterText: ""

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"
    readonly property string promptText: step === "message" ? "Reminder message" : "Remind in minutes"
    readonly property string captionText: step === "message" ? ("In " + minutes + (minutes === "1" ? " minute" : " minutes")) : "New reminder"

    // ------------------------------------------------------------ geometry
    readonly property int cardMargin: theme.space(4)
    readonly property int headerHeight: theme.space(10)
    readonly property int contentSpacing: theme.space(2)
    readonly property int cardWidth: panel.width > 0 ? Math.min(theme.space(90), panel.width - theme.space(8) * 2) : theme.space(90)

    // ---------------------------------------------------------- open/close
    function show() {
        step = "minutes";
        minutes = "";
        filterText = "";
        opened = true;
    }

    function hide() {
        opened = false;
        filterText = "";
    }

    function toggle() {
        if (opened)
            hide();
        else
            show();
    }

    function setFilter(next) {
        filterText = next;
    }

    // ------------------------------------------------------------- submit
    function submit() {
        const selection = filterText;

        if (step === "minutes") {
            // Upstream: an empty line means "never mind".
            if (!selection.trim()) {
                hide();
                return;
            }

            const nextMinutes = ReminderFlowModel.validMinutes(selection);
            if (!nextMinutes) {
                Quickshell.execDetached(["notify-send", "-a", "qshell", "Invalid reminder", "Enter the number of minutes"]);
                return;
            }

            minutes = nextMinutes;
            step = "message";
            filterText = "";
            return;
        }

        if (step === "message") {
            const args = [binDir + "reminder"].concat(ReminderFlowModel.reminderArgs(minutes, selection));
            hide();
            if (args.length > 1)
                Quickshell.execDetached(args);
        }
    }

    OverlaySurface {
        id: panel

        theme: flowRoot.theme
        opened: flowRoot.opened
        namespace: "qshell-reminders"
        cardWidth: flowRoot.cardWidth
        cardHeight: content.implicitHeight + flowRoot.cardMargin * 2
        onDismissed: flowRoot.hide()

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true

            // The line is not a TextInput: as in the other pickers, one
            // catcher owns every keystroke so Enter and Escape keep their
            // flow meaning.
            Keys.onPressed: event => {
                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

                if (event.key === Qt.Key_Escape) {
                    if (flowRoot.filterText)
                        flowRoot.setFilter("");
                    else
                        flowRoot.hide();
                } else if (event.key === Qt.Key_Backspace) {
                    // Plain backspace drops a character, Ctrl+Backspace a
                    // word, Ctrl+U the lot — upstream's Util.editsFilter.
                    if (!flowRoot.filterText)
                        return;
                    flowRoot.setFilter(FilterKeys.erased(flowRoot.filterText, ctrl));
                } else if (ctrl && event.key === Qt.Key_U) {
                    flowRoot.setFilter("");
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    flowRoot.submit();
                } else if (FilterKeys.printable(event)) {
                    flowRoot.setFilter(flowRoot.filterText + event.text);
                } else {
                    return;
                }
                event.accepted = true;
            }

            Column {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: flowRoot.cardMargin
                spacing: flowRoot.contentSpacing

                Row {
                    width: parent.width
                    spacing: flowRoot.theme.space(2)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰢌" // md-reminder, as upstream's indicator
                        color: flowRoot.theme.accent
                        font.family: flowRoot.theme.fontMono
                        font.pixelSize: flowRoot.theme.fontPx(1.0)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: flowRoot.captionText
                        color: flowRoot.theme.textMuted
                        font.family: flowRoot.theme.fontUi
                        font.pixelSize: flowRoot.theme.fontPx(0.833)
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1
                    }
                }

                Rectangle {
                    width: parent.width
                    height: flowRoot.headerHeight
                    radius: flowRoot.theme.radius(1)
                    color: flowRoot.theme.surface2
                    border.width: flowRoot.theme.borderWidth
                    border.color: flowRoot.filterText ? flowRoot.theme.accent : flowRoot.theme.surface3

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: flowRoot.theme.space(3)
                        anchors.rightMargin: flowRoot.theme.space(3)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        // Upstream's placeholder is the prompt with an
                        // ellipsis, dimmed until something is typed.
                        text: flowRoot.filterText || (flowRoot.promptText + "…")
                        color: flowRoot.filterText ? flowRoot.theme.textPrimary : flowRoot.theme.textMuted
                        font.family: flowRoot.theme.fontUi
                        font.pixelSize: flowRoot.theme.fontPx(1.1)
                    }
                }
            }
        }
    }
}
