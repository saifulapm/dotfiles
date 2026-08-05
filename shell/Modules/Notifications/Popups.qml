import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "NotificationLogic.js" as Logic

// Toast stack, top-right, one window per output. Ported from the popup half
// of omarchy's notifications Service.qml (CREDITS.md): a full-screen overlay
// surface per screen whose size never changes (adding or removing a toast
// only changes the content inside, so the compositor can never scale a stale
// buffer), click-through everywhere except over the toast column, and a slot
// delegate that owns the lifetime tick while the card stays presentational.
//
// The window exists only while this component is loaded (shell.qml gates the
// Loader on the first notification) and is visible only while there is
// something to show.
Scope {
    id: popupsRoot

    required property var theme
    required property var notifs
    // Bar edge and size, so the stack clears the bar when the bar is on the
    // top or right edge — and does not move when it is not.
    property string barPosition: "top"
    property int barSize: theme.barHeight

    readonly property int gap: theme.space(2)
    readonly property var placement: Logic.popupPlacement(barPosition, barSize + gap, gap)

    // Hover is per-notification, not per-delegate: every output renders its
    // own copy of a toast, and hovering any one of them must hold the expiry
    // on all of them — otherwise another screen's countdown removes the row
    // out from under the cursor. Keyed by originalId with a hover count; the
    // revision counter is what bindings actually depend on, since mutating a
    // plain JS map emits no change signal.
    property var hoverHolds: ({})
    property int hoverHoldsRevision: 0

    function setHoverHold(originalId, hovering) {
        const next = (hoverHolds[originalId] || 0) + (hovering ? 1 : -1);
        if (next > 0)
            hoverHolds[originalId] = next;
        else
            delete hoverHolds[originalId];
        hoverHoldsRevision++;
    }

    function hoverHeld(originalId) {
        return hoverHoldsRevision !== -1 && (hoverHolds[originalId] || 0) > 0;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: popupWindow

            required property var modelData
            screen: modelData
            visible: popupsRoot.notifs.popupModel.count > 0

            WlrLayershell.namespace: "qshell-notifications"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Keep the surface click-through except over the toast column, so
            // the rest of the (invisible) full-screen overlay never eats input.
            mask: Region {
                item: popupColumn
            }

            ColumnLayout {
                id: popupColumn
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: popupsRoot.placement.margins.top
                anchors.rightMargin: popupsRoot.placement.margins.right
                spacing: popupsRoot.theme.space(2)

                Repeater {
                    model: popupsRoot.notifs.popupModel

                    // The delegate is a slot Item owning the lifetime timer;
                    // the visuals live in NotificationCard.
                    delegate: Item {
                        id: cardSlot

                        required property int index
                        required property string app
                        required property string appIcon
                        required property string summary
                        required property string body
                        required property string image
                        required property string glyph
                        required property int urgency
                        required property double expireTimeout
                        required property double timestamp
                        // double: the model key folds a ms-epoch session
                        // stamp into the server id, which overflows int.
                        required property double originalId

                        // The card sizes itself; the slot tracks it so the
                        // column fits whichever card is widest.
                        Layout.preferredWidth: card.implicitWidth
                        Layout.alignment: Qt.AlignRight
                        implicitHeight: card.implicitHeight

                        readonly property real lifetime: popupsRoot.notifs.durationFor(urgency, expireTimeout)
                        property real remainingLifetime: 1.0
                        // Hovering this toast on ANY screen holds it here too.
                        readonly property bool ticking: lifetime > 0 && !popupsRoot.hoverHeld(cardSlot.originalId)

                        Component.onDestruction: {
                            if (card.hovered)
                                popupsRoot.setHoverHold(cardSlot.originalId, false);
                        }

                        Timer {
                            interval: 50
                            repeat: true
                            running: cardSlot.ticking
                            onTriggered: {
                                if (cardSlot.lifetime <= 0)
                                    return;
                                cardSlot.remainingLifetime -= 50.0 / cardSlot.lifetime;
                                if (cardSlot.remainingLifetime <= 0) {
                                    cardSlot.remainingLifetime = 0;
                                    popupsRoot.notifs.expirePopup(cardSlot.index);
                                }
                            }
                        }

                        NotificationCard {
                            id: card
                            anchors.right: parent.right
                            onHoveredChanged: popupsRoot.setHoverHold(cardSlot.originalId, card.hovered)
                            theme: popupsRoot.theme
                            app: cardSlot.app
                            appIcon: cardSlot.appIcon
                            summary: cardSlot.summary
                            body: cardSlot.body
                            image: cardSlot.image
                            glyph: cardSlot.glyph
                            urgency: cardSlot.urgency
                            timestamp: cardSlot.timestamp
                            // A replayed history row has no live notification
                            // behind it, so it renders without buttons.
                            actions: {
                                const ref = popupsRoot.notifs.liveRefs[cardSlot.originalId];
                                return ref && ref.actions ? ref.actions : [];
                            }
                            progress: cardSlot.remainingLifetime
                            showCountdown: cardSlot.lifetime > 0

                            onCloseRequested: popupsRoot.notifs.dismissPopup(cardSlot.index)
                            onCardClicked: popupsRoot.notifs.invokePopupDefault(cardSlot.index)
                            onActionInvoked: action => {
                                action.invoke();
                                popupsRoot.notifs.dismissPopup(cardSlot.index);
                            }

                            opacity: 0
                            Component.onCompleted: opacity = 1
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: popupsRoot.theme.time(1)
                                    easing.type: popupsRoot.theme.easing
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
