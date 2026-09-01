import QtQuick
import Quickshell
import Quickshell.Io
import "DnsShieldModel.js" as Model

// DNS Shield service — owns everything the widget and panel read about the
// family DNS helper (see DnsShieldModel.js for the chain). ONE instance
// however many screens carry the widget (S2) — created at the bar root.
//
// Probe-on-open only, the family-sanctioned cadence (Dropbox, DevServices):
// startup presence check, panel open, right-click. No follower — the chain
// has no user-session event source (system units, not user units), and a
// system-bus monitor for two services that change a few times a month is not
// worth a resident process. The live block test inside the probe is the real
// health signal anyway.
//
// The probe is one bash child wrapped in `setpriv --pdeathsig TERM` like
// every long-running family child; it exits 3 on machines without the
// helper unit, which closes the gate for good (DevServices' pattern).
QtObject {
    id: root

    property bool probed: false
    property bool available: false
    property bool refreshing: false
    property string lastError: ""

    // The parsed probe snapshot, or null before the first answer.
    property var state: null

    readonly property bool healthy: state !== null && Model.chainHealthy(state)
    readonly property bool lanServing: state !== null && state.bindLan
    readonly property var rows: Model.rows(state)

    property string _probeOutput: ""
    property string _probeError: ""

    function refresh() {
        if (probed && !available)
            return;
        if (probeProcess.running)
            return;
        _probeOutput = "";
        _probeError = "";
        refreshing = true;
        probeProcess.running = true;
    }

    function openDashboard() {
        Quickshell.execDetached(["xdg-open", Model.DASHBOARD_URL]);
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // The one probe: unit presence gate, then every fact the model renders.
    // dig gets one second and one try — the panel opens instantly and a
    // hung client reads as "No answer", which is itself the diagnosis.
    readonly property Process probeProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", "systemctl cat ublockdns.service >/dev/null 2>&1 || exit 3; " + "echo client=$(systemctl is-active ublockdns 2>/dev/null); " + "echo dnsmasq=$(systemctl is-active dnsmasq 2>/dev/null); " + "b=$(ss -lnu 2>/dev/null); " + "case \"$b\" in *'127.0.0.1:53 '*) echo bind_client=yes;; *) echo bind_client=no;; esac; " + "case \"$b\" in *'127.0.0.2:53 '*) echo bind_fwd=yes;; *) echo bind_fwd=no;; esac; " + "iface=$(head -1 \"$HOME/.config/dns-helper/serve\" 2>/dev/null | tr -cd 'a-z0-9'); " + "cur=; [ -n \"$iface\" ] && cur=$(ip -4 addr show \"$iface\" 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | cut -d' ' -f2); " + "echo lan_ips=$cur; " + "bound=; [ -n \"$cur\" ] && case \"$b\" in *\"$cur:53 \"*) bound=$cur;; esac; " + "echo lan_bound=$bound; " + "dev=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*dev \\([^ ]*\\).*/\\1/p' | head -1); " + "echo laptop_dns=$(resolvectl status $dev 2>/dev/null | sed -n 's/.*Current DNS Server: //p' | head -1); " + "echo block_test=$(dig @127.0.0.1 youtube.com +short +time=1 +tries=1 2>/dev/null | head -1)"]
        stdout: StdioCollector {
            id: probeStdout
            waitForEnd: true
            onStreamFinished: root._probeOutput = text
        }
        stderr: StdioCollector {
            id: probeStderr
            waitForEnd: true
            onStreamFinished: root._probeError = text
        }
        onExited: exitCode => {
            root.refreshing = false;
            root.probed = true;
            const out = String(probeStdout.text || root._probeOutput || "");
            const err = String(probeStderr.text || root._probeError || "");
            if (exitCode === 0) {
                root.available = true;
                root.state = Model.parseProbe(out);
                root.lastError = "";
            } else if (exitCode === 3) {
                // Not the helper machine — inert for good, no width, no probe.
                root.available = false;
            } else {
                root.lastError = root.elideStatus(err || out || "Could not probe the DNS helper");
            }
        }
    }

    Component.onCompleted: refresh()
}
