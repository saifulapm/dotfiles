import QtQuick
import Quickshell
import "../components"
import "../../../components"

// Mail — the unread Imbox count on the bar, from the HEY-style mail setup in
// ~/.config/emacs (lisp/hey-notmuch.md). The data has existed since the day
// that setup shipped: the notmuch post-new hook publishes every box's count to
// ~/.local/state/qshell/mail.json after every sync, and until now nothing read
// it.
//
// The mark is md-email (U+F01EE) plus the Imbox number. The Imbox and not the
// total, because that is the one number the whole Screener exists to protect:
// 219 strangers waiting to be screened is not news, and a bar that adds them in
// is a bar that is always shouting. The Screener's own count is one row down in
// the panel.
//
// Left click opens the panel, right click syncs now (bin/mail-sync, the same
// entry point imapnotify and the 15-minute timer use), middle click re-reads
// the state file and re-probes.
//
// On a machine with no mailbox — the Mac mini, the NUC — the widget takes no
// width and draws nothing after its one presence probe. It exists in the
// registry so "mail" can be named in a bar section, and stays inert where it has
// nothing to say (Dufs's rule for a missing binary).
BarButton {
    id: rootItem

    // The icon slot, until a number joins the glyph and the slot has to size to
    // its content instead — Battery's rule for its percentage label.
    fixedWidth: vertical ? -1 : (countShown ? -1 : 27)
    fixedHeight: vertical ? 27 : -1

    visible: mail.probed && mail.installed

    // The shared service, injected by the bar's registry — ONE instance however
    // many screens carry this widget (S2).
    required property MailService mail

    // The number is a horizontal-bar affordance: on a vertical bar the family
    // shows the mark alone (omarchy hides the labels there), and three digits
    // do not fit across a 27 px bar anyway.
    readonly property bool countShown: !vertical && mail.haveCounts && mail.imbox > 0

    // Whether there is anything to read. Drives the mark the way `active` drives
    // Dufs's, and NOT through BarButton.active: that recolors content to
    // theme.error, omarchy's red "this wants you now", and unread mail is the
    // ordinary state of a mailbox rather than an alert. An envelope permanently
    // red beside a Screener permanently 219 deep tells you nothing.
    readonly property bool unread: mail.haveCounts && mail.imbox > 0

    // The hook's own notification wording, so the bar and the banner that
    // announced the mail say the same thing.
    tooltipText: {
        if (mail.syncing)
            return "Mail — syncing";
        if (!mail.haveCounts)
            return "Mail — no counts published yet";
        const head = mail.imbox === 0 ? "Imbox clear" : mail.imbox + " unread in your Imbox";
        return head + " · " + mail.screener + " waiting in the Screener";
    }

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("MailPanel.qml", {
                theme: rootItem.theme,
                mail: rootItem.mail
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            mail.sync();
        else if (button === Qt.MiddleButton)
            mail.refresh();
        else
            openPanel();
    }

    // Children of BarButton's centered content row, so only the vertical
    // anchors are theirs to set (a Row forbids the horizontal ones).
    OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰇮" // md-email
        pixelSize: 13
        verticalInkCenter: true
        color: rootItem.unread ? rootItem.barFg : Qt.darker(rootItem.barFg, 1.55)
        opacity: rootItem.unread ? 1.0 : 0.6
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    StyledText {
        theme: rootItem.theme
        role: StyledText.Small
        mono: true

        anchors.verticalCenter: parent.verticalCenter
        visible: rootItem.countShown
        text: rootItem.mail.imbox
        color: rootItem.barFg
        renderType: Text.NativeRendering
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    Loader {
        id: panelLoader
        visible: false
    }
}
