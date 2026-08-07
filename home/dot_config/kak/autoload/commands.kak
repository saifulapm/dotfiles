define-command -override -hidden true nop
define-command -override -hidden false fail

# ------------------------
# Mkdir
# ------------------------
define-command mkdir %{ nop %sh{ mkdir -p $(dirname $kak_buffile) } }

# ------------------------
# Path
# ------------------------
define-command path -docstring 'Echo and copy current file path to clipboard' %{
  evaluate-commands %sh{
    printf '%s' "$kak_buffile" | pbcopy 2>/dev/null || printf '%s' "$kak_buffile" | wl-copy 2>/dev/null
    echo "echo -markup '{Information}$kak_buffile'"
  }
}

# ------------------------
# Code Sharing
# ------------------------
define-command pastebin -docstring 'Upload selection to termbin.com' %{
    evaluate-commands %sh{
        url=$(printf '%s' "$kak_selection" | nc termbin.com 9999)

        if [ -n "$url" ]; then
            printf '%s' "$url" | pbcopy 2>/dev/null || printf '%s' "$url" | wl-copy 2>/dev/null
            echo "echo -markup '{Information}Copied $url to clipboard!'"
        else
            echo "echo -markup '{Error}Upload failed'"
        fi
    }
}

# ------------------------
# Diff Utils
# ------------------------
declare-option -hidden str find_command fd
declare-option -hidden str-list find_args --hidden --type=file --exclude=.git --color=never
declare-option -hidden str find_completion %{ eval "$kak_quoted_opt_find_command" "$kak_quoted_opt_find_args" }

define-command diff -docstring 'diff [<arguments>]: Generate a diff' -shell-script-candidates %opt{find_completion} -params 1.. %{
    fifo -name diff -- diff -u %arg{@}; set buffer filetype diff;
}

define-command difft -docstring 'difft [<arguments>]: Diff with difftastic' -shell-script-candidates %opt{find_completion} -params 1.. %{
    fifo -name diff -- difft --width %val{window_width} --color always %arg{@};
}

define-command diffd -docstring 'delta [<arguments>]: Diff with Delta' -shell-script-candidates %opt{find_completion} -params 1.. %{
    fifo -name diff -- delta %arg{@};
}

# ------------------------
# Common Apps
# ------------------------
define-command bun -docstring 'bun [<arguments>]: bun utility wrapper' -params 1.. %{
  fifo -name "'bun %arg{@}'" -scroll -- bun %arg{@}
}

