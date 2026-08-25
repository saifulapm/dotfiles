import QtQuick
import Quickshell
import Quickshell.Io

// Prayer times service — the aladhan.com calendar for one month, cached on
// disk, walked by a minute clock. ONE instance however many screens carry
// the widget (S2); created at the bar root.
//
// Network cost: at most one HTTP call per month per location (the calendar
// endpoint returns every day at once); the disk cache under
// ~/.cache/qshell/ means shell restarts — frequent in development — refetch
// nothing. Everything else is minute-tick arithmetic on the cached table.
//
// Defaults are Dhaka with the University of Islamic Sciences Karachi method
// (method=1), the convention the Islamic Foundation Bangladesh follows; the
// widget's inline settings in shell.json override all of it:
//   { "id": "prayer", "latitude": 23.8, "longitude": 90.4, "method": 1,
//     "notify": true }
QtObject {
    id: root

    property var settings: null

    readonly property real latitude: settings && isFinite(Number(settings.latitude)) ? Number(settings.latitude) : 23.8103
    readonly property real longitude: settings && isFinite(Number(settings.longitude)) ? Number(settings.longitude) : 90.4125
    readonly property int method: settings && isFinite(Number(settings.method)) ? Number(settings.method) : 1
    readonly property bool notifyEnabled: !settings || settings.notify !== false

    // The month table: { "DD-MM-YYYY": { timings: {...}, hijri: "..." } }.
    property var days: ({})
    property bool probed: false
    property string lastError: ""

    // Minute clock. Every derived property below hangs off nowMinute, so
    // the whole widget recomputes exactly once a minute and never polls.
    readonly property var clock: SystemClock {
        precision: SystemClock.Minutes
    }
    readonly property var nowDate: clock.date
    readonly property int nowMinute: nowDate.getHours() * 60 + nowDate.getMinutes()

    // Notified prayers, keyed "date|name" — the minute tick fires the
    // notification when a prayer's minute arrives, once.
    property string lastNotifiedKey: ""

    readonly property var order: ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    // Sunrise is a boundary, not a prayer — listed in the panel, never
    // notified, never the bar's "next".
    readonly property var prayers: ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    function dateKey(d) {
        const pad = n => (n < 10 ? "0" : "") + n;
        return pad(d.getDate()) + "-" + pad(d.getMonth() + 1) + "-" + d.getFullYear();
    }

    function minutesOf(hhmm) {
        const m = String(hhmm || "").match(/^(\d{1,2}):(\d{2})/);
        return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
    }

    function fmt(hhmm) {
        const m = String(hhmm || "").match(/^(\d{1,2}):(\d{2})/);
        return m ? m[0] : "";
    }

    readonly property var today: days[dateKey(nowDate)] || null
    readonly property var tomorrow: {
        const d = new Date(nowDate.getTime() + 86400000);
        return days[dateKey(d)] || null;
    }
    readonly property string hijriToday: today ? String(today.hijri || "") : ""

    // The next PRAYER from now — after Isha it is tomorrow's Fajr.
    readonly property var next: {
        if (!today)
            return null;
        for (const name of prayers) {
            const t = minutesOf(today.timings[name]);
            if (t > nowMinute)
                return {
                    name: name,
                    time: fmt(today.timings[name]),
                    minutes: t - nowMinute,
                    tomorrow: false
                };
        }
        if (tomorrow) {
            const t = minutesOf(tomorrow.timings["Fajr"]);
            return {
                name: "Fajr",
                time: fmt(tomorrow.timings["Fajr"]),
                minutes: (1440 - nowMinute) + t,
                tomorrow: true
            };
        }
        return null;
    }

    // "Asr 15:28" on the bar; the countdown lives in tooltip and panel.
    readonly property string barText: next ? next.name + " " + next.time : ""
    readonly property bool imminent: next !== null && next.minutes <= 20

    function countdownText(mins) {
        if (mins >= 60)
            return "in " + Math.floor(mins / 60) + "h " + (mins % 60) + "m";
        return "in " + mins + "m";
    }

    readonly property string tooltip: {
        if (!probed)
            return "Prayer times";
        if (!today)
            return "Prayer times — " + (lastError || "no data yet");
        const lines = [];
        if (next)
            lines.push("Next: " + next.name + " " + next.time + " (" + countdownText(next.minutes) + ")");
        for (const name of order)
            lines.push(name + "  " + fmt(today.timings[name]));
        if (hijriToday)
            lines.push(hijriToday);
        return lines.join("\n");
    }

    // Fire the notification on the minute a prayer arrives.
    onNowMinuteChanged: {
        if (!notifyEnabled || !today)
            return;
        for (const name of prayers) {
            if (minutesOf(today.timings[name]) !== nowMinute)
                continue;
            const key = dateKey(nowDate) + "|" + name;
            if (key === lastNotifiedKey)
                return;
            lastNotifiedKey = key;
            Quickshell.execDetached(["notify-send", "-a", "qshell", "🕌 " + name, "It is " + fmt(today.timings[name])]);
            return;
        }
    }

    // A new day (or month) may need the next month's table.
    readonly property string nowDateKey: dateKey(nowDate)
    onNowDateKeyChanged: ensureData()

    function ensureData() {
        if (!days[dateKey(nowDate)] || !tomorrow)
            refresh();
    }

    function refresh() {
        if (fetchProc.running)
            return;
        // Cache-or-fetch in one process: this month and next month's first
        // two days (the after-Isha countdown crosses midnight, and month
        // boundaries need the neighbour file). Each month is one file; the
        // tmp+mv keeps a killed curl from leaving a half JSON behind.
        fetchProc.command = ["bash", "-c", `
            set -uo pipefail
            cache_dir="\${XDG_CACHE_HOME:-$HOME/.cache}/qshell/prayer"
            mkdir -p "$cache_dir"
            get_month() {
                local y="$1" m="$2" f="$cache_dir/$1-$2.json"
                if [[ ! -s $f ]]; then
                    # -L: the calendar endpoint 302s to /calendar/YYYY/M.
                    # The jq gate keeps an error page out of the month cache
                    # — a bad cache file would wedge the widget for a month.
                    curl -fsSL --max-time 20 "https://api.aladhan.com/v1/calendar?latitude=${root.latitude}&longitude=${root.longitude}&method=${root.method}&month=$m&year=$y" -o "$f.tmp" \
                        && jq -e '.data | length > 0' "$f.tmp" >/dev/null 2>&1 \
                        && mv "$f.tmp" "$f" || rm -f "$f.tmp"
                fi
                [[ -s $f ]] && cat "$f"
            }
            y=$(date +%Y); m=$(date +%-m)
            ny=$y; nm=$((m + 1)); ((nm > 12)) && { nm=1; ny=$((y + 1)); }
            printf '['
            get_month "$y" "$m" || printf 'null'
            printf ','
            get_month "$ny" "$nm" || printf 'null'
            printf ']'
        `];
        fetchProc.running = true;
    }

    readonly property Process fetchProc: Process {
        stdout: StdioCollector {
            id: fetchOut
            waitForEnd: true
            onStreamFinished: root.applyFetch(String(text || ""))
        }
    }

    function applyFetch(raw) {
        probed = true;
        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch (e) {
            lastError = "prayer times fetch failed";
            return;
        }
        const table = {};
        for (const month of parsed) {
            if (!month || !Array.isArray(month.data))
                continue;
            for (const day of month.data) {
                const key = day && day.date && day.date.gregorian ? day.date.gregorian.date : "";
                if (!key)
                    continue;
                const h = day.date.hijri;
                table[key] = {
                    timings: day.timings || {},
                    hijri: h ? h.day + " " + (h.month ? h.month.en : "") + " " + h.year + " AH" : ""
                };
            }
        }
        if (Object.keys(table).length === 0) {
            lastError = "prayer times fetch failed";
            return;
        }
        days = table;
        lastError = "";
    }

    Component.onCompleted: refresh()
}
