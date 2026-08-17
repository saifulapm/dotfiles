.pragma library

// Audio panel math — ported near-verbatim from omarchy's audio plugin
// Model.js (direct copies). Pure JS: PipeWire nodes and MPRIS
// players come in from the QML, nothing here touches Qt.
//
// Deviations from the source: omarchy's parseSinkAvailability was dropped (it
// parses the output of their omarchy-audio-sink-availability helper, which we
// do not ship), and the two node-type tests take the node's type NAME as a
// second argument — quickshell 0.3 exposes PwNode.type as a numeric flags
// enum, so the QML resolves it with PwNodeType.toString() first.

function isPlaybackStream(node, typeName) {
    if (!node || !node.isStream)
        return false
    if (node.isSink === true)
        return true

    var mediaClass = String(typeName || node.type || "")
    return mediaClass.indexOf("Stream/Output/Audio") !== -1
        || mediaClass.indexOf("AudioOutStream") !== -1
        || mediaClass.indexOf("Output") !== -1
}

function isAudioSource(node, typeName) {
    if (!node)
        return false
    if (node.audio)
        return true

    var mediaClass = String(typeName || node.type || "")
    // Deviation: their bare "Source" test also matches a Video/Source, which
    // put this machine's FaceTime camera in the input list.
    if (mediaClass.indexOf("Video") !== -1)
        return false
    return mediaClass.indexOf("Audio/Source") !== -1
        || mediaClass.indexOf("AudioSource") !== -1
        || mediaClass.indexOf("Source") !== -1
}

function listSnapshot(list) {
    return list && list.slice ? list.slice() : []
}

// Playful mood-name for a given output volume; bands are wide enough that
// small tweaks don't rename the room you're in.
function outputVolumeName(volume, muted) {
    if (muted)
        return "Muted"
    var p = Math.round(volume * 100)
    if (p === 0)
        return "Silenced"
    if (p >= 100)
        return "Concert hall"
    if (p >= 85)
        return "Party mode"
    if (p >= 70)
        return "Cranked up"
    if (p >= 50)
        return "Steady groove"
    if (p >= 30)
        return "Easy listening"
    if (p >= 15)
        return "Murmur"
    return "Whisper"
}

function friendlyDeviceLabel(text) {
    var label = String(text || "").trim()
    label = label.replace(/^sof-soundwire\s+/i, "")
    label = label.replace(/^built-?in audio\s+/i, "")
    label = label.replace(/\s+Output$/i, "")
    label = label.replace(/\s+Input$/i, "")
    label = label.replace(/\bMicrophones\b/g, "Microphone")
    return label
}

// PwNode.properties is invalid until the node is bound by a tracker, so every
// read goes through this guard.
function nodeProps(node) {
    return node && node.ready && node.properties ? node.properties : {}
}

function nodeLabel(node) {
    if (!node)
        return "Unknown"
    var p = nodeProps(node)
    var nickname = friendlyDeviceLabel(node.nickname || p["node.nick"] || p["device.profile.description"] || "")
    if (nickname)
        return nickname
    return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "Unknown")
}

function isHeadphones(node) {
    if (!node)
        return false
    var p = nodeProps(node)
    var blob = String([node.name, node.description, node.nickname, p["device.icon-name"] || "", p["device.product.name"] || "", p["node.description"] || "", p["node.nick"] || ""].join(" ")).toLowerCase()
    return blob.indexOf("headphone") !== -1
        || blob.indexOf("headset") !== -1
        || blob.indexOf("earbud") !== -1
        || blob.indexOf("earphone") !== -1
        || blob.indexOf("airpod") !== -1
}

function sinkGlyph(node) {
    if (!node)
        return "󰓃"
    if (isHeadphones(node))
        return "󰋋"
    var p = nodeProps(node)
    var blob = String([node.name, node.description, node.nickname, p["device.icon-name"] || "", p["device.product.name"] || ""].join(" ")).toLowerCase()
    if (blob.indexOf("bluetooth") !== -1)
        return "󰂯"
    if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1)
        return "󰍹"
    return "󰓃"
}

function sourceGlyph(node) {
    if (!node)
        return "󰍬"
    var p = nodeProps(node)
    var blob = String([node.name, node.description, node.nickname, p["device.icon-name"] || ""].join(" ")).toLowerCase()
    if (blob.indexOf("headset") !== -1)
        return "󰋋"
    if (blob.indexOf("bluetooth") !== -1)
        return "󰂯"
    if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1)
        return "󰄀"
    return "󰍬"
}

