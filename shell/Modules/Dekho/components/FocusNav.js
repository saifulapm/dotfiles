// omakade's focus helpers (qml/Main.qml:23–152), lifted into a library so the
// module root and the modal sheet share one copy.
//
// THE MODULE DRIVES REAL QT FOCUS NOW. It used to keep its own cursor — an
// integer per screen, moved by a single key catcher — because a focused
// TextInput eats Left and Right for its own caret and those are how you walk a
// rail (doc §6). That is no longer a reason: the search line is a real
// TextField that hands Down straight back to the grid, everything else is a
// real Button, and the compositor gives an ordinary toplevel its focus without
// any of the layer-shell grab dance doc §12 deleted.
//
// omakade's fourth helper, `focusSpatial`, is deliberately NOT here. It exists
// there to give a GAMEPAD d-pad something to mean on a page of buttons, driven
// off `Controller.onFocusDirectionRequested`; nothing in this shell speaks to a
// gamepad, so it would have had no caller. Tab is what walks a screen here, as
// doc §13 already decided it should be, and the grid owns its own arrows.
.pragma library

function isWithin(item, container) {
    while (item) {
        if (item === container)
            return true;
        item = item.parent;
    }
    return false;
}

// The next (or previous) focusable thing inside `container`, wrapping within it
// rather than escaping into whatever is behind. `preferred` is the item a
// freshly opened container wants the focus on regardless of the chain — a
// dialog's Cancel button, a screen's primary action.
function focusWithin(window, container, forward, preferred, reveal) {
    if (!container)
        return;
    if (preferred && preferred.visible && preferred.enabled) {
        preferred.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        if (reveal)
            reveal(preferred);
        return;
    }
    const current = window ? window.activeFocusItem : null;
    const origin = isWithin(current, container) ? current : container;
    let candidate = origin.nextItemInFocusChain(forward);
    for (let attempts = 0; candidate && attempts < 300; ++attempts) {
        if (isWithin(candidate, container) && candidate.visible && candidate.enabled && candidate.activeFocusOnTab) {
            candidate.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
            if (reveal)
                reveal(candidate);
            return;
        }
        candidate = candidate.nextItemInFocusChain(forward);
    }
}

// Scroll just far enough that the newly focused item is inside the viewport.
// Tabbing off the bottom of a long page has to move the page, and Flickable
// will not do it by itself.
function revealInFlickable(flickable, item, margin) {
    if (!flickable || !item)
        return;
    const position = item.mapToItem(flickable, 0, 0);
    if (position.y < margin) {
        flickable.contentY = Math.max(flickable.originY, flickable.contentY + position.y - margin);
    } else if (position.y + item.height > flickable.height - margin) {
        flickable.contentY = Math.min(flickable.originY + Math.max(0, flickable.contentHeight - flickable.height), flickable.contentY + position.y + item.height - flickable.height + margin);
    }
}
