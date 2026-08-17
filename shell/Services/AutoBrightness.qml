import QtQuick
import Quickshell
import Quickshell.Io

// Auto-brightness — the ambient-light half of what macOS does for free on
// this hardware, and the biggest single battery lever on the machine. The
// panel spans 3.69 W at 8 % to 8.41 W at 100 % (measured on battery,
// 2026-08-17, 13" MBP M2): a 4.7 W range that dwarfs every other knob here.
// Riding the room instead of parking at one number is worth more than every
// daemon-level tweak on this laptop put together.
//
// The source is the AOP ambient-light sensor the Asahi kernel exposes at
// /sys/bus/iio/devices/iio:device0/in_illuminance_input — plain lux, one
// line, world-readable (-rw-r--r-- root root), so nothing here needs a
// helper or a privilege.
//
// iio-sensor-proxy is DELIBERATELY not used, though it is the usual answer
// and what the desktop stacks expect. It is a second always-running daemon
// whose whole job is to poll this same file and republish it on D-Bus. On a
// feature whose entire purpose is to spend less power, adding a resident
// process to read a file this shell can read itself would give back part of
// what the feature saves. FileView reads it in-process for an open/read.
//
// DELIBERATE no-polling exception — the second in this shell, after
// WeatherService. An IIO sysfs attribute has no event source: it cannot be
// selected on, it emits no uevent, and the driver will not push. The only
// way to follow the room is to sample it. The rule is about IDLE cost
// (NetworkPanel says so), so the sampler is gated to the only case where a
// sample can change something a human sees: the timer does not run while the
// monitors are powered off or the session is locked. A laptop sitting with a
// blanked screen — the case the rule exists to protect — polls nothing.
//
// Two behaviours keep it from being the annoying kind of auto-brightness:
//
//  * Hysteresis + smoothing. Readings run through an EMA and a move is only
//    applied once the target differs from the panel by `hysteresis` points.
//    A hand passing over the sensor does not move the backlight.
//  * Manual override wins. If the backlight leaves where we put it, a human
//    used the brightness keys, and this backs off for `overrideMinutes`
//    instead of fighting them. Auto resumes on its own, so there is no state
//    to remember and nothing to un-stick.
//
// FileView specifics, verified against quickshell 1.27 rather than assumed:
// a FileView with a path loads on its own and text() returns the contents,
// and reload() re-reads. reload() is NOT relied upon to publish
// synchronously — every value this service acts on is taken in an onLoaded
// handler, and override detection needs the same mismatch twice running, so
// a stale read can at worst delay a decision by one tick, never invert one.
QtObject {
    id: root

    // Injected by shell.qml: the config root, and the idle service whose
    // monitorsPoweredOff is half the poll gate.
    property var shellRoot: null
    property var idle: null

    readonly property string alsPath: "/sys/bus/iio/devices/iio:device0/in_illuminance_input"
    readonly property string backlightDir: "/sys/class/backlight/apple-panel-bl"

    readonly property var config: shellRoot && shellRoot.config && shellRoot.config.autoBrightness && typeof shellRoot.config.autoBrightness === "object" ? shellRoot.config.autoBrightness : ({})

    function setting(name, fallback) {
        const value = config ? config[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    // shell.json says whether the feature exists for this fleet; the flag
    // file says whether the human wants it right now. Same split, and the
    // same "presence IS the state" flag file, as Idle's stay-awake — so
    // `touch`/`rm` from a terminal toggles it exactly like the panel row.
    // Presence means OFF, because the configured default is on: a machine
    // that has never been toggled should behave as configured.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell"
    readonly property string disabledPath: stateDir + "/auto-brightness-off"
    property bool userDisabled: false

    readonly property bool configEnabled: setting("enabled", false) === true
    readonly property bool enabled: configEnabled && !userDisabled

    // Flip in memory first so the panel row reacts on the click; the flag
    // file is the durable copy and its watcher re-delivers the same value.
    function setEnabled(value) {
        const on = !!value;
        userDisabled = !on;
        disabledWriter.command = ["bash", "-c", on ? "rm -f \"$1\"" : "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\"", "qshell-auto-brightness", disabledPath];
        disabledWriter.running = true;
        return on;
    }

    readonly property Process disabledWriter: Process {}

    readonly property FileView disabledFlag: FileView {
        path: root.disabledPath
        watchChanges: true
        printErrors: false
        onLoaded: root.userDisabled = true
        onLoadFailed: root.userDisabled = false
        onFileChanged: reload()
        // Without an explicit read the view stays unloaded and neither
        // signal above ever fires (Idle.qml hit the same thing).
        Component.onCompleted: reload()
    }

    // A FileView cannot arm its watch when the state dir is missing, and
    // nothing re-arms it later. Same defence as Idle and Theme: each service
    // defends itself, because service construction order is undefined.
    readonly property Process stateDirProc: Process {
        command: ["mkdir", "-p", root.stateDir]
        onExited: root.disabledFlag.reload()
        Component.onCompleted: running = true
    }
    readonly property int intervalMs: Math.max(1000, Math.round(setting("intervalSeconds", 5) * 1000))
    readonly property int minPercent: Math.max(1, setting("minPercent", 8))
    readonly property int maxPercent: Math.min(100, setting("maxPercent", 90))
    readonly property int hysteresis: Math.max(1, setting("hysteresis", 4))
    readonly property int overrideMs: Math.max(0, Math.round(setting("overrideMinutes", 10) * 60000))
    readonly property real smoothing: Math.min(1, Math.max(0.05, setting("smoothing", 0.35)))

    // lux -> percent, piecewise linear between the knees. Roughly
    // logarithmic in lux, which is how the eye reads brightness: the step
    // from a dim room to a lit one matters far more than the top of the
    // daylight range, where the panel is saturated anyway. Indoor evening
    // measures ~70 lux here; overcast daylight through a window is ~1000.
    readonly property var defaultCurve: [[0, 8], [10, 13], [30, 18], [70, 25], [150, 34], [400, 48], [1000, 62], [3000, 78], [10000, 100]]
    readonly property var curve: {
        const c = setting("curve", null);
        return Array.isArray(c) && c.length >= 2 ? c : defaultCurve;
    }

    // Smoothed lux; -1 until the first read, which is what lets the first
    // sample after a wake make a large move instead of easing from a fake 0.
    property real smoothedLux: -1

    // What this service last asked for. -1 (nothing applied yet) must never
    // read as a mismatch, or the first sample would declare an override.
    property int lastAppliedPercent: -1
    property double overrideUntilMs: 0

    // Last brightness percentage seen by the brightness FileView's onLoaded.
    // -1 until the first successful read parks the service rather than
    // guessing at a panel it cannot measure.
    property int measuredPercent: -1
    property int maxRaw: -1

    // Override needs the same mismatch on two consecutive samples. One
    // sample is not enough: our own apply lands asynchronously, so the tick
    // straight after an apply can still be reading the pre-apply value.
    property int mismatchStreak: 0

    // Where the panel sat when we issued the current apply, and how many
    // times we have re-issued it. Together these separate the two ways a
    // mismatch can happen — see onLuxRead.
    property int preApplyPercent: -1
    property int retryCount: 0
    readonly property int maxRetries: 2

    // Whether this machine HAS an ambient-light sensor. The MacBook does;
    // the Mac mini and the NUC do not, and on them the FileView fails to
    // load and the whole service parks itself. This is the "laptop only"
    // gate, expressed as the capability it actually needs rather than as a
    // hostname test — a machine list would have to be edited every time the
    // fleet changes, and would still be wrong about a machine whose sensor
    // the kernel stopped exposing.
    property bool sensorPresent: false
    readonly property bool available: sensorPresent && maxRaw > 0

    readonly property bool screenVisible: !(idle && idle.monitorsPoweredOff) && !(shellRoot && shellRoot.locked)
    readonly property bool active: enabled && available && screenVisible

    function clamp(value, lo, hi) {
        return Math.min(hi, Math.max(lo, value));
    }

    // Piecewise-linear interpolation across the knees, clamped to the
    // configured working range at both ends.
    function percentForLux(lux) {
        const points = curve;
        const last = points.length - 1;
        let pct;
        if (lux <= points[0][0])
            pct = points[0][1];
        else if (lux >= points[last][0])
            pct = points[last][1];
        else {
            pct = points[last][1];
            for (let i = 0; i < last; i++) {
                const x0 = points[i][0], y0 = points[i][1];
                const x1 = points[i + 1][0], y1 = points[i + 1][1];
                if (lux >= x0 && lux <= x1) {
                    const span = x1 - x0;
                    pct = span <= 0 ? y1 : y0 + (y1 - y0) * ((lux - x0) / span);
                    break;
                }
            }
        }
        return Math.round(clamp(pct, minPercent, maxPercent));
    }

    function sample() {
        if (!active)
            return;
        // Both files, every tick: the backlight moves under us whenever the
        // brightness keys are pressed, and sysfs never says so.
        brightnessFile.reload();
        alsFile.reload();
    }

    // Called from the brightness FileView's onLoaded — the only place the
    // panel's real percentage enters this object.
    function onBrightnessRead(raw) {
        if (!isFinite(raw) || maxRaw <= 0)
            return;
        measuredPercent = Math.round((raw / maxRaw) * 100);
    }

    // Called from the ALS FileView's onLoaded. This is the decision point;
    // it runs after the brightness read of the same tick in the common case,
    // and tolerates the reverse by requiring a repeated mismatch.
    function onLuxRead(lux) {
        if (!isFinite(lux) || lux < 0 || measuredPercent < 0)
            return;

        smoothedLux = smoothedLux < 0 ? lux : smoothedLux + smoothing * (lux - smoothedLux);

        // The panel is not where we put it. That has two very different
        // causes and they must not be conflated:
        //
        //  * The apply never landed. bin/brightness-display takes a
        //    non-blocking flock and `exit 0`s when another brightness move
        //    holds it, so an ambient nudge issued while the brightness keys
        //    are repeating is dropped silently. The panel is then still on
        //    exactly the value it had when we issued the apply.
        //  * A human used the brightness keys. The panel is then on some
        //    new value that is neither our target nor where it started.
        //
        // Treating the first as an override was the original bug here: one
        // dropped write would switch auto-brightness off for the whole
        // override window, which reads as "it just stops working sometimes".
        // A dropped write is re-issued instead, and only a genuinely new
        // value counts as a human.
        if (lastAppliedPercent >= 0 && Math.abs(measuredPercent - lastAppliedPercent) > 1) {
            if (measuredPercent === preApplyPercent && retryCount < maxRetries) {
                retryCount++;
                apply(lastAppliedPercent, true);
                return;
            }
            mismatchStreak++;
            if (mismatchStreak >= 2) {
                overrideUntilMs = Date.now() + overrideMs;
                lastAppliedPercent = measuredPercent;
                mismatchStreak = 0;
                retryCount = 0;
            }
            return;
        }
        mismatchStreak = 0;
        retryCount = 0;

        if (Date.now() < overrideUntilMs)
            return;

        const target = percentForLux(smoothedLux);
        if (Math.abs(target - measuredPercent) < hysteresis)
            return;

        apply(target);
    }

    // `isRetry` re-issues a write we believe was dropped, so it must not
    // reset the retry counter or move the pre-apply baseline — otherwise a
    // panel that genuinely refuses to move would be retried forever.
    function apply(percent, isRetry) {
        lastAppliedPercent = percent;
        mismatchStreak = 0;
        if (!isRetry) {
            preApplyPercent = measuredPercent;
            retryCount = 0;
        }
        // bin/brightness-display, not brightnessctl directly: it owns the
        // flock that keeps concurrent brightness moves from racing, and
        // --no-osd is what stops an ambient nudge throwing a popup over
        // whatever is on screen. Every other brightness path here goes
        // through it too.
        Quickshell.execDetached(["brightness-display", "--no-osd", percent + "%"]);
    }

    // Re-baseline whenever the screen comes back: the room may have changed
    // while it was off, and the first sample after a wake should be free to
    // make a large move rather than easing there through the EMA.
    onActiveChanged: {
        if (active) {
            smoothedLux = -1;
            lastAppliedPercent = -1;
            mismatchStreak = 0;
            sample();
        }
    }

    readonly property FileView alsFile: FileView {
        path: root.alsPath
        onLoaded: {
            root.sensorPresent = true;
            root.onLuxRead(parseFloat(text()));
        }
        // The machines without an ambient-light sensor land here once, at
        // startup, and never arm the timer. Nothing else needs to know which
        // machine this is.
        onLoadFailed: root.sensorPresent = false
    }

    readonly property FileView brightnessFile: FileView {
        path: root.backlightDir + "/brightness"
        onLoaded: root.onBrightnessRead(parseInt(text(), 10))
    }

    // Never changes for a given panel, so it is read once and never reloaded.
    readonly property FileView maxBrightnessFile: FileView {
        path: root.backlightDir + "/max_brightness"
        onLoaded: {
            const value = parseInt(text(), 10);
            if (isFinite(value) && value > 0)
                root.maxRaw = value;
        }
    }

    readonly property Timer sampler: Timer {
        interval: root.intervalMs
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }
}