function friendlyStreamLabel(label) {
    label = String(label || "").trim()
    if (!label)
        return ""

    var known = {
        "spotify": "Spotify"
    }
    var normalized = label.toLowerCase()
    return known[normalized] || label
}

function streamLabelKey(label) {
    return String(label || "").trim().toLowerCase()
}

function streamLabelIsGeneric(label) {
    return streamLabelKey(label) === "audio-src"
}

function rawStreamLabel(node) {
    if (!node)
        return ""
    var p = nodeProps(node)
    return p["application.name"] || node.description || p["media.name"] || p["node.name"] || node.name
}

function mprisPlayerLabel(player) {
    if (!player)
        return ""
    return friendlyStreamLabel(player.identity || player.desktopEntry || "")
}

function mprisPlayerIsProxy(player) {
    var dbusName = String(player && player.dbusName || "").toLowerCase()
    var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
    return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function streamRepresentsMprisPlayer(streamLabel, playerLabel) {
    var streamKey = streamLabelKey(friendlyStreamLabel(streamLabel))
    var playerKey = streamLabelKey(playerLabel)
    if (!streamKey || !playerKey)
        return false
    return streamKey === playerKey
        || streamKey.indexOf(playerKey) !== -1
        || playerKey.indexOf(streamKey) !== -1
}

function mprisLabelsFor(players, predicate) {
    var values = Array.isArray(players) ? players : []
    var playingCandidates = []
    var candidates = []
    var playingProxyCandidates = []
    var proxyCandidates = []

    for (var i = 0; i < values.length; i++) {
        var player = values[i]
        if (!player)
            continue
        if (!player.isPlaying && !player.canPlay)
            continue

        var playerLabel = mprisPlayerLabel(player)
        if (!playerLabel || !predicate(playerLabel))
            continue

        if (mprisPlayerIsProxy(player)) {
            if (player.isPlaying)
                playingProxyCandidates.push(playerLabel)
            proxyCandidates.push(playerLabel)
        } else {
            if (player.isPlaying)
                playingCandidates.push(playerLabel)
            candidates.push(playerLabel)
        }
    }

    if (playingCandidates.length === 1)
        return playingCandidates[0]
    if (playingCandidates.length === 0 && playingProxyCandidates.length === 1)
        return playingProxyCandidates[0]
    if (candidates.length === 1)
        return candidates[0]
    if (candidates.length === 0 && proxyCandidates.length === 1)
        return proxyCandidates[0]
    return ""
}

function matchingMprisStreamLabel(label, players) {
    if (streamLabelIsGeneric(label))
        return ""
    return mprisLabelsFor(players, function (playerLabel) {
        return streamRepresentsMprisPlayer(label, playerLabel)
    })
}

// Spotify exposes its PipeWire stream as "audio-src". For generic stream
// names, use the one MPRIS player not already represented by another audio
// stream (e.g. Chromium, or ALSA apps).
function unmatchedMprisStreamLabel(label, players, streams) {
    if (!streamLabelIsGeneric(label))
        return ""

    return mprisLabelsFor(players, function (playerLabel) {
        var values = Array.isArray(streams) ? streams : []
        for (var i = 0; i < values.length; i++) {
            var stream = values[i]
            var label2 = rawStreamLabel(stream)
            if (!streamLabelIsGeneric(label2) && streamRepresentsMprisPlayer(label2, playerLabel))
                return false
        }
        return true
    })
}

function streamLabel(node, players, streams) {
    if (!node)
        return "Stream"
    var label = rawStreamLabel(node)
    return friendlyStreamLabel(matchingMprisStreamLabel(label, players) || unmatchedMprisStreamLabel(label, players, streams) || label) || "Stream"
}

function streamRepresentsPlayer(node, player, players, streams) {
    if (!node || !player)
        return false
    var playerLabel = mprisPlayerLabel(player)
    if (!playerLabel)
        return false

    var label = rawStreamLabel(node)
    if (!streamLabelIsGeneric(label))
        return streamRepresentsMprisPlayer(label, playerLabel)
    return streamRepresentsMprisPlayer(streamLabel(node, players, streams), playerLabel)
}
