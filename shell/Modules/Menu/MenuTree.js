// The command menu's action tree — this file IS the menu. Edit it and the
// running shell picks the change up on the next reload.
//
// Shape mirrors omarchy's omarchy-menu.jsonc (CREDITS.md): ids are keys, a
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
    // Ours, with no upstream counterpart: omarchy ships no radio and no music
    // picker — their whole music story is a Spotify package that has no
    // aarch64 build (bin/radio's header). Sits with the other pickers.
    "radio": {
        "icon": "󰖖",
        "label": "Radio",
        "aliases": ["music", "radio", "stream", "listen", "song", "player", "station", "stations", "somafm", "youtube"],
        "description": "Play internet radio, or a track from YouTube"
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

    // ----------------------------------------------------------------- radio
    // Stop leads and hides while nothing plays, the way
    // capture.screenrecord.stop does. `radio status` exits non-zero when idle,
    // so the same command is both the guard here and the answer elsewhere.
    "radio.stop": {
        "icon": "󰓛",
        "label": "Stop",
        "aliases": ["stop", "off", "silence", "quit"],
        "description": "Stop the stream that is playing",
        "when": "\"$HOME/.dotfiles/bin/radio\" status",
        "action": "\"$HOME/.dotfiles/bin/radio\" stop"
    },
    "radio.stations": {
        "icon": "󰲰",
        "label": "Stations",
        "aliases": ["station", "saved", "presets", "list"],
        "description": "Pick one of the saved stations",
        "action": "\"$HOME/.dotfiles/bin/radio\""
    },
    "radio.music": {
        "icon": "󰝚",
        "label": "Play Music",
        "aliases": ["song", "track", "youtube", "play", "search"],
        "description": "Search YouTube for a track and play its audio",
        "when": "command -v yt-dlp",
        "action": "\"$HOME/.dotfiles/bin/music\""
    },
    "radio.search": {
        "icon": "󰍉",
        "label": "Search Stations",
        "aliases": ["find", "browse", "radio-browser", "new", "country"],
        "description": "Search radio-browser.info for a station anywhere",
        "action": "\"$HOME/.dotfiles/bin/radio\" search"
    },
    "radio.save": {
        "icon": "󰆓",
        "label": "Save Current Station",
        "aliases": ["save", "bookmark", "keep", "add"],
        "description": "Append what is playing to the saved station list",
        "when": "\"$HOME/.dotfiles/bin/radio\" status",
        "action": "\"$HOME/.dotfiles/bin/radio\" save"
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
    "toggle.nightlight": {
        "icon": "󰔎",
        "label": "Night Light",
        "aliases": ["nightlight", "night-light", "warm", "wlsunset", "gamma"],
        "description": "Warm the screen to 4000 K",
        "when": "command -v wlsunset",
        "state": "nightlight",
        "call": "nightlight"
    },
    "toggle.blur": {
        "icon": "󰂵",
        "label": "Blur",
        "aliases": ["blur", "glass", "frost", "transparency", "background-effect"],
        "description": "Frost windows and shell cards over the wallpaper",
        "state": "blur",
        "call": "blur"
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
        // The bash child is orphaned by the pkill and survives it, so it can
        // start the replacement in a fresh session.
        "action": "pkill -x qs; sleep 0.5; exec setsid qs"
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
