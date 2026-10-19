# Kakoune_find
declare-option -hidden str find_command fd
declare-option -hidden str-list find_args --hidden --type=file --exclude=.git --color=never
declare-option -hidden str find_completion %{ eval "$kak_quoted_opt_find_command" "$kak_quoted_opt_find_args" }

hook global BufCreate '\*find\*' %{
  set-option buffer filetype find
}

hook global BufSetOption filetype=find %{
  add-highlighter buffer/find ref find
  map -docstring 'jump to files' buffer normal <ret> ':jump_to_files<ret>'
  map -docstring 'jump to files and close find buffer' buffer normal <s-ret> ':jump_to_files_and_close_find_buffer<ret>'
}

add-highlighter shared/find regex '^(.+?)$' 0:value

define-command find -params .. %{
  evaluate-commands -save-regs '"' %{
    try %{
      execute-keys -buffer '*find*' -save-regs '' '%y'
    } catch %{
      set-register dquote
    }
    fifo -name '*find*' -- %opt{find_command} %opt{find_args} %arg{@}
    execute-keys -buffer '*find*' 'P'
  }
}

complete-command find file

define-command -hidden jump_to_files %{
  evaluate-commands -draft %{
    execute-keys 'x<a-s><a-K>^\n<ret>H'
    evaluate-commands -itersel %{
      evaluate-commands -client %val{client} -verbatim edit -existing -- %val{selection}
    }
  }
}

define-command -hidden jump_to_files_and_close_find_buffer %{
  jump_to_files
  delete-buffer '*find*'
}

define-command -hidden open_find_buffer_and_jump_to_files -params 1 %{
  buffer '*find*'
  execute-keys ",;%arg{1}gh"
  jump_to_files
}

define-command jump_to_next_file %{
  open_find_buffer_and_jump_to_files 'j'
}

define-command jump_to_previous_file %{
  open_find_buffer_and_jump_to_files 'k'
}

alias global fn jump_to_next_file
alias global fp jump_to_previous_file

# File Picker
declare-option str picker_interface %sh{
    if ! [[ -z "$TMUX" ]]; then
        echo sk --tmux center,75% --prompt
    elif command -v bemenu &>/dev/null; then
        echo bemenu -l '20 down' -P » -if --prompt
    fi
}

define-command -docstring 'buffer-picker: filter and jump to buffers' buffer-picker %{
    try %{
      buffer %sh{
        xargs -n1 <<< "$kak_quoted_buflist" | $kak_opt_picker_interface buffer
      }
    }
}

define-command -docstring 'file-picker: filter and jump to files' file-picker %{
    try %{
      edit -existing %sh{
        fd -t file | $kak_opt_picker_interface 'file relative to root: '
      }
    }
}

define-command -docstring 'file-picker-dir: filter and jump to files from the current directory' file-picker-dir %{
    try %{
      edit -existing %sh{
        fd -t file . $(dirname $kak_buffile) | $kak_opt_picker_interface 'file around buffer: '
      }
    }
}

define-command -hidden open_file_picker %{
	prompt open: -menu -shell-script-candidates %opt{find_completion} %{
        edit -existing -- %val{text}
	}
}

define-command -docstring 'buffer-picker: filter and jump to buffers' -hidden tmux-buffer-picker %{
  try %{
    buffer %sh{
      xargs -n1 <<< "$kak_quoted_buflist" | sk --prompt 'buffer: ' --tmux
    }
  }
}

define-command -docstring 'file-picker: filter and jump to files' -hidden tmux-file-picker %{
  try %{
    edit -existing %sh{
      fd -t file | sk --prompt 'file relative to root: ' --tmux
    }
  }
}

define-command -hidden file-picker-open-selections %{
  execute-keys <a-s>_
  evaluate-commands %sh{
    eval set -- "$kak_quoted_selections"
    for file in "$@"; do
      [ -f "$file" ] && printf "edit '%s'\n" "$file"
    done
  }
}

define-command -docstring 'file-picker: filter and jump to files from the current directory' swiper-file-picker %{
  edit -scratch '*file-picker*'

  try %{
    map buffer normal <ret> ': file-picker-open-selections<ret>'
    add-highlighter buffer/file-picker-item regex (.*) 1:cyan
  }

  swiper 'rg -i' '%|fd --hidden --type=file --exclude=.git --color=never<ret>gg'
}

# Modified File Picker
declare-option -hidden str git_status_command sh
declare-option -hidden str-list git_status_args -c %{ git status -z --no-renames -- "$@" | tr '\0' '\n' }
declare-option -hidden str git_status_completion %{ eval "$kak_quoted_opt_git_status_command" "$kak_quoted_opt_git_status_args" }
define-command -hidden open_changed_file_picker %{
  prompt open: -menu -shell-script-candidates %opt{git_status_completion} %{
    edit -existing -- %sh{ printf '%s' "$kak_text" | cut -c 4- }
  }
}

# Open Line Picker
define-command open_line_picker %{
  prompt line_picker: -menu -shell-script-candidates %{
    fifo=$(mktemp -u)
    mkfifo "$fifo"
    printf 'eval -client "%s" -verbatim write "%s"\n' "$kak_client" "$fifo" |
    kak -p "$kak_session"
    cat "$fifo"
    unlink "$fifo"
  } %{
    set-register / "^\Q%val{text}\E\n"
    execute-keys 'genvv'
  }
}

# gf find
define-command -hidden -docstring "goto-file <filename>: search for file recusively under path option: %opt{path}" goto-file -params 1 %{
  	evaluate-commands %sh{
        file=$1
        eval "set -- $kak_buflist"
        while [ $# -gt 0 ]; do            # Check if buffer with this
            if [ "$file" = "$1" ]; then   # file already exists. Basically
                printf "%s\n" "buffer $1" # emulating what edit command does
                exit
            fi
            shift
        done
        if [ -e "$file" ]; then                     # Test if file exists under
            printf "%s\n" "edit -existing %{$file}" # servers' working directory
            exit                                    # this is last resort until
        fi                                          # we start recursive searchimg

        # if everthing  above fails - search for file under path
        eval "set -- $kak_opt_path"
        while [ $# -gt 0 ]; do
            case $1 in                        # Since we want to check fewer places
                ./) path=${kak_buffile%/*} ;; # I've swapped ./ and %/ because
                %/) path=$PWD ;;              # %/ usually has smaller scope. So
                *)  path=$1 ;;                # this trick is a speedi-up hack.
            esac
            if [ -z "${file##*/*}" ]; then # test if filename contains path
                if [ -e "$path/$file" ]; then
                    printf "%s\n" "edit -existing %{$path/$file}"
                    exit
                fi
            else # build list of candidates or automatically select if only one found
                for candidate in $(find -L $path -mount -type f -name "$file"); do
                    if [ -n "$candidate" ]; then
                        candidates="$candidates %{$candidate} %{evaluate-commands %{edit -existing %{$candidate}}}"
                    fi
                done
                if [ -n "$candidates" ]; then
                    printf "%s\n" "menu -auto-single $candidates"
                    exit
                fi
            fi
            shift
        done
        printf "%s\n" "echo -markup %{{Error}unable to find file '$file'}"
		}
}
