# Disarm the terminal modes a dropped SSH session leaves armed: mouse
# tracking (1000/1002/1003 and the 1006 encoding), focus reporting (1004) and
# the alternate screen (1049), then show the cursor again.
#
# A remote tmux, herdr or editor turns these on over the pipe and is the only
# thing that can turn them off. When the connection dies instead of exiting,
# they stay on locally and every mouse move floods the prompt with escape
# junk. (omarchy default/bash/fns/ssh-reconnect.)
function _ssh_disarm --description 'Undo terminal modes a dead SSH session left armed'
    printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?1049l\e[?25h'
end
