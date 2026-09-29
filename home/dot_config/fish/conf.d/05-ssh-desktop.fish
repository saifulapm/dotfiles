# SSH into the live desktop (managed by chezmoi).
#
# An SSH login gets DBUS_SESSION_BUS_ADDRESS and XDG_RUNTIME_DIR from
# pam_systemd, but not the compositor: no WAYLAND_DISPLAY, no NIRI_SOCKET. So
# an agent working over SSH could not use the desktop skill at all — niri msg,
# grim, wtype, wlrctl and qs ipc all failed (verified 2026-09-29). niri-session
# imports the live values into the systemd user manager, so copy them from
# there, and only while that niri is actually up (its socket exists): a
# headless box, or one sitting at the tty1 login, stays headless.
#
# Every SSH shell, not just agents (user pick): anything graphical started over
# SSH now lands on that machine's screen — xdg-open, and pkexec in the chezmoi
# scripts / qt6-hold, which prompt there instead of on the terminal.
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
