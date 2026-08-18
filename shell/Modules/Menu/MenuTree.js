// The command menu's action tree — this file IS the menu. Edit it and the
// running shell picks the change up on the next reload.
//
// Shape mirrors omarchy's omarchy-menu.jsonc: ids are keys, a
// dotted id declares its parent ("capture.region" lives under "capture"), and
// the kind is inferred — `action` or `call` makes a row, `target` makes a
// redirect, anything else is a submenu. Declaration order is display order.
//
// Fields:
//   icon         Nerd Font glyph. MATERIAL DESIGN RANGE ONLY (U+F0001+) —
//                the FontAwesome range does not render under our font fallback.
//   label        row text
//   title        header text while the submenu is open (defaults to label)
//   aliases      extra search terms, and routes for `qs ipc call menu open <x>`
//   description  searched by whole word; shown as the row detail while filtering
//   action       shell command, run detached through `bash -lc`
//   call         handled inside the shell instead (see Menu.qml runCall)
//   target       id of another menu to open (a link row)
//   provider     submenu whose rows are produced at runtime, not declared here
//                (see Menu.qml providers, and "apps")
//   when         shell test; the row is hidden when it fails
//   checked      shell test; appends ✓ when it succeeds
//   state        in-shell boolean name that does the same (see Menu.qml stateValue)

