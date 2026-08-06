declare-option -hidden str-list buffers_info

declare-option -hidden int buffers_total

# keys to use for buffer picking
declare-option -hidden str buffer_keys "1234567890qwertyuiopasdfghjklzxcvbnm"

# used to handle [+] (modified) symbol in list
define-command -hidden refresh-buffers-info %{
  set-option global buffers_info
  set-option global buffers_total 0
  # iteration over all buffers (except debug and scratch ones)
  evaluate-commands %sh{
    eval "set -- $kak_quoted_buflist"
    while [ "$1" ]; do
      # Skip buffers that start with * (debug, scratch, etc.)
      case "$1" in
        \**) shift; continue ;;
      esac

      # Get buffer info
      printf "evaluate-commands -no-hooks -buffer '%s' %%{\n" "$1"
      printf "  set-option -add global buffers_info \"%%val{bufname}_%%val{modified}\"\n"
      printf "}\n"
      shift
    done
  }
  evaluate-commands %sh{
    total=$(printf '%s\n' "$kak_opt_buffers_info" | tr ' ' '\n' | grep -v '^$' | wc -l)
    printf "set-option global buffers_total $total"
  }
}

# used to handle # (alt) symbol in list
declare-option -hidden str alt_bufname
declare-option -hidden str current_bufname
# adjust this number to display more buffers in info
declare-option -hidden int max_list_buffers 42

