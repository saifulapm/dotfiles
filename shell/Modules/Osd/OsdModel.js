// Icon table and payload model for the on-screen display. Near-verbatim port
// of omarchy's shell/plugins/osd/OsdModel.js.
//
// Kept free of QML types so it can be exercised under node.
//
// Glyph substitutions: their four speaker icons are FontAwesome-range
// (U+EEE8 mute, U+F026 low, U+F027 medium, U+F028 high) and that range does
// not render under our Symbols Nerd Font fallback — only Material Design
// (U+F0001+) does. Ours are the MD speaker ladder 󰖁 󰕿 󰖀 󰕾, the same four the
// bar's audio widget draws, in the same four slots. Every other glyph in the
// table is already MD and is upstream's unchanged.

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value))
}

// The widest glyph `iconFor` can return. The progress OSD sizes its icon
// column to it so the bar keeps its place as the icon changes.
var widestIcon = "󰕾"

function iconFor(name, percent) {
    var n = String(name || "").toLowerCase()
    if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute")
        return "󰖁"
    if (n === "volume-low")
        return "󰕿"
    if (n === "volume-medium")
        return "󰖀"
    if (n === "volume-high" || n === "volume")
        return "󰕾"
    if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off")
        return "󰍭"
    if (n === "microphone" || n === "mic")
        return "󰍬"
    if (n === "keyboard")
        return "󰌌"
    if (n === "brightness" || n === "display")
        return "󰍹"
    if (n === "touchpad")
        return "󰟸"
    if (n === "touch" || n === "touchscreen")
        return "󰝁"
    if (n === "reboot" || n === "restart")
        return "󰜉"
    if (n === "shutdown" || n === "power" || n === "poweroff")
        return "󰐥"
    if (n === "logout" || n === "sign-out" || n === "leave")
        return "󰍃"
    if (n === "media" || n === "player")
        return "󰝚"
    if (n === "media-source" || n === "player-source")
        return "󰝚"
    if (n === "media-play" || n === "player-play")
        return "󰐊"
    if (n === "media-pause" || n === "player-pause")
        return "󰏤"
    if (n === "media-next" || n === "player-next")
        return "󰒭"
    if (n === "media-previous" || n === "player-previous")
        return "󰒮"
    // Anything else is taken as a literal glyph, so a caller can hand the OSD
    // a icon we have no name for (omarchy's downloader passes 󰇚 this way).
    if (n.length > 0)
        return name
    if (percent <= 0)
        return "󰖁"
    if (percent <= 33)
        return "󰕿"
    if (percent <= 66)
        return "󰖀"
    return "󰕾"
}

// Everything one `show` needs, resolved from the string-shaped payload the
// IPC surface carries. A value with no message is a progress OSD; a message
// suppresses the bar and takes its place.
function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var maxValue = Math.max(1, parseInt(rawMax || "100", 10))
    var parsedValue = parseInt(rawValue || "0", 10)
    var hasProgress = rawValue !== "" && !isNaN(parsedValue) && rawMessage === ""
    var value = hasProgress ? clamp(parsedValue, 0, maxValue) : 0
    var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
    var parsedDuration = parseInt(rawDuration || "1200", 10)

    return {
        iconKey: String(iconName || "").toLowerCase(),
        maxValue: maxValue,
        hasProgress: hasProgress,
        value: value,
        message: String(rawMessage || (hasProgress ? (rawProgressText || percent + "%") : "")),
        icon: iconFor(iconName, percent),
        duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration)
    }
}

if (typeof module !== "undefined") {
    module.exports = {
        widestIcon: widestIcon,
        iconFor: iconFor,
        stateForShow: stateForShow
    }
}
