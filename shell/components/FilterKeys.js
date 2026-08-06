// The parts of type-to-filter key handling that were byte-identical across
// the six filterable surfaces (ui-audit 2026-08-06, A14; upstream shape:
// omarchy's Util.editsFilter, CREDITS.md). Only the shared COMPUTATIONS live
// here — when a key edits the query versus navigates stays at each call
// site, because those differences are invariants, not drift: Menu's
// empty-filter Backspace goes back a menu, FilePicker's goes up a directory,
// Emojis' and Clipboard's fall through unaccepted.

// The printable-append guard: exactly one visible character, no chords.
function printable(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier);
}

// Backspace's result: Ctrl erases the trailing word, plain the last char.
function erased(text, ctrl) {
    return ctrl ? text.replace(/\s+$/, "").replace(/\S+$/, "") : text.slice(0, -1);
}