define-command -hidden info-buffers -docstring 'populate an info box with a numbered buffers list' %{
  refresh-buffers-info
  evaluate-commands %sh{
    # info title
    printf "info -title '$kak_opt_buffers_total buffers' -- %%^"

    index=0
    eval "set -- $kak_quoted_opt_buffers_info"
    while [ "$1" ]; do
      # limit lists too big
      index=$((index + 1))
      if [ "$index" -gt "$kak_opt_max_list_buffers" ]; then
        printf '  …'
        break
      fi

      name=${1%_*}
      if [ "$name" = "$kak_bufname" ]; then
        printf '>'
      elif [ "$name" = "$kak_opt_alt_bufname" ]; then
        printf '#'
      else
        printf ' '
      fi

      modified=${1##*_}
      if [ "$modified" = true ]; then
        printf '+ '
      else
        printf '  '
      fi

      if [ "$index" -lt 10 ]; then
        echo "0$index - $name"
      else
        echo "$index - $name"
      fi

      shift
    done
    printf ^\\n
  }
}

declare-user-mode pick-buffers
define-command -hidden pick-buffers -docstring 'enter buffer pick mode' %{
  refresh-buffers-info
  unmap global pick-buffers
  evaluate-commands %sh{
    docstring() {
      if [ "$1" = true ]; then
        printf "%s+ %s" "$2" "$3"
      else
        printf "%s  %s" "$2" "$3"
      fi
    }
    index=0
    keys=" $kak_opt_buffer_keys"
    num_keys=${#kak_opt_buffer_keys}
    eval "set -- $kak_quoted_opt_buffers_info"
    while [ "$1" ]; do
      # limit lists too big
      index=$((index + 1))
      if [ "$index" -gt "$num_keys" ]; then
        break
      fi

      buf_id=$(echo ${keys} | cut -c${index})
      name=${1%_*}
      modified=${1##*_}
      if [ "$name" = "$kak_bufname" ]; then
        printf "map global pick-buffers %s ': buffer-by-index %s<ret>' -docstring '%s'\n" ${buf_id} $index "$(docstring $modified '>' "$name")"
      elif [ "$name" = "$kak_opt_alt_bufname" ]; then
        printf "map global pick-buffers %s ': buffer-by-index %s<ret>' -docstring '%s'\n" ${buf_id} $index "$(docstring $modified '#' "$name")"
      else
        printf "map global pick-buffers %s ': buffer-by-index %s<ret>' -docstring '%s'\n" ${buf_id} $index "$(docstring $modified ':' "$name")"
      fi

      shift
    done
  }
  enter-user-mode pick-buffers
}

define-command -hidden buffer-first -docstring 'move to the first buffer in the list' 'buffer-by-index 1'

define-command -hidden buffer-last -docstring 'move to the last buffer in the list' %{
  buffer-by-index %opt{buffers_total}
}

define-command -hidden -params 1 buffer-by-index %{
  refresh-buffers-info
  evaluate-commands %sh{
    target=$1
    index=0
    eval "set -- $kak_quoted_opt_buffers_info"
    while [ "$1" ]; do
      index=$((index+1))
      name=${1%_*}
      if [ $index = $target ]; then
        printf "buffer '$name'"
      fi
      shift
    done
  }
}

define-command -hidden buffer-first-modified -docstring 'move to the first modified buffer in the list' %{
  refresh-buffers-info
  evaluate-commands %sh{
    eval "set -- $kak_quoted_opt_buffers_info"
    while [ "$1" ]; do
      name=${1%_*}
      modified=${1##*_}
      if [ "$modified" = true ]; then
        printf "buffer '$name'"
      fi
      shift
    done
  }
}

define-command -hidden delete-buffers -docstring 'delete all saved buffers (excludes scratch/debug)' %{
  evaluate-commands %sh{
    deleted=0
    eval "set -- $kak_quoted_buflist"
    while [ "$1" ]; do
      # Skip buffers that start with * (debug, scratch, etc.)
      case "$1" in
        \**) shift; continue ;;
      esac

      echo "try %{delete-buffer '$1'}"
      echo "echo -markup '{Information}$deleted buffers deleted'"
      deleted=$((deleted+1))
      shift
    done
  }
}

define-command -hidden buffer-only -docstring 'delete all saved buffers except current one (excludes scratch/debug)' %{
  evaluate-commands %sh{
    deleted=0
    eval "set -- $kak_quoted_buflist"
    while [ "$1" ]; do
      # Skip buffers that start with * (debug, scratch, etc.)
      case "$1" in
        \**) shift; continue ;;
      esac

      if [ "$1" != "$kak_bufname" ]; then
        echo "try %{delete-buffer '$1'}"
        echo "echo -markup '{Information}$deleted buffers deleted'"
        deleted=$((deleted+1))
      fi
      shift
    done
  }
}

define-command -hidden buffer-only-force -docstring 'delete all buffers except current one (excludes scratch/debug)' %{
  evaluate-commands %sh{
    deleted=0
    eval "set -- $kak_quoted_buflist"
    while [ "$1" ]; do
      # Skip buffers that start with * (debug, scratch, etc.)
      case "$1" in
        \**) shift; continue ;;
      esac

      if [ "$1" != "$kak_bufname" ]; then
        echo "delete-buffer! '$1'"
        echo "echo -markup '{Information}$deleted buffers deleted'"
        deleted=$((deleted+1))
      fi
      shift
    done
  }
}

define-command -hidden buffer-only-directory -docstring 'delete all saved buffers except the ones in the same current buffer directory (excludes scratch/debug)' %{
  evaluate-commands %sh{
    deleted=0
    current_buffer_dir=$(dirname "$kak_bufname")
    eval "set -- $kak_quoted_buflist"
    while [ "$1" ]; do
      # Skip buffers that start with * (debug, scratch, etc.)
      case "$1" in
        \**) shift; continue ;;
      esac

      dir=$(dirname "$1")
      if [ $dir != "$current_buffer_dir" ]; then
        echo "try %{delete-buffer '$1'}"
        echo "echo -markup '{Information}$deleted buffers deleted'"
        deleted=$((deleted+1))
      fi
      shift
    done
  }
}

define-command edit-kakrc -docstring 'open kakrc in a new buffer' %{
  evaluate-commands %sh{
    printf "edit $kak_config/kakrc"
  }
}

declare-user-mode buffers

