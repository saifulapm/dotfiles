# The TERM to hand an emacsclient that may end up drawing a terminal frame.
#
# Emacs reads its color depth from TERMINFO, not from COLORTERM, and foot's
# default entry caps at colors#0x100 — so a tty frame approximated every color
# of the rendered qshell palette to the nearest xterm-256 index (bg-main
# #161622 came out as index 17, a navy) and looked nothing like the GUI frames
# the same theme paints. The `-direct` sibling entry advertises
# colors#0x1000000, which is what makes Emacs emit the theme's exact RGB.
#
# Probed rather than hardcoded to foot-direct, so a terminal with no direct
# entry (kitty) keeps the TERM it set. Applied per emacsclient invocation:
# emacsclient hands its own TERM to the daemon as the new frame's terminal
# type, so nothing else in this shell — nor Emacs's subprocesses, which get
# their own TERM — ever sees it.
function _emacs_term --description 'TERM for a terminal Emacs frame: the direct-color entry when one exists'
    if command -q infocmp
        and not string match -q '*-direct' -- $TERM
        and infocmp $TERM-direct >/dev/null 2>&1
        echo $TERM-direct
    else
        echo $TERM
    end
end
