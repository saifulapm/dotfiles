# http://tmux.github.io/
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
provide-module tmux %{
  # ensure we're running under tmux
  evaluate-commands %sh{
    [ -z "${kak_opt_windowing_modules}" ] || [ -n "$TMUX" ] || echo 'fail tmux not detected'
  }

  define-command -hidden -params 2.. tmux-terminal-impl %{
    evaluate-commands %sh{
      tmux=${kak_client_env_TMUX:-$TMUX}
      if [ -z "$tmux" ]; then
        echo "fail 'This command is only available in a tmux session'"
        exit
      fi
      tmux_args="$1"
      if [ "${1%%-*}" = split ]; then
        tmux_args="$tmux_args -t ${kak_client_env_TMUX_PANE}"
      elif [ "${1%% *}" = new-window ]; then
        session_id=$(tmux display-message -p -t ${kak_client_env_TMUX_PANE} '#{session_id}')
        tmux_args="$tmux_args -t $session_id"
      fi
      shift
      # ideally we should escape single ';' to stop tmux from interpreting it as a new command
      # but that's probably too rare to care
      if [ -n "$TMPDIR" ]; then
        TMUX=$tmux tmux $tmux_args env TMPDIR="$TMPDIR" "$@"
      else
        TMUX=$tmux tmux $tmux_args "$@"
      fi
    }
  }

  define-command tmux-terminal-vertical -params 1.. -docstring '
  tmux-terminal-vertical <program> [<arguments>]: create a new terminal as a tmux pane
  The current pane is split into two, top and bottom
  The program passed as argument will be executed in the new terminal' \
  %{
    tmux-terminal-impl 'split-window -v' %arg{@}
  }
  complete-command tmux-terminal-vertical shell

  define-command tmux-terminal-horizontal -params 1.. -docstring '
  tmux-terminal-horizontal <program> [<arguments>]: create a new terminal as a tmux pane
  The current pane is split into two, left and right
  The program passed as argument will be executed in the new terminal' \
  %{
    tmux-terminal-impl 'split-window -h' %arg{@}
  }
  complete-command tmux-terminal-horizontal shell

  define-command tmux-terminal-window -params 1.. -docstring '
  tmux-terminal-window <program> [<arguments>]: create a new terminal as a tmux window
  The program passed as argument will be executed in the new terminal' \
  %{
    tmux-terminal-impl 'new-window' %arg{@}
  }
  complete-command tmux-terminal-window shell
  alias global tmux-terminal-tab tmux-terminal-window

  define-command tmux-focus -params ..1 -docstring '
  tmux-focus [<client>]: focus the given client
  If no client is passed then the current one is used' \
  %{
    evaluate-commands %sh{
      if [ $# -eq 1 ]; then
        printf "evaluate-commands -client '%s' focus" "$1"
      elif [ -n "${kak_client_env_TMUX}" ]; then
        # select-pane makes the pane active in the window, but does not select the window. Both select-pane
        # and select-window should be invoked in order to select a pane on a currently not focused window.
        TMUX="${kak_client_env_TMUX}" tmux select-window -t "${kak_client_env_TMUX_PANE}" \; \
                                           select-pane   -t "${kak_client_env_TMUX_PANE}" > /dev/null
      fi
    }
  }
  complete-command -menu tmux-focus client

  ## The default behaviour for the `new` command is to open an horizontal pane in a tmux session
  alias global focus tmux-focus

  define-command split -params 0..1 -docstring "split [file]: Split current pane horizontally" %{
    evaluate-commands %sh{
      if [ $# -eq 0 ]; then
        echo "nop %sh{ tmux split-window -v \"kak -c '$kak_session' '$kak_bufname'\" }"
      else
        echo "nop %sh{ tmux split-window -v \"kak -c '$kak_session' '$1'\" }"
      fi
    }
  }

  define-command vsplit -params 0..1 -docstring "vsplit [file]: Split current pane vertically" %{
    evaluate-commands %sh{
      if [ $# -eq 0 ]; then
        echo "nop %sh{ tmux split-window -h \"kak -c '$kak_session' '$kak_bufname'\" }"
      else
        echo "nop %sh{ tmux split-window -h \"kak -c '$kak_session' '$1'\" }"
      fi
    }
  }

  alias global vsp vsplit
  alias global sp split
  complete-command split shell-script-candidates %opt{find_completion}
  complete-command vsplit shell-script-candidates %opt{find_completion}

  define-command tmux-split -params 1 -docstring 'split (down / right)' %{
    nop %sh{
      tmux split-window $1 kak -c $kak_session
    }
  }

  define-command tmux-select-pane -params 1 -docstring 'select pane' %{
    nop %sh{
      tmux select-pane $1
    }
  }

  declare-user-mode window-tmux
  map global window-tmux Q ':q!<ret>'                  -docstring 'close window (force)'
  map global window-tmux h ':tmux-select-pane -L<ret>' -docstring 'move left'
  map global window-tmux s ':tmux-split -v<ret>'       -docstring 'horizontal split'
  map global window-tmux q ':q<ret>'                   -docstring 'close window'
  map global window-tmux l ':tmux-select-pane -R<ret>' -docstring 'move right'
  map global window-tmux k ':tmux-select-pane -U<ret>' -docstring 'move up'
  map global window-tmux j ':tmux-select-pane -D<ret>' -docstring 'move down'
  map global window-tmux v ':tmux-split -h<ret>'       -docstring 'vertical split'

  map global user w ':enter-user-mode window-tmux<ret>' -docstring 'window mode'

  # Override pickers
  # map global picker f ':tmux-file-picker<ret>'   -docstring 'file picker'
  # map global user <space> ':tmux-file-picker<ret>'   -docstring 'pick file'
  # map global user , ':tmux-buffer-picker<ret>'   -docstring 'buffer picker'
  # map global picker b ':tmux-buffer-picker<ret>'   -docstring 'buffer picker'
}