define-command bat -docstring 'bat [<files>]: bat utility wrapper' -params 0.. %{
  	evaluate-commands %sh{
        if [ $# -eq 0 ]; then
          echo "fifo -name \"'bat %val{buffile}'\" -- bat --style=plain --color=always %val{buffile}"
        else
          echo "fifo -name \"'bat %arg{@}'\" -- bat --style=plain --color=always %arg{@}"
        fi
    }
}

define-command npm -docstring 'npm [<arguments>]: npm utility wrapper' -params 1.. %{
  fifo -name "'npm %arg{@}'" -scroll -- npm %arg{@}
}

define-command pnpm -docstring 'pnpm [<arguments>]: pnpm utility wrapper' -params 1.. %{
  evaluate-commands %sh{
    if [ "$1" = "run" ]; then
      shift
      printf "fifo -name '*pnpm*' -scroll -- pnpm run --color %s\n" "$*" "$*"
    else
      printf "fifo -name '*pnpm*' -scroll -- pnpm %s\n" "$*" "$*"
    fi
  }
}
alias global p pnpm

define-command flutter -docstring 'flutter [<arguments>]: flutter utility wrapper' -params 1.. %{
  fifo -name "'flutter %arg{@}'" -scroll -- flutter %arg{@}
}

define-command npx -docstring 'npx [<arguments>]: npx utility wrapper' -params 1.. %{
  fifo -name "'npx %arg{@}'" -scroll -- npx %arg{@}
}

define-command copilot -docstring 'Start copilot api' %{
  fifo -name "*copilot*" -scroll -- npx copilot-api@latest start
}

define-command dev -docstring 'Cloudflared dev tunnel' %{
  evaluate-commands %sh{
    printf "fifo -name '*cloudflared*' -scroll -- cloudflared tunnel --config '%s/.cloudflared/config.dev.yaml' run dev\n" "$HOME"
  }
}

define-command hurl -docstring 'hurl [<arguments>]: Hurl, run and test HTTP requests with plain text.' -params 0.. %{
	evaluate-commands %sh{
      if [ $# -eq 0 ]; then
        echo "fifo -name 'hurl' -scroll -- hurl --color %val{buffile}"
      else
        echo "fifo -name 'hurl' -scroll -- hurl %arg{@}"
      fi
  }
}

define-command artisan -docstring 'artisan [<arguments>]: Laravel artisan utility' -params 1.. %{
  evaluate-commands %sh{
    if [ "$1" = "tinker" ]; then
      printf 'popup --title tinker -- php artisan tinker'
    else
      printf "fifo -name \"'php artisan %s'\" -scroll -- php artisan --ansi %s" "$*" "$*"
    fi
  }
}

complete-command -menu artisan shell-script-candidates %{
  if [ $kak_token_to_complete -eq 0 ]; then
    php artisan list --format=json | jq -r '.commands[].name'
  fi
}
alias global a artisan


define-command composer -docstring 'composer [<arguments>]: Composer utility wrapper' -params 1.. %{
  fifo -name "composer %arg{@}" -scroll -- composer --ansi %arg{@}
}

complete-command -menu composer shell-script-candidates %{
  if [ $kak_token_to_complete -eq 0 ]; then
    composer list --format=json | jq -r '.commands[].name'
  fi
}

# ------------------------
# Select View
# ------------------------
declare-option -hidden str _scrolloff
define-command select-view -docstring 'select visible part of buffer' %{
  set-option window _scrolloff %opt{scrolloff}
  set-option window scrolloff 0,0

  execute-keys gtGbGl

  hook window -once NormalKey .* %{
    set-option window scrolloff %opt{_scrolloff}
  }
}

# ------------------------
# Utilities
# ------------------------
define-command save-macro-as -docstring 'save-macro-as <command-name>: define-command with macro register' -params 1 %{
  define-command %arg{1} -override %{ execute-keys "%reg{@}" }
}

define-command seq -docstring 'seq: <start?> <inc?> insert numbered output to cursors' -params 0.. %{
  evaluate-commands %sh{
    start=1; increment=1;
    if [ $# -eq 1 ]; then start=$1; fi
    if [ $# -eq 2 ]; then increment=$2; fi
    end=$(( $start + $kak_selection_count ))
    echo "
      edit -scratch
      execute-keys '!seq -w $start $increment $end <ret>'
      execute-keys '<a-s>_y:db<ret>P'
    "
  }
}

define-command tldr -docstring 'tldr <command>: Cheatsheet for the given command' -shell-completion -params 0.. %{
  evaluate-commands %sh{
    if [ $# -eq 0 ]; then
      echo "fifo -name tldr -- tldr --compact --color=always %val{selection}"
    else
      echo "fifo -name tldr -- tldr --compact --color=always %arg{@}"
    fi
  }
}

define-command watchexec -docstring 'watchexec [<args>] <command>: execute the given command when the current directory changes' -shell-completion -params 0.. %{
  fifo -scroll -- watchexec %arg{@}
}

define-command watchthis -docstring 'watchexec [<args>] <command>: execute the given command when the current file changes' -shell-completion -params 0.. %{
  fifo -scroll -- watchexec --watch %val{buffile} %arg{@}
}

define-command xargs -docstring '
  xargs [<arguments>]: xargs utility wrapper
  execute a command with each selection, selections are represented with {} as a placeholder
' %{
  prompt 'command:' %{
    execute-keys "| xargs -J {} %val{text} <ret>"
  }
}

define-command rustywind -override %{ execute-keys -draft '%|rustywind --stdin <ret>' }
define-command minify -override %{ execute-keys '%|minhtml <ret>%' }

define-command -docstring %{
    shell-command [switches] <args>: Run the given shell command. Display
    its output in an info modal.
    Switches:
        -d  echo stdout to *debug* buffer as well
} -params 1.. shell-command %{
	evaluate-commands %sh{
        if [ "$1" =	"-d" ];	then
        	debug="true"
        	shift
        fi
        stdout="$(eval "$@")"
        printf 'info -title	sh "%s"\n' "$stdout"
        if [ "$debug" = "true" ]; then
        	printf 'echo -debug	-- "%s"\n' "$stdout"
        fi
	}
}
define-command -docstring %{
    shell-async-command [switches] <args>: Run the given shell command
    asynchronously. Display its output in an info modal.
    Switches:
        -d  echo stdout to *debug* buffer as well
} -params 1.. shell-async-command %{
    nop %sh{
        {
            if [ "$1" = "-d" ]; then
                debug="true"
                shift
            fi
            stdout="$(eval "$@")"
            cmd="$(printf 'info -title sh "%s"\n' "$stdout")"
            if [ "$debug" = "true" ]; then
                dcmd="$(printf 'echo -debug "%s"\n' "$stdout")"
                cmd="$(printf '%s\n%s' "$cmd" "$dcmd")"
            fi
            printf 'evaluate-commands -try-client %s %%{ %s }' "$kak_client" "$cmd" | kak -p "$kak_session"
        } >/dev/null 2>&1 </dev/null &
    }
}

alias global sh  shell-command
alias global sh& shell-async-command

# ------------------------
# Clipboard
# -----------------------
declare-option str extra_yank_system_clipboard_cmd %sh{ test "$(uname)" = "Darwin" && echo 'pbcopy' || echo 'wl-copy' }
declare-option str extra_paste_system_clipboard_cmd %sh{ test "$(uname)" = "Darwin" && echo 'pbpaste' || echo 'wl-paste' }

define-command extra-yank-system -docstring 'yank into the system clipboard' %{
  execute-keys -draft "<a-|>%opt{extra_yank_system_clipboard_cmd}<ret>"
	echo "Copied to clipboard"
}

define-command extra-paste-system -docstring 'paste from the system clipboard' %{
  execute-keys -draft "<a-!>%opt{extra_paste_system_clipboard_cmd}<ret>"
}

# -------------------------
# Open URL
# -------------------------
declare-option str url_open_cmd 'open %s'
define-command -docstring "Open the URL the cursor is on with url_open_cmd." url-open %{
    evaluate-commands -save-regs 'ab' %{
        set-register b 'https?://(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)'
        try %{
            try %{
                execute-keys -draft '<a-a><a-w>s<c-r>b<ret>"ay'
            } catch %{
                fail 'No URL found!'
            }
            evaluate-commands %sh{
                # strip trailing punctuation
                clean_url="$(echo "$kak_reg_a" | sed 's/[][(){}.,;!?]*$//')"
                if eval "$(printf "$kak_opt_url_open_cmd" "$clean_url")" >/dev/null 2>&1; then
                    echo "info -title 'URL Opened' '$clean_url'"
                else
                    echo "fail 'url_open_cmd failed!'"
                fi
            }
        } catch %{
            info -title 'URL Open' "Couldn't open URL: %val{error}"
        }
    }
}

# ---------------------------
# Docs Helpers
# ---------------------------
define-command docs -docstring 'docs <docset> <args> : search for an api within a dedoc docset' -params 1.. %{
  popup --title dedoc --kak-script 'fifo -name docs -- printf %opt{popup_output}' -- docs %arg{@}
}

complete-command docs shell-script-candidates %{
  if [ $kak_token_to_complete = 0 ]; then
    dedoc ls -ln | awk -v ft="$kak_opt_filetype" '
      {
        if ($1 ~ ft)
          a[NR] = $1
        else
          b[NR] = $1
      }
      END {
        for (i in a)
          print a[i]
        for (i in b)
          print b[i]
      }'
  elif [ $kak_token_to_complete = 1 ]; then
    dedoc ss -i --porcelain "$1"
  fi
}

define-command grep_doc -params 1 -docstring 'grep doc' %{
  grep %arg{1} "%val{runtime}/doc"
}

complete-command grep_doc shell-script-candidates %{
  find -L "$kak_config/doc" "$kak_runtime/doc" -type f '(' -name '*.asciidoc' -or -name '*.md' ')' -exec grep -o -h -w '[[:alpha:]][[:alnum:]_-]\+' -- {} + | sort -u
}


# ----------------------------
# Config Helper
# ----------------------------
define-command open_config -params 1 -docstring 'open config' %{
  edit -existing -readonly %arg{1}
}

complete-command -menu open_config shell-script-candidates %{
  find -L "$kak_config/kakrc" -type f -name 'kakrc'
  find -L "$kak_config/autoload" -type f -name '*.kak'
}

alias global config open_config

define-command grep_config -params 1 -docstring 'grep config' %{
  grep %arg{1} "%val{config}/kakrc" "%val{config}/autoload"
}

complete-command grep_config shell-script-candidates %{
  {
    find -L "$kak_config/kakrc" -type f -name 'kakrc'
    find -L "$kak_config/autoload" -type f -name '*.kak'
  } |
  xargs grep -o -h -w '[[:alpha:]][[:alnum:]_-]\+' -- |
  sort -u
}

define-command explore_config %{
  explore %val{config}
}

# ----------------------------
# Explorer
# ---------------------------
define-command explore -params 0..1 %{
  evaluate-commands %sh{
    case "$#" in
      1)
        echo 'ls %arg{1}'
        break
        ;;
      0)
        echo 'ls %sh{dirname "$kak_buffile"}'
        break
        ;;
    esac
  }
}
complete-command explore file

define-command yazi -docstring "File manager with yazi in popup" -params .. %{
    popup --title yazi \
        --kak-script %{ 
            evaluate-commands %sh{
                if [ -n "$kak_opt_popup_output" ]; then
                    while IFS= read -r file; do
                        printf "edit '%s'\n" "$file"
                    done <<< "$kak_opt_popup_output"
                fi
            }
        } \
        -- yazi --chooser-file=/dev/stdout %arg{@}
}

define-command lf -docstring "File manager with lf in popup" -params .. %{
    popup --title lf \
        --kak-script %{ 
            evaluate-commands %sh{
                if [ -n "$kak_opt_popup_output" ]; then
                    while IFS= read -r file; do
                        printf "edit '%s'\n" "$file"
                    done <<< "$kak_opt_popup_output"
                fi
            }
        } \
        -- lf -print-selection %arg{@}
}


define-command sk -docstring "Find a file to open with sk" -params .. %{
    popup --title open --kak-script %{
        evaluate-commands %sh{
            while IFS= read -r file; do
                [ -f "$file" ] && printf "edit '%s'\n" "$file"
            done <<< "$kak_opt_popup_output"
        }
    } -- sk -c "fd --type f --hidden --exclude .git" -m --preview "bat -pp --color=always {}"
}

define-command sk-live-grep -docstring "Live grep with sk and jump to line" -params .. %{
    popup --title open --kak-script %{
        evaluate-commands %sh{
            while IFS= read -r match; do
                file=$(printf '%s' "$match" | cut -d: -f1)
                line=$(printf '%s' "$match" | cut -d: -f2)
                if [ -f "$file" ] && [ -n "$line" ]; then
                    printf "edit '%s' %s\n" "$file" "$line"
                fi
            done <<< "$kak_opt_popup_output"
        }
    } -- sk -m --ansi -i -c 'rg --color=always --line-number "{}"'
}

define-command fzf -docstring "Find a file to open with sk" -params .. %{
    popup --title open --kak-script %{edit %opt{popup_output}} -- fzf --preview "bat -pp --color=always {}"
}

define-command zf -docstring "Find a file to open with sk" -params .. %{
    popup --title open --kak-script %{
        evaluate-commands %sh{
            while IFS= read -r file; do
                printf "edit '%s'\n" "$file"
            done <<< "$kak_opt_popup_output"
        }
    } -- sh -c 'fd --hidden --type=file --exclude=.git | zf --height "$kak_window_height" --preview "bat -pp {}"'
}

define-command lazygit -docstring 'Lazygit wrapper' %{
  popup --title lazygit -- lazygit
}

define-command gitui -docstring 'Gitui wrapper' %{
  popup --title gitui -- gitui
}

# ----------------------------
# File Utils
# ---------------------------
define-command -docstring %{
    move-file <name>: move the file on the filesystem and the open buffer.
} -params 1 move-file %{
    evaluate-commands %sh{
        old="$kak_buffile"
        printf "rename-buffer '%s'\n" "$1"
        printf "write\n"
        printf "nop %%sh{ rm '%s' }\n" "$old"
    }
}
alias global mv move-file

define-command -docstring %{
    rename-file <name>: rename the file on filesystem and buffer,
    keeping the same directory.
} -params 1 rename-file %{
    evaluate-commands %sh{
        dir="${kak_buffile%/*}"
        old="$kak_buffile"
        new="${dir}/$1"
        printf "rename-buffer '%s'\n" "$new"
        printf "write\n"
        printf "nop %%sh{ rm '%s' }\n" "$old"
    }
}
alias global rf rename-file

define-command -docstring %{
    remove-file [<switches>] [<name>]: remove the file from the filesystem
    and close the buffer. Omit <name> to remove the current file.
    Switches:
        -f  remove even if buffer has unsaved changes

} -params 0..2 remove-file %{
    evaluate-commands %sh{
        if [ "$1" = "-f" ]; then
            force="true"
            shift
        fi
        if [ -z "$1" ]; then
            targ="$kak_buffile"
            targ_bname="$kak_bufname"
        else
            targ="$(realpath ${1})"
            targ_bname="$1"
        fi
        if [ "$kak_modified" = "true" ]; then
            if [ "$force" != "true" ]; then
                echo "fail 'Refusing to remove modified buffer without -f switch.'"
            else
                echo "try %{ delete-buffer! $targ_bname }" >$kak_command_fifo
                rm "$targ"
            fi
        else
            echo "try %{ delete-buffer $targ_bname }" >$kak_command_fifo
            rm "$targ"
        fi
    }
}
alias global rm remove-file
complete-command remove-file file

define-command cp -params 1 %{
  write -- %arg{1}
  edit -- %arg{1}
}

define-command cp_f -params 1 %{
  write! -- %arg{1}
  edit! -- %arg{1}
}

complete-command cp file
complete-command cp_f file
alias global cp! cp_f

define-command pwd %{
  echo -markup "{Information}%sh{pwd}"
}

# -------------------------
# Sudo Write
# -------------------------
define-command sudo-write %{
  prompt -password password: %{
    sudo_write %val{text}
  }
}

define-command -hidden sudo_write -params 1 %{
  evaluate-commands %sh{
    echo "$1" | sudo -S -b dd "if=$kak_response_fifo" "of=$kak_buffile" &&
    echo "write $kak_quoted_response_fifo" > "$kak_command_fifo" ||
    echo "fail 'sudo write failed'"
  }
}

# -------------------------
# Some extra utils commands
# -------------------------
define-command wrap-toggle -docstring 'Toggle word wrap for current window' %{
  try %{
    add-highlighter window/wrap wrap -word -indent
    echo 'Word wrap enabled'
  } catch %{
    remove-highlighter window/wrap
    echo 'Word wrap disabled'
  }
}

define-command toggle_readonly_flag %{
  set-option buffer readonly %sh{
    if [ "$kak_opt_readonly" = true ]; then
      printf false
    else
      printf true
    fi
  }
}

define-command insert_buffer_contents -params 1 %{
  evaluate-commands -save-regs '"' %{
    evaluate-commands -buffer %arg{1} %{
      execute-keys -save-regs '' '%y'
    }
    execute-keys 'p'
  }
}

complete-command insert_buffer_contents buffer
alias global r insert_buffer_contents

define-command reload_selected_commands %{
  echo -to-shell-script "sed 's/define-command /define-command -override /g' | kak -p %val{session}" -- %val{selections}
}

define-command show_character_info %{
  evaluate-commands -draft %{
    execute-keys ',;'
    evaluate-commands -client %val{client} -verbatim echo -markup %sh{
      printf '{Information}"%s" (U+%04x) Dec %d Hex %02x\n' "$kak_selection" "$kak_cursor_char_value" "$kak_cursor_char_value" "$kak_cursor_char_value"
    }
  }
}
alias global char show_character_info

define-command erase_characters_before_cursor_to_line_begin %{
  evaluate-commands -draft %{
    execute-keys '<a-h>'
    evaluate-commands -draft -itersel -verbatim -- try %{
      execute-keys '<a-k>^.\z<ret>'
    } catch %{
      execute-keys '<a-k>^\h+.\z<ret><a-:>Hd'
    } catch %{
      execute-keys '<a-k>^\h+\H<ret>WL<a-:>Hd'
    } catch %{
      execute-keys '<a-:>Hd'
    } catch %{}
  }
  execute-keys '<a-;><a-:><a-;><a-;>'
}

define-command erase_word_before_cursor %{
  evaluate-commands -draft %{
    execute-keys ';<a-_>'
    evaluate-commands -draft -itersel -verbatim -- try %{
      execute-keys -draft '<a-k>^.\z<ret>'
    } catch %{
      execute-keys -draft 'h<a-k>^.\z<ret>d'
    } catch %{
      execute-keys -draft 'h<a-k>\b\w|\B[^\w\h]<ret>d'
    } catch %{
      execute-keys -draft 'hBd'
    } catch %{}
  }
}

define-command convert_selected_text_to_ascii %{
  execute-keys '|iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE<ret>'
}

# Goto Line
define-command open_goto_line_prompt %{
  prompt goto_line: %{
    goto_lines_from_text %val{text}
  } -on-change %exp{
    try %%{
      goto_lines_from_text %%val{text}
    } catch %%{
      select -timestamp %val{timestamp} %val{selections_desc}
    }
  } -on-abort %exp{
    select -timestamp %val{timestamp} %val{selections_desc}
  }
}

define-command -hidden goto_lines_from_text -params 1 %{
  evaluate-commands %sh{
    selections_desc=
    IFS=','
    for cursor_line in $1
    do
      if [ "$cursor_line" -eq "$cursor_line" ]
      then
        selections_desc="$cursor_line.1,$cursor_line.1 $selections_desc"
      else
        echo 'fail "cannot parse text as a list of integers: %arg{1}"'
        exit 1
      fi
    done
    echo "select $selections_desc"
  }
}

define-command move_selected_lines_down %{
  execute-keys -draft 'x<a-_><a-:>Z;ezjxdzP'
}

define-command move_selected_lines_up %{
  execute-keys -draft 'x<a-_><a-:><a-;>Z;bzkxdzp'
}

define-command -hidden increment_selected_numbers -params 1 %{
  execute-keys "a+%sh{expr $1 '|' 1}<esc>|{ cat; echo; } | bc<ret>"
}

define-command -hidden decrement_selected_numbers -params 1 %{
  execute-keys "a-%sh{expr $1 '|' 1}<esc>|{ cat; echo; } | bc<ret>"
}

define-command snippets-or-emmet-expand %{
    try %{
        snippets-expand-trigger
    } catch %{
        try %{
            lsp-snippets-select-next-placeholders
        } catch %{
            emmet-expand
        }
    }
}

define-command select_highlights %{
  execute-keys -save-regs 'ab' '"aZ*%s<ret>"bZ"az"b<a-z>a'
}

# ------------------------
# Syms - Project Symbol Search
# ------------------------
declare-option -hidden str syms_cache_file
declare-option -hidden str syms_preview_text
declare-option -hidden str syms_preview_lang
declare-option -hidden str syms_preview_title

define-command syms -docstring 'syms [flags]: search symbols with tree-sitter
Flags: -buffer, -kind <kind>, -exported
Kinds: fn, method, class, struct, enum, type, interface, const, mod, trait, component, hook, test' -params 0.. %{
  evaluate-commands %sh{
    target="."
    kind=""
    exported=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -buffer) target="$kak_buffile" ;;
        -kind) shift; kind="$1" ;;
        -exported) exported="--exported" ;;
      esac
      shift
    done

    cache=$(mktemp "${TMPDIR:-/tmp}/syms-kak.XXXXXX")
    syms ${kind:+--kind "$kind"} $exported "$target" 2>/dev/null > "$cache"
    printf "set-option window syms_cache_file '%s'\n" "$cache"
  }
  syms-prompt
}