var TREE = {
    // ------------------------------------------------------------------ root
    // Rows come from DesktopEntries at open time (Menu.qml mergeAppRows), as
    // real children of this id — so an app is searched, ranked and escaped
    // exactly like a menu row instead of handing off to the launcher overlay.
    "apps": {
        "icon": "󰀻",
        "label": "Apps",
        "aliases": ["app", "applications", "launcher", "run"],
        "description": "Launch an installed application",
        "provider": "apps"
    },
    // Omarchy's agent launcher (their SUPER+SHIFT+CTRL+A, our Agent row and
    // Setup > Coding Agent radio) was ported and then REMOVED 2026-08-13: an
    // agent launched through bin/app-run lands in a transient systemd unit,
    // whose WorkingDirectory is $HOME whatever the launcher cd'd to, so every
    // session opened on the home directory instead of a project. Agents get
    // started from a terminal that is already in the right repo. The bar's AI
    // usage panel (SUPER+SHIFT+CTRL+A here) is unrelated and stays.
    "theme": {
        "icon": "󰸌",
        "label": "Theme",
        "aliases": ["themes", "style", "colors", "colours", "appearance"],
        "description": "Switch the desktop theme",
        "call": "themes"
    },
    // Omarchy's style.background, one row further out: theirs is a single
    // leaf that opens the picker, ours also carries their bg-next cycle.
    "background": {
        "icon": "󰸉",
        "label": "Background",
        "aliases": ["wallpaper", "wallpapers", "backgrounds", "image"],
        "description": "Change the desktop wallpaper"
    },
    "capture": {
        "icon": "󰄀",
        "label": "Capture",
        "aliases": ["screenshot", "screenshots", "shot", "grab", "screen", "screenrecord", "screen-record", "screenrecording", "record"]
    },
    // Omarchy files this under their Trigger submenu, next to Capture — our
    // tree hoisted Capture to the root, so Emoji sits beside it.
    "emoji": {
        "icon": "󰇵",
        "label": "Emoji",
        "aliases": ["emojis", "emoticon", "smiley", "symbols"],
        "description": "Search an emoji and copy it to the clipboard",
        "call": "emojis"
    },
    // Omarchy's menu has no row for the clipboard picker at all — theirs is
    // keybind-only (SUPER+CTRL+V), and their only clipboard row is a Share
    // action. Ours sits beside Emoji, the other copy-something-out picker.
    "clipboard": {
        "icon": "󰅌",
        "label": "Clipboard",
        "aliases": ["clip", "history", "paste", "copy"],
        "description": "Pick something copied earlier and copy it again",
        "call": "clipboard"
    },
    // Omarchy files this under their Trigger submenu, with the same three
    // rows; ours sits at the root next to the other pickers.
    // omarchy files cliamp under Apps and launches it with one bind; ours gets
    // a submenu instead, because the player is a singleton with a running
    // state worth acting on from here (stop it, queue a track into it) rather
    // than only something to open. Sits with the other pickers.
    "music": {
        "icon": "󰝚",
        "label": "Music",
        "aliases": ["music", "radio", "stream", "listen", "song", "player", "station", "stations", "somafm", "youtube", "spotify", "podcast", "cliamp"],
        "description": "Radio, YouTube, podcasts — anything cliamp plays"
    },
    "reminder": {
        "icon": "󰢌",
        "label": "Reminder",
        "aliases": ["reminders", "remind", "timer", "alarm"],
        "description": "Set a reminder that notifies you later"
    },
    "toggle": {
        "icon": "󰔎",
        "label": "Toggle",
        "aliases": ["toggles", "switch"]
    },
    "setup": {
        "icon": "󰒓",
        "label": "Setup",
        "aliases": ["settings", "config", "configure", "preferences"]
    },
    "update": {
        "icon": "󰚰",
        "label": "Update",
        "aliases": ["upgrade", "packages", "dnf"],
        "description": "Install pending system packages",
        "when": "command -v foot",
        "action": "foot-run --app-id=qshell-float -e bash -lc 'sudo dnf upgrade --refresh; rm -f ~/.local/state/qshell/updates; read -r -p \"done — press enter to close\"'"
    },
    "system": {
        "icon": "󰐥",
        "label": "System",
        "aliases": ["power", "power-menu", "session"]
    },

    // --------------------------------------------------------------- capture
    "capture.region": {
        "icon": "󰩭",
        "label": "Region",
        "aliases": ["area", "selection", "crop"],
        "description": "Pick an area to screenshot",
        "when": "command -v niri",
        "action": "niri msg action screenshot"
    },
    "capture.window": {
        "icon": "󰖯",
        "label": "Window",
        "aliases": ["active"],
        "description": "Screenshot the focused window",
        "when": "command -v niri",
        "action": "niri msg action screenshot-window"
    },
    "capture.screen": {
        "icon": "󰍹",
        "label": "Screen",
        "aliases": ["display", "monitor", "fullscreen"],
        "description": "Screenshot the whole focused screen",
        "when": "command -v niri",
        "action": "niri msg action screenshot-screen"
    },
    // The annotate and OCR rows are ports of the pre-qshell dotfiles-linux
    // capture flow (satty on the capture, slurp + tesseract for text), not
    // omarchy's — their screenshot script is hyprshot/tensaku-shaped and
    // Hyprland-bound. Each row hides until its tool exists.
    "capture.annotate-region": {
        "icon": "󰽉",
        "label": "Region → Annotate",
        "aliases": ["annotate", "edit", "markup", "satty", "draw", "slurp"],
        "description": "Pick an area and open the shot in satty",
        "when": "command -v satty && command -v slurp",
        "action": "screenshot-annotate --region"
    },
    "capture.annotate": {
        "icon": "󱇣",
        "label": "Annotate Last Capture",
        "aliases": ["annotate", "edit", "clipboard", "satty", "markup"],
        "description": "Open the clipboard image in satty",
        "when": "command -v satty",
        "action": "screenshot-annotate"
    },
    "capture.ocr": {
        "icon": "󱄺",
        "label": "Extract Text (OCR)",
        "aliases": ["ocr", "text", "read", "recognize", "extract"],
        "description": "Pick an area and copy its text",
        "when": "command -v tesseract",
        "action": "screenshot-ocr"
    },
    // Omarchy's trigger.capture.qr. The decoded value only ever reaches the
    // clipboard — never the notification body, never stdout — because QR codes
    // routinely carry secrets (otpauth:// 2FA setup URIs).
    "capture.qr": {
        "icon": "󰐲",
        "label": "QR Code",
        "aliases": ["qr", "qrcode", "barcode", "scan", "decode"],
        "description": "Pick an area and copy the QR code it contains",
        "when": "command -v zbarimg",
        "action": "screenshot-qr"
    },
    // Omarchy's trigger.transcode: re-encode a picture or video for sharing.
    // Interactive halves (fzf file pick, gum format/resolution) run in a
    // float; the finished file's URI lands on the clipboard.
    "capture.transcode": {
        "icon": "󰕧",
        "label": "Transcode",
        "aliases": ["convert", "reencode", "compress", "share"],
        "description": "Re-encode a picture or video into a share-friendly file",
        "when": "command -v ffmpeg && command -v fzf",
        "action": "foot-run --app-id=qshell-float -e bash -lc 'transcode; read -r -p \"press enter to close\"'"
    },
    // Omarchy's trigger.capture.color runs hyprpicker; niri ships the picker
    // in the compositor, so ours is one IPC call wrapped in bin/color-pick.
    "capture.color": {
        "icon": "󰈊",
        "label": "Color Picker",
        "aliases": ["color", "colour", "pick", "eyedropper", "picker"],
        "description": "Pick a color from the screen and copy its hex value",
        "action": "color-pick"
    },
    // Omarchy's trigger.capture.screenrecord submenu, one row per audio
    // variant with Stop declared first and guarded by a `pgrep` test, exactly
    // as theirs is. Two differences, both from wf-recorder: their single smart
    // picker becomes an explicit Region/Screen split (see bin/screenrecord),
    // and their "desktop + microphone audio" row cannot exist because
    // wf-recorder records one device — the microphone gets its own rows
    // instead. Their webcam row needs mpv + v4l2-ctl, neither installed.
    "capture.screenrecord": {
        "icon": "󰻂",
        "label": "Screenrecord",
        "aliases": ["record", "recording", "screenrecording", "screen-record", "video", "capture-video"],
        "description": "Record the screen to a video file",
        "when": "command -v wf-recorder"
    },
    "capture.screenrecord.stop": {
        "icon": "󰓛",
        "label": "Stop Screenrecording",
        "aliases": ["stop", "end", "finish"],
        "description": "Stop the running screen recording and save the file",
        "when": "pgrep -x wf-recorder",
        "action": "screenrecord stop"
    },
    "capture.screenrecord.region": {
        "icon": "󰩭",
        "label": "Region, no audio",
        "aliases": ["area", "selection", "crop"],
        "description": "Pick an area and record it without sound",
        "action": "screenrecord --region"
    },
    "capture.screenrecord.region-audio": {
        "icon": "󰕾",
        "label": "Region with desktop audio",
        "aliases": ["area", "sound", "output"],
        "description": "Pick an area and record it with the desktop audio",
        "action": "screenrecord --region --with-desktop-audio"
    },
    "capture.screenrecord.region-mic": {
        "icon": "󰍬",
        "label": "Region with microphone",
        "aliases": ["area", "mic", "voice"],
        "description": "Pick an area and record it with the microphone",
        "action": "screenrecord --region --with-microphone-audio"
    },
    "capture.screenrecord.screen": {
        "icon": "󰍹",
        "label": "Screen, no audio",
        "aliases": ["display", "monitor", "fullscreen", "output"],
        "description": "Record the whole focused screen without sound",
        "action": "screenrecord --fullscreen"
    },
    "capture.screenrecord.screen-audio": {
        "icon": "󰕾",
        "label": "Screen with desktop audio",
        "aliases": ["display", "sound", "fullscreen"],
        "description": "Record the whole focused screen with the desktop audio",
        "action": "screenrecord --fullscreen --with-desktop-audio"
    },
    "capture.screenrecord.screen-mic": {
        "icon": "󰍬",
        "label": "Screen with microphone",
        "aliases": ["display", "mic", "voice", "fullscreen"],
        "description": "Record the whole focused screen with the microphone",
        "action": "screenrecord --fullscreen --with-microphone-audio"
    },

    // ------------------------------------------------------------ background
    "background.choose": {
        "icon": "󰸉",
        "label": "Choose",
        "aliases": ["background-choose", "pick", "picker"],
        "description": "Pick a wallpaper from this theme and your own",
        "call": "wallpaper"
    },
    "background.next": {
        "icon": "󰒭",
        "label": "Next",
        "aliases": ["background-next", "cycle", "shuffle"],
        "description": "Advance to the next wallpaper",
        "action": "\"$HOME/.dotfiles/bin/background-next\""
    },

    // ----------------------------------------------------------------- music
    // Four rows, where the old radio submenu had five. The two that went are
    // not missing features, they moved INSIDE the player, which is the whole
    // point of replacing a pile of shell scripts with cliamp: browsing the
    // 30 000+ radio-browser.info catalogue is `R` then `/`, and saving what is
    // playing is `f` — neither has a CLI verb, and wrapping the socket to fake
    // one would be building a worse copy of a screen that already exists.
    //
    // `cliamp status` exits non-zero when nothing is running, so it guards the
    // two rows that only make sense mid-playback exactly the way the old
    // `radio status` did — they lead the submenu and hide while it is idle,
    // like capture.screenrecord.stop.
    // cliamp is named by absolute path, like every other command here: it
    // lives in ~/.local/bin, which the shell's own environment does not
    // reliably carry (run_after_10's header has the same note about bash).
    "music.toggle": {
        "icon": "󰏤",
        "label": "Pause / Resume",
        "aliases": ["pause", "resume", "toggle", "hold"],
        "description": "Pause what is playing, or start it again",
        "when": "\"$HOME/.local/bin/cliamp\" status",
        "action": "\"$HOME/.local/bin/cliamp\" toggle"
    },
    "music.stop": {
        "icon": "󰓛",
        "label": "Stop",
        "aliases": ["stop", "off", "silence", "quit"],
        "description": "Stop playback",
        "when": "\"$HOME/.local/bin/cliamp\" status",
        "action": "\"$HOME/.local/bin/cliamp\" stop"
    },
    "music.open": {
        "icon": "󰝚",
        "label": "Open Player",
        "aliases": ["open", "player", "cliamp", "radio", "stations", "browse", "podcast", "spotify"],
        "description": "Open cliamp, or focus it if it is already playing",
        "action": "\"$HOME/.dotfiles/bin/music\""
    },
    "music.play": {
        "icon": "󰍉",
        "label": "Play a Track",
        "aliases": ["song", "track", "youtube", "play", "search", "queue"],
        "description": "Search YouTube for a track and add it to the playlist",
        "when": "command -v yt-dlp",
        "action": "\"$HOME/.dotfiles/bin/music\" --prompt"
    },

    // -------------------------------------------------------------- reminder
    "reminder.set": {
        "icon": "󰢌",
        "label": "Set one",
        "aliases": ["reminder-set", "remind"],
        "description": "Ask for a delay and a message",
        "call": "reminders"
    },
    "reminder.show": {
        "icon": "󰢌",
        "label": "Show all",
        "aliases": ["reminder-show", "upcoming"],
        "description": "Notify what is still outstanding",
        "action": "\"$HOME/.dotfiles/bin/reminder\" show"
    },
    "reminder.clear": {
        "icon": "󰢌",
        "label": "Clear all",
        "aliases": ["reminder-clear"],
        "description": "Cancel every outstanding reminder",
        "action": "\"$HOME/.dotfiles/bin/reminder\" clear"
    },

    // ---------------------------------------------------------------- toggle
    "toggle.dnd": {
        "icon": "󰂛",
        "label": "Do Not Disturb",
        "aliases": ["dnd", "notifications", "silence", "quiet"],
        "description": "Silence notification popups",
        "state": "dnd",
        "call": "dnd"
    },
    "toggle.blur": {
        "icon": "󰂵",
        "label": "Blur",
        "aliases": ["blur", "glass", "frost", "transparency", "background-effect"],
        "description": "Frost windows and shell cards over the wallpaper",
        "state": "blur",
        "call": "blur"
    },
    // systemd-coredump already journals every crash; crash-watch.service turns
    // that into a toast whose click hands the facts to Claude Code with the
    // diagnose-crash skill. The flag is a STOP file, so ✓ means "no flag".
    "toggle.crash-capture": {
        "icon": "󱚡",
        "label": "Crash Capture",
        "aliases": ["crash", "coredump", "core", "segfault", "diagnose"],
        "description": "Notify when a program crashes, and offer an AI diagnosis",
        "when": "command -v coredumpctl",
        "checked": "test ! -e \"$HOME/.local/state/qshell/crash-capture-off\"",
        "action": "crash-capture-toggle"
    },
    "toggle.keyboard-layout": {
        "icon": "󰌌",
        "label": "Keyboard Layout",
        "aliases": ["kb", "layout", "language", "input"],
        "description": "Switch to the next keyboard layout",
        "when": "command -v niri",
        "action": "niri msg action switch-layout next"
    },
    // Omarchy's power-profiles provider submenu: rows come from the daemon at
    // open time (✓ marks the active profile), a pick saves per power source
    // through bin/power-profile.
    "toggle.profile": {
        "icon": "󰐋",
        "label": "Power Profile",
        "aliases": ["profile", "performance", "powersave", "power-saver", "balanced"],
        "description": "Pick the power profile for the current power source",
        "when": "command -v powerprofilesctl",
        "provider": "power-profiles"
    },

    // ----------------------------------------------------------------- setup
    "setup.shell": {
        "icon": "󰍜",
        "label": "Shell Config",
        "aliases": ["bar", "widgets", "shell-json"],
        "description": "Edit shell.json in a terminal",
        "when": "command -v foot",
        "action": "foot-run --app-id=qshell-float -e \"${EDITOR:-vi}\" \"$HOME/.dotfiles/shell/shell.json\""
    },
    "setup.quotes": {
        "icon": "󰉾",
        "label": "Screensaver Quotes",
        "aliases": ["screensaver", "quotes"],
        "description": "Edit the quotes the screensaver draws from",
        "when": "command -v foot",
        "action": "foot-run --app-id=qshell-float -e \"${EDITOR:-vi}\" \"$HOME/.dotfiles/home/dot_config/nirisaver/quotes.txt\""
    },
    "setup.niri": {
        "icon": "󱂬",
        "label": "Niri Config",
        "aliases": ["compositor", "keybinds", "keybindings", "kdl"],
        "description": "Edit the niri config in a terminal",
        "when": "command -v foot",
        "action": "foot-run --app-id=qshell-float -e \"${EDITOR:-vi}\" \"$HOME/.dotfiles/home/dot_config/niri/config.kdl\""
    },
    "setup.themes": {
        "icon": "󰸌",
        "label": "Theme Files",
        "aliases": ["dotfiles", "tokens", "toml"],
        "description": "Open a terminal in the dotfiles theme directory",
        "when": "command -v foot",
        "action": "foot-run --app-id=qshell-float --working-directory=\"$HOME/.dotfiles/themes\""
    },
    // Omarchy files this under Update → Timezone; ours lives in Setup with
    // the other config wizards. fzf picker in a float, polkit guards apply.
    "setup.timezone": {
        "icon": "󰗕",
        "label": "Timezone",
        "aliases": ["tz", "time", "zone", "clock"],
        "description": "Pick and apply a system timezone",
        "when": "command -v fzf",
        "action": "foot-run --app-id=qshell-float -e timezone-set"
    },
    // Omarchy's Install/Remove → Web App / TUI rows (their webapp-install /
    // tui-install, ported as bin/ scripts). They write .desktop files only —
    // no packages — so they sit here with the other Setup wizards rather
    // than behind an Install root ours doesn't have.
    "setup.webapp-add": {
        "icon": "󰖟",
        "label": "Add Web App",
        "aliases": ["webapp", "webapps", "web-app", "site"],
        "description": "Create a launcher entry that opens a site as an app window",
        "when": "command -v gum",
        "action": "foot-run --app-id=qshell-float -e bash -lc 'webapp-install; read -r -p \"press enter to close\"'"
    },
    "setup.webapp-remove": {
        "icon": "󰖟",
        "label": "Remove Web App",
        "aliases": ["webapp-remove"],
        "description": "Delete a web-app launcher entry",
        "when": "grep -qs X-Qshell-WebApp=true \"$HOME\"/.local/share/applications/*.desktop",
        "action": "foot-run --app-id=qshell-float -e bash -lc 'webapp-remove; read -r -p \"press enter to close\"'"
    },
    "setup.tui-add": {
        "icon": "󰆍",
        "label": "Add TUI App",
        "aliases": ["tui", "terminal-app", "console"],
        "description": "Create a launcher entry that runs a terminal app (float or tile)",
        "when": "command -v gum",
        "action": "foot-run --app-id=qshell-float -e bash -lc 'tui-install; read -r -p \"press enter to close\"'"
    },
    "setup.tui-remove": {
        "icon": "󰆍",
        "label": "Remove TUI App",
        "aliases": ["tui-remove"],
        "description": "Delete a TUI launcher entry",
        "when": "grep -qs X-Qshell-TUI=true \"$HOME\"/.local/share/applications/*.desktop",
        "action": "foot-run --app-id=qshell-float -e bash -lc 'tui-remove; read -r -p \"press enter to close\"'"
    },
    // Omarchy's setup.default.agent radio picked which agent their launcher
    // started; it went with the launcher (see the note by the root rows).

    // ---------------------------------------------------------------- system
    "system.lock": {
        "icon": "󰌾",
        "label": "Lock",
        "aliases": ["lockscreen", "screensaver"],
        "description": "Lock the session",
        "call": "lock"
    },
    "system.relaunch": {
        "icon": "󰑐",
        "label": "Relaunch Shell",
        "aliases": ["restart-shell", "reload", "qs"],
        "description": "Restart this shell process",
        // bin/qshell-relaunch, not a pkill dance: menu actions run in the
        // shell's own cgroup, so anything that kills the shell kills the
        // relauncher with it (and SIGTERM retires the unit as a success, so
        // Restart=on-failure stays out of it). The script hands the job to
        // systemd, which is outside that cgroup.
        "action": "qshell-relaunch"
    },
    // Omarchy files this under Update → Hardware (title "Restart") beside
    // audio/wifi/trackpad rows we have no scripts for; our update is a leaf,
    // so the one hardware escape hatch we ship sits here beside the other
    // restart row. Runs in a visible terminal, as their
    // omarchy-launch-floating-terminal-with-presentation row does.
    "system.restart-bluetooth": {
        "icon": "󰂯",
        "label": "Restart Bluetooth",
        "aliases": ["bluetooth", "rfkill", "unblock", "restart-bluetooth", "hardware"],
        "description": "Unblock the radio and restart the bluetooth stack",
        "when": "command -v rfkill && command -v foot",
        "action": "foot-run --app-id=qshell-float -e bash -lc '\"$HOME/.dotfiles/bin/bluetooth-restart\"; read -r -p \"press enter to close\"'"
    },
    // Omarchy files this under Trigger > Tests (2521b11) beside their network
    // speed test; ours sits with the other diagnostic row, since our network
    // test is reached from the Network panel rather than the menu. The overlay
    // starts measuring as soon as it opens, so the row is the whole gesture.
    "system.disk-speedtest": {
        "icon": "󰋊",
        "label": "Disk Speed Test",
        "aliases": ["disk", "speed", "benchmark", "ssd", "nvme", "throughput", "io"],
        "description": "Measure live disk read and write speed",
        "action": "qs ipc call diskspeedtest -- show"
    },
    "system.exit": {
        "icon": "󰍃",
        "label": "Exit niri",
        "aliases": ["logout", "quit", "sign-out"],
        "when": "command -v niri",
        "action": "niri msg action quit --skip-confirmation"
    },
    "system.reboot": {
        "icon": "󰜉",
        "label": "Reboot",
        "aliases": ["restart"],
        "when": "command -v systemctl",
        "action": "systemctl reboot"
    },
    "system.shutdown": {
        "icon": "󰐥",
        "label": "Shutdown",
        "aliases": ["poweroff", "halt", "off"],
        "when": "command -v systemctl",
        "action": "systemctl poweroff"
    }
};
