pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "lib/motion.mjs" as M

// Shell-wide state that `qs ipc call shell status` reports.
Singleton {
    // Names of the surfaces that have loaded; each appends itself when made, in the warm-up after the first frame or on an earlier open.
    property list<string> loaded: []
    property list<QtObject> ticks: []
    // When the running recording started, in ms since the epoch; 0 while nothing records.
    property real recordingSince: 0
    // How many times slower surfaces move, read once at start; only bin/dots-dev sets it.
    readonly property real slowdown: M.slowdownOf(Quickshell.env("DOTS_MOTION_SLOWDOWN"))

    // A function, not a binding: a binding over ticks would miss a Tick starting or stopping.
    function timers(): int {
        return ticks.filter(t => t.running).length;
    }

    function addTick(tick) {
        ticks.push(tick);
    }

    function removeTick(tick) {
        ticks = ticks.filter(t => t !== tick);
    }

    // Every Ipc handler, so the socket can answer what qs ipc would: the first enabled handler of a target, and only the functions it declares.
    property var ipcs: []

    function addIpc(handler) {
        ipcs.push(handler);
    }

    function removeIpc(handler) {
        ipcs = ipcs.filter(h => h !== handler);
    }

    // A bare handler's own functions, such as targetChanged, which qs ipc never exposes and neither may the socket.
    IpcHandler {
        id: bare
        enabled: false
    }
    readonly property var builtins: functionNames(bare)

    function functionNames(object) {
        const names = [];
        for (const key in object)
            if (typeof object[key] === "function")
                names.push(key);
        return names;
    }

    // {ran: true, output} once the function ran; {ran: false} for an unknown target or function or the wrong argument count, so dots-call asks qs ipc and nothing runs twice.
    function callIpc(target, name, args) {
        const handler = ipcs.find(h => h.enabled && h.target === target);
        if (!handler || builtins.includes(name) || /Changed$/.test(name) || !functionNames(handler).includes(name) || handler[name].length !== args.length)
            return { ran: false };
        try {
            const out = handler[name](...args);
            return { ran: true, output: out === undefined || out === null ? "" : String(out) };
        } catch (e) {
            console.warn("ipc " + target + " " + name + " failed: " + e);
            return { ran: true, output: "" };
        }
    }
}
