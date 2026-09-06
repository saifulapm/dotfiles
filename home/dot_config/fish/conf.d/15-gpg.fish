# GPG — make the passphrase prompt follow you to whichever terminal asked.
#
# gpg-agent is a daemon started by the graphical session and it spawns pinentry
# with its OWN environment, not the client's. On a headless machine the agent
# still holds WAYLAND_DISPLAY from the tty1 session, so `pass` run over SSH drew
# a Qt dialog on a monitor nobody was sitting at and the SSH session hung until
# it timed out (NUC, 2026-09-06). bin/pinentry-auto picks the right prompt; the
# two variables below are how it is told which one.

# Which terminal the agent should draw on. GnuPG's own standing advice, and
# unset on this machine until now — without it the agent reuses whatever tty it
# inherited at startup.
if isatty stdin
    set -gx GPG_TTY (tty)
end

# The honest signal that a request came from a terminal. gpg forwards this from
# the client, through the agent, into pinentry's environment — verified on the
# NUC, and it is the ONLY thing that survives that trip. A display check alone
# cannot work here: the agent's inherited WAYLAND_DISPLAY is present either way,
# and `gpg-connect-agent updatestartuptty` does not clear it.
#
# Local terminals deliberately leave this unset, so they keep falling through
# pinentry-auto's display check to the Qt dialog, exactly as before.
if set -q SSH_CONNECTION
    set -gx PINENTRY_USER_DATA curses
end

# A machine that has just been powered on has a locked agent, and imapnotify,
# mbsync, msmtp and browserpass are all failing quietly until someone types the
# passphrase once. At a screen that answers itself; headless it never does. So
# an interactive SSH login is where we ask — it is the only place left.
#
# Cheap when there is nothing to do: gpg-unlock's first act is a
# --pinentry-mode=error probe that succeeds silently on an unlocked agent.
# Gated on SSH_TTY, not SSH_CONNECTION, because a prompt needs a terminal —
# `ssh host <command>` must stay non-interactive.
if status is-interactive; and set -q SSH_TTY
    gpg-unlock
end
