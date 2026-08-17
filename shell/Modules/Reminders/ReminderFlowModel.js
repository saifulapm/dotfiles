// Near-verbatim port of omarchy's plugins/reminders/ReminderFlowModel.js:
// the whole of their capture-flow validation. Minutes are a
// positive integer and nothing else — their CLI parses no richer time input,
// so neither does ours — and the argument list handed to the CLI carries the
// message only when one was typed, so an empty message falls through to the
// CLI's own "Your N minutes are up" default.
//
// Their `module.exports` tail was dropped and whitespace follows house
// 4-space qmlformat.

function validMinutes(value) {
    var minutes = String(value || "").trim();
    return /^[0-9]+$/.test(minutes) && Number(minutes) > 0 ? minutes : "";
}

function reminderArgs(minutes, message) {
    var valid = validMinutes(minutes);
    if (!valid)
        return [];

    var args = [valid];
    var text = String(message || "");
    if (text.length > 0)
        args.push(text);
    return args;
}