map global buffers a 'ga'                             -docstring 'alternate ↔'
map global buffers b ': info-buffers<ret>'            -docstring 'info'
map global buffers c ': chat-buffer<ret>'             -docstring 'chat buffer'
map global buffers d ': delete-buffer<ret>'           -docstring 'delete'
map global buffers D ': delete-buffers<ret>'          -docstring 'delete all'
map global buffers f ': buffer<space>'                -docstring 'find'
map global buffers , ': pick-buffers<ret>'            -docstring 'Pick Buffer'
map global buffers h ': buffer-first<ret>'            -docstring 'first ⇐'
map global buffers l ': buffer-last<ret>'             -docstring 'last ⇒'
map global buffers m ': buffer-first-modified<ret>'   -docstring 'modified'
map global buffers n ': buffer-next<ret>'             -docstring 'next →'
map global buffers o ': buffer-only<ret>'             -docstring 'only'
map global buffers p ': buffer-previous<ret>'         -docstring 'previous ←'
map global buffers r ': rename-buffer '               -docstring 'rename'
map global buffers s ': edit -scratch *scratch*<ret>' -docstring '*scratch*'
map global buffers u ': buffer *debug*<ret>'          -docstring '*debug*'
map global normal <a-1> ':buffer-by-index 1<ret>'   -docstring 'Pick buffer'
map global normal <a-2> ':buffer-by-index 2<ret>'   -docstring 'Pick buffer'
map global normal <a-3> ':buffer-by-index 3<ret>'   -docstring 'Pick buffer'
map global normal <a-4> ':buffer-by-index 4<ret>'   -docstring 'Pick buffer'
map global normal <a-5> ':buffer-by-index 5<ret>'   -docstring 'Pick buffer'
map global normal <a-6> ':buffer-by-index 6<ret>'   -docstring 'Pick buffer'
map global normal <a-7> ':buffer-by-index 7<ret>'   -docstring 'Pick buffer'
map global normal <a-8> ':buffer-by-index 8<ret>'   -docstring 'Pick buffer'
map global normal <a-9> ':buffer-by-index 9<ret>'   -docstring 'Pick buffer'

# trick to access count, 3b → display third buffer
define-command -hidden enter-buffers-mode %{
  evaluate-commands %sh{
    if [ "$kak_count" -eq 0 ]; then
      printf 'enter-user-mode buffers'
    else
      printf "buffer-by-index $kak_count"
    fi
  }
}

# Title bar
define-command -hidden set-buffer-title %{
  refresh-buffers-info
  evaluate-commands %sh{
    if [ -z "$kak_client" ]; then
      exit
    fi

    # Build buffer list with indices
    list=""
    index=0
    active_mod="false"

    # Create temp file for processing
    seen_basenames=""
    duplicate_basenames=""

    # First pass: identify duplicates using pure shell
    eval "set -- $kak_quoted_opt_buffers_info"
    while [ "$1" ]; do
      name=${1%_*}
      # Extract basename using parameter expansion (no fork)
      bn="${name##*/}"

      # Check if we've seen this basename before
      case "$seen_basenames" in
        *"|$bn|"*)
          duplicate_basenames="$duplicate_basenames|$bn|"
          ;;
        *)
          seen_basenames="$seen_basenames|$bn|"
          ;;
      esac
      shift
    done

    # Second pass: build the title
    eval "set -- $kak_quoted_opt_buffers_info"
    while [ "$1" ]; do
      name=${1%_*}
      modified=${1##*_}
      index=$((index + 1))
      
      # Extract basename using parameter expansion
      bn="${name##*/}"

      # Check if this basename is a duplicate
      case "$duplicate_basenames" in
        *"|$bn|"*)
          # It's a duplicate, show parent/basename format
          # Extract parent directory name without forking
          dir="${name%/*}"
          parent="${dir##*/}"
          display_name="$parent/$bn"
          ;;
        *)
          # Not a duplicate, show just basename
          display_name="$bn"
          ;;
      esac

      # Format each buffer
      if [ "$name" = "$kak_bufname" ]; then
        # Active buffer with brackets
        if [ "$modified" = "true" ]; then
          cur="[ $index $display_name+ ]"
          active_mod="true"
        else
          cur="[ $index $display_name ]"
        fi
      else
        # Inactive buffer
        if [ "$modified" = "true" ]; then
          cur="$index $display_name+"
        else
          cur="$index $display_name"
        fi
      fi
      
      list="$list $cur"
      shift
    done
    
    if [ -n "$list" ]; then
      printf "set-option -add global ui_options 'terminal_title=%s'\n" "$list"
    fi
  }
}

hook global WinDisplay .* %{
    set-option global alt_bufname %opt{current_bufname}
    set-option global current_bufname %val{bufname}
    # set-buffer-title
}
