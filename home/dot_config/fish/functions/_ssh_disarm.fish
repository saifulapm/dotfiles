# Mouse tracking (1000/1002/1003, encoding 1006), focus reporting (1004) and the alternate screen (1049) stay on locally after a dead session, and every mouse move then floods the prompt with escape junk.
function _ssh_disarm --description 'Undo terminal modes a dead SSH session left armed'
    printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?1049l\e[?25h'
end
