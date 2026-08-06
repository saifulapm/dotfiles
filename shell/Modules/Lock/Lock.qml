import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

// Session lock: ext-session-lock-v1 via WlSessionLock, PAM auth via our own
// pam.d/qshell-lock config (auth include system-auth) — no /etc writes.
//
// The state machine is omarchy's lock service (CREDITS.md): the requested /
// pending / secure split, the screen-stabilize queue, the failed-attempt
// counter, the fingerprint flow beside the password one, the idle blank timer
// with its suspend-gap guard, and the preview overlay. The face it drives is
// LockView.qml.
//
// Unlock happens ONLY through PAM success. forceUnlock() exists for the
// nested dev session and is IPC-reachable only when QSHELL_DEV=1.
Scope {
    id: lockRoot

    required property var theme

    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
    readonly property string pamDir: Quickshell.shellDir + "/Modules/Lock/pam.d"

    property bool lockRequested: false
    property bool pendingSessionLock: false
    property bool authenticatingPassword: false
    // Armed by pamMessage when a prompt wants an answer, consumed by
    // respondToPasswordPrompt: PamContext never clears responseRequired after
    // respond(), so gating on responseRequired alone wrote the password twice
    // per prompt (once per connected signal).
    property bool promptPending: false
    // error and completed(PamResult.Error) both arrive for a single PAM
    // error; count one user-visible failure per submitted attempt.
    property bool failureCounted: false
    property bool fingerprintAuthenticating: false
    property bool passwordPamConfigured: false
    property bool fingerprintConfigured: false
    property bool previewVisible: false
    property string enteredPassword: ""
    property string pendingPassword: ""
    property string failureMessage: ""
    property int failedAttempts: 0
    property string backgroundPath: ""
    property int backgroundVersion: 0
    property string lastEvent: "init"
    property string lastEventAt: ""

    // What shell.qml's `locked` guard and the LazyLoader self-unload watch.
    // A lock that has been asked for but whose surface has not mapped yet is
    // still a locked session.
    // All three, as omarchy does, and the OR is load-bearing: quickshell emits
    // WlSessionLock's lockStateChanged when the lock DROPS but not when it
    // engages (realizeLockTarget only emits on the unlock branch), so a binding
    // on `sessionLock.locked` alone reads a stale false for the whole session.
    readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
    readonly property bool secure: sessionLock.secure
    readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating
    // Whether we are the reason the monitors are off. omarchy fires their wake
    // helper on every pointer motion; a niri DPMS action per mouse move is a
    // process per frame, so the wake only runs when there is something to undo.
    property bool blanked: false

    function realScreenCount() {
        const screens = Quickshell.screens || [];
        let count = 0;
        for (let i = 0; i < screens.length; i++) {
            const screen = screens[i];
            if (screen && screen.name && screen.width > 0 && screen.height > 0)
                count += 1;
        }
        return count;
    }

    function hasRealScreen() {
        return realScreenCount() > 0;
    }

    // A blocking read, so a lock request arriving in the same tick the module
    // is created still knows whether there is a way back out. The module is
    // lazy-loaded at lock time, so an async load would not have resolved yet.
    function pamConfigured() {
        const ok = String(pamFile.text() || "").trim().length > 0;
        passwordPamConfigured = ok;
        return ok;
    }

    function queueSessionLock() {
        pendingSessionLock = true;
        if (!sessionLockStabilizeTimer.running)
            logEvent("lock-pending: screen-stabilizing");
        sessionLockStabilizeTimer.restart();
        if (!pendingSessionLockTimer.running)
            pendingSessionLockTimer.start();
    }

    function requestSessionLock() {
        if (!lockRequested || sessionLock.locked || sessionLock.secure) {
            // A withdrawn lock request must stand the retry timer down too,
            // or it keeps firing at 10 Hz for the rest of the session.
            if (!lockRequested) {
                pendingSessionLock = false;
                pendingSessionLockTimer.stop();
            }
            return;
        }
        if (sessionLockStabilizeTimer.running)
            return;
        if (!hasRealScreen()) {
            if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen")
                logEvent("lock-pending: no-real-screen");
            pendingSessionLock = true;
            if (!pendingSessionLockTimer.running)
                pendingSessionLockTimer.start();
            return;
        }
        pendingSessionLock = false;
        pendingSessionLockTimer.stop();
        sessionLock.locked = true;
    }

    function refreshBackground() {
        backgroundFile.reload();
        const next = String(backgroundFile.text() || "").trim();
        if (next !== backgroundPath) {
            backgroundPath = next;
            backgroundVersion += 1;
        }
    }

    function refreshFingerprintStatus() {
        if (!fingerprintCheckProc.running)
            fingerprintCheckProc.running = true;
    }

    // Kept in `status` rather than shouted at the journal: console.log is
    // suppressed at the default log level and console.warn would make every
    // ordinary lock look like a fault.
    function logEvent(event) {
        lastEvent = event;
        lastEventAt = new Date().toISOString();
    }

    function resetAuthenticationState() {
        enteredPassword = "";
        pendingPassword = "";
        promptPending = false;
        failureMessage = "";
        failedAttempts = 0;
        authenticatingPassword = false;
        fingerprintAuthenticating = false;
        fingerprintRetryTimer.stop();
        if (pam.active)
            pam.abort();
        if (fingerprintPam.active)
            fingerprintPam.abort();
    }

    function lock() {
        if (!pamConfigured()) {
            logEvent("lock-denied: missing-pam");
            console.warn("Lock: refusing to lock — pam.d/qshell-lock is missing");
            return false;
        }
        resetAuthenticationState();
        lockRequested = true;
        // Assume the monitors may already be off (the idle service's
        // screensaver stage runs before the lock stage), so the first key or
        // click on the lock screen is guaranteed to bring them back.
        blanked = true;
        armBlankTimer();
        logEvent("lock-requested");
        queueSessionLock();
        Qt.callLater(() => {
            lockRoot.refreshBackground();
            lockRoot.refreshFingerprintStatus();
        });
        return true;
    }

    function finishUnlock() {
        if (!locked && !lockRequested)
            return;
        lockRequested = false;
        pendingSessionLock = false;
        sessionLockStabilizeTimer.stop();
        pendingSessionLockTimer.stop();
        resetAuthenticationState();
        idleBlankTimer.stop();
        sessionLock.locked = false;
        logEvent("unlocked");
        runWake();
    }

    function forceUnlock() {
        finishUnlock();
    }

    function armBlankTimer() {
        idleBlankTimer.armedAt = Date.now();
        idleBlankTimer.restart();
    }

    function runWake() {
        if (blanked) {
            blanked = false;
            if (!wakeProcess.running)
                wakeProcess.running = true;
        }
        if (lockRequested)
            armBlankTimer();
    }

    function runBlank() {
        blanked = true;
        if (!blankProcess.running)
            blankProcess.running = true;
    }

    function submitPassword(value) {
        const password = String(value || "");
        if (!lockRequested || authenticatingPassword || password.length === 0)
            return;
        runWake();
        pendingPassword = password;
        failureMessage = "";
        promptPending = false;
        failureCounted = false;
        authenticatingPassword = true;
        if (!pam.start()) {
            handlePasswordFailure(PamResult.Error);
            return;
        }
    }

    function respondToPasswordPrompt() {
        if (!authenticatingPassword || !pam.active || !pam.responseRequired)
            return;
        if (!promptPending)
            return;
        promptPending = false;
        pam.respond(pendingPassword);
    }

    function handlePasswordFailure(result) {
        if (!lockRequested)
            return;
        if (failureCounted)
            return;
        failureCounted = true;
        authenticatingPassword = false;
        enteredPassword = "";
        pendingPassword = "";
        failedAttempts += 1;
        const label = result === PamResult.MaxTries ? "Too many attempts" : "Authentication failed";
        failureMessage = label + " (" + failedAttempts + ")";
        logEvent("auth-failed: " + failedAttempts);
        runWake();
    }

    function startFingerprint() {
        if (!lockRequested || !sessionLock.secure || !fingerprintConfigured)
            return;
        if (fingerprintPam.active || fingerprintAuthenticating)
            return;
        fingerprintAuthenticating = true;
        if (!fingerprintPam.start())
            fingerprintAuthenticating = false;
    }

    function handleFingerprintFinished(result) {
        fingerprintAuthenticating = false;
        if (!lockRequested)
            return;
        if (result === PamResult.Success)
            finishUnlock();
        else if (fingerprintConfigured)
            fingerprintRetryTimer.restart();
    }

    function showPreview() {
        refreshBackground();
        refreshFingerprintStatus();
        previewVisible = true;
    }

    function hidePreview() {
        previewVisible = false;
    }

    onAuthenticatingChanged: {
        if (!lockRequested)
            return;
        if (authenticating)
            idleBlankTimer.stop();
        else
            armBlankTimer();
    }

    Component.onCompleted: {
        pamConfigured();
        refreshBackground();
        refreshFingerprintStatus();
    }

    WlSessionLock {
        id: sessionLock

        locked: false

        onSecureStateChanged: {
            lockRoot.logEvent("secure=" + secure);
            if (secure) {
                lockRoot.pendingSessionLock = false;
                sessionLockStabilizeTimer.stop();
                pendingSessionLockTimer.stop();
                lockRoot.startFingerprint();
            }
        }

        onLockStateChanged: {
            lockRoot.logEvent("session-locked=" + locked);
            if (locked) {
                lockRoot.pendingSessionLock = false;
                sessionLockStabilizeTimer.stop();
                pendingSessionLockTimer.stop();
            }
            if (!locked && lockRoot.lockRequested) {
                lockRoot.lockRequested = false;
                lockRoot.pendingSessionLock = false;
                sessionLockStabilizeTimer.stop();
                pendingSessionLockTimer.stop();
                lockRoot.resetAuthenticationState();
                lockRoot.runWake();
            }
        }

        WlSessionLockSurface {
            id: surface
            color: lockRoot.theme.surface1

            LockView {
                anchors.fill: parent
                theme: lockRoot.theme
                backgroundPath: lockRoot.backgroundPath
                backgroundVersion: lockRoot.backgroundVersion
                fingerprintConfigured: lockRoot.fingerprintConfigured
                authenticatingPassword: lockRoot.authenticatingPassword
                failureMessage: lockRoot.failureMessage
                inputEnabled: lockRoot.lockRequested
                loadBackground: lockRoot.locked
                passwordText: lockRoot.enteredPassword
                onPasswordTextEdited: password => lockRoot.enteredPassword = password
                onSubmitPassword: password => lockRoot.submitPassword(password)
                onClearFailureRequested: lockRoot.failureMessage = ""
                onWakeRequested: lockRoot.runWake()
            }
        }
    }

    // Renders the lock screen without locking anything — how the design is
    // checked (and how a theme change is judged) without putting a password
    // prompt between the user and their session.
    PanelWindow {
        id: previewWindow

        visible: lockRoot.previewVisible
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        WlrLayershell.namespace: "qshell-lock-preview"
        WlrLayershell.layer: WlrLayer.Overlay
        // niri never hands the keyboard to a layer surface that asks for it in
        // its first commit — map with None, flip one tick later.
        WlrLayershell.keyboardFocus: lockRoot.previewVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        LockView {
            anchors.fill: parent
            theme: lockRoot.theme
            backgroundPath: lockRoot.backgroundPath
            backgroundVersion: lockRoot.backgroundVersion
            fingerprintConfigured: lockRoot.fingerprintConfigured
            authenticatingPassword: false
            failureMessage: ""
            inputEnabled: false
            loadBackground: lockRoot.previewVisible
            passwordText: ""
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: lockRoot.hidePreview()
        }

        Item {
            focus: true
            Keys.onEscapePressed: lockRoot.hidePreview()
        }
    }

    PamContext {
        id: pam
        config: "qshell-lock"
        configDirectory: "pam.d"

        // pamMessage is the ONE responder path: it fires exactly once per
        // prompt, while responseRequiredChanged fires only on transitions —
        // respond() never resets the flag, so a second prompt in the same
        // conversation would not re-fire it.
        onPamMessage: {
            if (pam.responseRequired) {
                lockRoot.promptPending = true;
                lockRoot.respondToPasswordPrompt();
            }
        }

        onCompleted: result => {
            lockRoot.authenticatingPassword = false;
            lockRoot.pendingPassword = "";
            if (!lockRoot.lockRequested)
                return;
            if (result === PamResult.Success)
                lockRoot.finishUnlock();
            else
                lockRoot.handlePasswordFailure(result);
        }

        onError: e => {
            console.warn("Lock: pam error:", e);
            lockRoot.handlePasswordFailure(PamResult.Error);
        }
    }

    // Second, independent flow: a fingerprint reader unlocks without the
    // password field ever being touched. Inert unless pam.d/qshell-lock-
    // fingerprint exists AND fprintd reports an enrolled finger.
    PamContext {
        id: fingerprintPam
        config: "qshell-lock-fingerprint"
        configDirectory: "pam.d"

        onCompleted: result => lockRoot.handleFingerprintFinished(result)

        onError: e => {
            lockRoot.fingerprintAuthenticating = false;
            if (lockRoot.lockRequested && lockRoot.fingerprintConfigured)
                fingerprintRetryTimer.restart();
        }
    }

    Timer {
        id: fingerprintRetryTimer
        interval: 250
        repeat: false
        onTriggered: lockRoot.startFingerprint()
    }

    // The wallpaper the lock screen blurs is the one on the desktop right now
    // — the same state file Modules/Background watches.
    FileView {
        id: backgroundFile
        path: Quickshell.env("HOME") + "/.local/state/qshell/background"
        blockLoading: true
        printErrors: false
    }

    // The lock refuses to arm without this file, so a broken checkout can
    // never strand the session behind a prompt nothing can answer.
    FileView {
        id: pamFile
        path: lockRoot.pamDir + "/qshell-lock"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: fingerprintCheckProc
        command: ["bash", "-c", "if [[ -f \"$1\" ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi", "bash", lockRoot.pamDir + "/qshell-lock-fingerprint"]
        stdout: StdioCollector {
            id: fingerprintCheckStdout
            waitForEnd: true
        }
        onExited: {
            lockRoot.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes";
            if (lockRoot.lockRequested && lockRoot.fingerprintConfigured)
                lockRoot.startFingerprint();
            else if (!lockRoot.fingerprintConfigured && fingerprintPam.active)
                fingerprintPam.abort();
        }
    }

    // omarchy blanks through their own brightness helpers; on niri the
    // compositor owns DPMS, and these are the same two actions the idle
    // service's screensaver stage uses.
    Process {
        id: wakeProcess
        command: ["niri", "msg", "action", "power-on-monitors"]
    }

    Process {
        id: blankProcess
        command: ["niri", "msg", "action", "power-off-monitors"]
    }

    Timer {
        id: idleBlankTimer
        interval: 5000
        repeat: false
        property double armedAt: 0
        onTriggered: {
            // A countdown frozen by suspend fires right after resume, which
            // would blank the freshly woken unlock screen under the user. Wall
            // clock time exposes the gap: take a fresh run-up instead.
            if (Date.now() - armedAt > interval + 2000) {
                lockRoot.armBlankTimer();
                return;
            }
            if (lockRoot.lockRequested && !lockRoot.authenticating)
                lockRoot.runBlank();
        }
    }

    // A lock asked for while outputs are still settling (a lid opening, a
    // monitor waking) must not map its surface against a screen list that is
    // about to change under it.
    Timer {
        id: sessionLockStabilizeTimer
        interval: 500
        repeat: false
        onTriggered: lockRoot.requestSessionLock()
    }

    Timer {
        id: pendingSessionLockTimer
        interval: 100
        repeat: true
        onTriggered: lockRoot.requestSessionLock()
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            lockRoot.requestSessionLock();
        }
    }
}
