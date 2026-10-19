# An SSH login gets DBUS_SESSION_BUS_ADDRESS and XDG_RUNTIME_DIR from pam_systemd, but not the compositor,
# so niri msg, grim, wtype and qs ipc all fail over SSH. niri-session imports the live values into the
# systemd user manager, so copy them from there, and only while that niri is up (its socket exists).
if set -q SSH_CONNECTION; and not set -q WAYLAND_DISPLAY
    for kv in (systemctl --user show-environment 2>/dev/null | string match -r '^(?:WAYLAND_DISPLAY|NIRI_SOCKET|DISPLAY)=.*')
        set -l pair (string split -m1 = $kv)
        set -f desktop_$pair[1] $pair[2]
    end
    if set -q desktop_NIRI_SOCKET; and test -S "$desktop_NIRI_SOCKET"
        set -gx WAYLAND_DISPLAY $desktop_WAYLAND_DISPLAY
        set -gx NIRI_SOCKET $desktop_NIRI_SOCKET
        set -q desktop_DISPLAY; and set -gx DISPLAY $desktop_DISPLAY
    end
end
