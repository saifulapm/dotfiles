// Dekho's focus helpers, itself omakade's (qml/Main.qml:23–152), lifted into a
// library so the modal sheet can capture and restore the keyboard.
//
// Only `focusWithin` is used here — this hub has one sheet and no long focus
// chain to scroll — but the file is taken whole rather than trimmed, so a diff
// against the copy it came from still reads as a copy.
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
// dialog's search field, a screen's primary action.
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