define-command -hidden syms-prompt %{
  prompt 'symbol: ' -shell-script-candidates %{
    # Extract just qualified names from cached output (last word of field1)
    awk -F'\t' '{ n = split($1, a, " "); print a[n] }' "$kak_opt_syms_cache_file"
  } -on-change %{
    evaluate-commands %sh{
      name="$kak_text"
      [ -z "$name" ] && exit 0

      # Look up the selected name in the cache (match as last word of field1)
      match=$(awk -F'\t' -v name="$name" '{ n = split($1, a, " "); if (a[n] == name) { print; exit } }' "$kak_opt_syms_cache_file")
      [ -z "$match" ] && exit 0

      # Parse location field (field2): file:line:end_line:col
      location=$(printf '%s' "$match" | cut -f2)
      IFS=: read -r file start end col <<< "$location"
      [ -z "$file" ] || [ -z "$start" ] || [ -z "$end" ] && exit 0
      [ ! -f "$file" ] && exit 0

      # Extract the full symbol body using tree-sitter range
      preview=$(sed -n "${start},${end}p" "$file" 2>/dev/null | head -40)
      [ -z "$preview" ] && exit 0

      # Build info title from metadata (kind + file:line)
      sig=$(printf '%s' "$match" | cut -f1 | sed 's/^[^ ]* *//' | sed 's/ *\[.*\] *//')
      title="${sig} — ${file}:${start}"

      # Get language from syms output (first field, first word)
      lang=$(printf '%s' "$match" | cut -f1 | awk '{ print $1 }')

      # Set options safely using heredoc-style escaping
      preview_escaped=$(printf '%s' "$preview" | sed "s/'/''/g")
      title_escaped=$(printf '%s' "$title" | sed "s/'/''/g")
      printf "set-option window syms_preview_text '%s'\n" "$preview_escaped"
      printf "set-option window syms_preview_lang '%s'\n" "$lang"
      printf "set-option window syms_preview_title '%s'\n" "$title_escaped"
      echo "syms-show-preview"
    }
  } -on-abort %{
    nop %sh{ rm -f "$kak_opt_syms_cache_file" }
  } %{
    evaluate-commands %sh{
      name="$kak_text"
      [ -z "$name" ] && { rm -f "$kak_opt_syms_cache_file"; exit 0; }

      # Look up the name in cache
      match=$(awk -F'\t' -v name="$name" '{ n = split($1, a, " "); if (a[n] == name) { print; exit } }' "$kak_opt_syms_cache_file")
      rm -f "$kak_opt_syms_cache_file"
      [ -z "$match" ] && exit 0

      # Parse location
      location=$(printf '%s' "$match" | cut -f2)
      IFS=: read -r file line end_line col <<< "$location"
      [ -z "$file" ] || [ -z "$line" ] && exit 0

      # Resolve relative paths
      case "$file" in /*) ;; *) file="$(pwd)/$file" ;; esac
      file=$(printf '%s' "$file" | sed "s/'/''/g")
      printf "edit -existing '%s' %s %s" "$file" "$line" "$col"
    }
  }
}

define-command -hidden syms-show-preview %{
  # The `php` tree-sitter grammar parses full PHP files and expects a leading
  # `<?php` tag. Symbol previews are raw PHP snippets, so prepend one before
  # highlighting — the extra line is visible in the info box but the rest of
  # the code gets highlighted correctly.
  evaluate-commands %sh{
    if [ "$kak_opt_syms_preview_lang" = "php" ]; then
      escaped=$(printf '<?php\n%s' "$kak_opt_syms_preview_text" | sed "s/'/''/g")
      printf "set-option window syms_preview_text '%s'\n" "$escaped"
    fi
  }
  try %{
    tree-sitter-highlight %opt{syms_preview_lang} %opt{syms_preview_text}
    info -markup -title %opt{syms_preview_title} %opt{tree_sitter_markup}
  } catch %{
    info -title %opt{syms_preview_title} -- %opt{syms_preview_text}
  }
}

complete-command -menu syms shell-script-candidates %{
  prev=""
  i=1
  while [ "$i" -lt "$kak_token_to_complete" ]; do
    eval "prev=\${$i}"
    i=$((i + 1))
  done
  if [ "$prev" = "-kind" ]; then
    printf '%s\n' fn method class struct enum type interface const mod trait component hook test
  else
    printf '%s\n' -buffer -kind -exported
  fi
}
