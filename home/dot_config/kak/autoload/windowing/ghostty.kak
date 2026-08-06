# Ghostty windowing module for Kakoune
# https://ghostty.org/docs/features/applescript
# Requires Ghostty 1.3.0+ for native AppleScript API
provide-module ghostty %{
  evaluate-commands %sh{
      [ -z "${kak_opt_windowing_modules}" ] || [ -n "$TERM_PROGRAM" ] && [ "$TERM_PROGRAM" = "ghostty" ] || echo 'fail ghostty not detected'
  }

  define-command ghostty-terminal-impl -hidden -params 2.. %{
    nop %sh{
      action="$1"
      shift

      cmd=$(printf '%s ' "$@")
      cmd=${cmd% }

      # Escape backslashes and double quotes for AppleScript string
      escaped_cmd=$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')
      escaped_path=$(printf '%s' "$PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')

      case "$action" in
        new-tab)
          osascript <<EOF
tell application "Ghostty"
  set conf to new surface configuration
  set command of conf to "$escaped_cmd"
  set initial working directory of conf to "$PWD"
  set environment variables of conf to {"PATH=$escaped_path"}
  new tab in front window with configuration conf
end tell
EOF
          ;;
        split-right)
          osascript <<EOF
tell application "Ghostty"
  set conf to new surface configuration
  set command of conf to "$escaped_cmd"
  set initial working directory of conf to "$PWD"
  set environment variables of conf to {"PATH=$escaped_path"}
  set t to focused terminal of selected tab of front window
  split t direction right with configuration conf
end tell
EOF
          ;;
        split-down)
          osascript <<EOF
tell application "Ghostty"
  set conf to new surface configuration
  set command of conf to "$escaped_cmd"
  set initial working directory of conf to "$PWD"
  set environment variables of conf to {"PATH=$escaped_path"}
  set t to focused terminal of selected tab of front window
  split t direction down with configuration conf
end tell
EOF
          ;;
        new-window)
          osascript <<EOF
tell application "Ghostty"
  set conf to new surface configuration
  set command of conf to "$escaped_cmd"
  set initial working directory of conf to "$PWD"
  set environment variables of conf to {"PATH=$escaped_path"}
  new window with configuration conf
end tell
EOF
          ;;
        *)
          echo "Unknown action: $action" >&2
          exit 1
          ;;
      esac
    }
  }

  define-command ghostty-terminal-vertical -params 1.. -docstring '
  ghostty-terminal-vertical <program> [<arguments>]: create a new terminal as a ghostty pane
  The current pane is split into two, top and bottom
  The program passed as argument will be executed in the new terminal' \
  %{
    ghostty-terminal-impl split-down %arg{@}
  }
  complete-command ghostty-terminal-vertical shell

  define-command ghostty-terminal-horizontal -params 1.. -docstring '
  ghostty-terminal-horizontal <program> [<arguments>]: create a new terminal as a ghostty pane
  The current pane is split into two, left and right
  The program passed as argument will be executed in the new terminal' \
  %{
    ghostty-terminal-impl split-right %arg{@}
  }
  complete-command ghostty-terminal-horizontal shell

  define-command ghostty-terminal-tab -params 1.. -docstring '
  ghostty-terminal-tab <program> [<arguments>]: create a new terminal as a ghostty tab
  The program passed as argument will be executed in the new terminal' \
  %{
    ghostty-terminal-impl new-tab %arg{@}
  }
  complete-command ghostty-terminal-tab shell

  define-command ghostty-terminal-window -params 1.. -docstring '
  ghostty-terminal-window <program> [<arguments>]: create a new terminal as a ghostty window
  The program passed as argument will be executed in the new terminal' \
  %{
    ghostty-terminal-impl new-window %arg{@}
  }
  complete-command ghostty-terminal-window shell

  define-command ghostty-focus -params ..1 -docstring '
  ghostty-focus [<client>]: focus the given client
  If no client is passed then the current one is used' \
  %{
    evaluate-commands %sh{
      if [ $# -eq 1 ]; then
        printf %s\\n "evaluate-commands -client '$1' focus"
      else
        osascript <<EOF
tell application "Ghostty"
  set t to focused terminal of selected tab of front window
  focus t
end tell
EOF
      fi
    }
  }
  complete-command -menu ghostty-focus client
  alias global focus ghostty-focus

  define-command split -params 0..1 -docstring "split [file]: Split current pane horizontally" %{
    evaluate-commands %sh{
      if [ $# -eq 0 ]; then
        echo "ghostty-terminal-horizontal kak -c '$kak_session' '$kak_bufname'"
      else
        echo "ghostty-terminal-horizontal kak -c '$kak_session' '$1'"
      fi
    }
  }

  define-command vsplit -params 0..1 -docstring "vsplit [file]: Split current pane vertically" %{
    evaluate-commands %sh{
      if [ $# -eq 0 ]; then
        echo "ghostty-terminal-vertical kak -c '$kak_session' '$kak_bufname'"
      else
        echo "ghostty-terminal-vertical kak -c '$kak_session' '$1'"
      fi
    }
  }

  alias global vsp vsplit
  alias global sp split
  complete-command split shell-script-candidates %opt{find_completion}
  complete-command vsplit shell-script-candidates %opt{find_completion}

  define-command ghostty-split -params 1 -docstring 'ghostty-split (down / right / left / up)' %{
    nop %sh{
      osascript <<EOF
tell application "Ghostty"
  set t to focused terminal of selected tab of front window
  split t direction $1
end tell
EOF
    }
  }

  define-command ghostty-select-pane -params 1 -docstring 'ghostty-select-pane <direction>: focus pane (left / right / up / down)' %{
    nop %sh{
      osascript <<EOF
tell application "Ghostty"
  set t to focused terminal of selected tab of front window
  perform action "goto_split:$1" on t
end tell
EOF
    }
  }

  define-command ghostty-close -params 0 -docstring 'close the focused ghostty terminal surface' %{
    nop %sh{
      osascript <<EOF
tell application "Ghostty"
  close (focused terminal of selected tab of front window)
end tell
EOF
    }
  }

  declare-user-mode window-ghostty
  map global window-ghostty h ':ghostty-select-pane left<ret>'  -docstring 'move left'
  map global window-ghostty l ':ghostty-select-pane right<ret>' -docstring 'move right'
  map global window-ghostty k ':ghostty-select-pane up<ret>'    -docstring 'move up'
  map global window-ghostty j ':ghostty-select-pane down<ret>'  -docstring 'move down'
  map global window-ghostty s ':ghostty-split down<ret>'        -docstring 'horizontal split'
  map global window-ghostty v ':ghostty-split right<ret>'       -docstring 'vertical split'
  map global window-ghostty q ':q<ret>'                         -docstring 'close client'
  map global window-ghostty Q ':q!<ret>'                        -docstring 'close client (force)'
  map global window-ghostty t ':ghostty-terminal-tab kak -c %val{session}<ret>' -docstring 'new tab'
  map global window-ghostty x ':ghostty-close<ret>'             -docstring 'close surface'

  map global user w ':enter-user-mode window-ghostty<ret>' -docstring 'window mode'
}
