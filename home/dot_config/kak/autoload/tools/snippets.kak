declare-option str-list snippets \
      "date" "date" "snippets-insert-date" \
      "uuid" "uuid" "snippets-insert-uuid"

define-command snippets-insert -params 1 %{
    evaluate-commands %sh{
        snippet_text="$1"

        # Convert $n to newlines
        converted=""
        while :; do
            case "$snippet_text" in
                *'$n'*)
                    before="${snippet_text%%'$n'*}"
                    converted="${converted}${before}
"
                    snippet_text="${snippet_text#*'$n'}"
                    ;;
                *)
                    converted="${converted}${snippet_text}"
                    break
                    ;;
            esac
        done

        escaped=$(printf '%s' "$converted" | sed "s/'/''/g")

        printf "execute-keys 'i <backspace>'\n"
        printf "evaluate-commands -draft -verbatim lsp-snippets-insert '%s'\n" "$escaped"
        printf "try lsp-snippets-select-next-placeholders\n"
    }
}

define-command snippets-expand-trigger %{
    evaluate-commands -save-regs 'st' %{
        evaluate-commands -draft %{
            execute-keys '<a-;><a-B><a-;>_'
            set-register t %val{selection}
            set-register s %val{selections_desc}
        }
        snippets-expand-by-trigger %reg{t} %reg{s}
    }
}

define-command snippets-expand-by-trigger -hidden -params 2 %{
    evaluate-commands %sh{
        trigger="$1"
        sel_desc="$2"

        eval set -- "$kak_quoted_opt_snippets"
        if [ $(($#%3)) -ne 0 ]; then
            printf "fail 'Invalid snippets option'"
            exit
        fi

        while [ $# -ne 0 ]; do
            if [ "$2" = "$trigger" ]; then
                printf "execute-keys '<esc>'\n"
                printf "select '%s'\n" "$sel_desc"
                printf "execute-keys 'd'\n"
                printf "%s\n" "$3"
                exit
            fi
            shift 3
        done
        printf "fail 'No snippet with trigger: %s'" "$trigger"
    }
}

define-command snippets -params 1 -shell-script-candidates %{
    eval set -- "$kak_quoted_opt_snippets"
    if [ $(($#%3)) -ne 0 ]; then exit; fi
    while [ $# -ne 0 ]; do
        printf '%s\n' "$1"
        shift 3
    done
} %{
    evaluate-commands %sh{
        name="$1"
        shift
        eval set -- "$kak_quoted_opt_snippets"
        if [ $(($#%3)) -ne 0 ]; then
            printf "fail 'Invalid snippets option'"
            exit
        fi

        while [ $# -ne 0 ]; do
            if [ "$1" = "$name" ]; then
                printf "%s\n" "$3"
                exit
            fi
            shift 3
        done
        printf "fail 'Snippet not found: %s'" "$name"
    }
}

define-command snippets-info %{
    info -title Snippets %sh{
        eval set -- "$kak_quoted_opt_snippets"
        if [ $(($#%3)) -ne 0 ]; then printf "Invalid 'snippets' value"; exit; fi
        if [ $# -eq 0 ]; then printf 'No snippets defined'; exit; fi
        maxtriglen=0
        while [ $# -ne 0 ]; do
            if [ ${#2} -gt $maxtriglen ]; then
                maxtriglen=${#2}
            fi
            shift 3
        done
        eval set -- "$kak_quoted_opt_snippets"
        while [ $# -ne 0 ]; do
            if [ $maxtriglen -eq 0 ]; then
                printf '%s\n' "$1"
            else
                if [ "$2" = "" ]; then
                    printf "%${maxtriglen}s   %s\n" "" "$1"
                else
                    printf "%${maxtriglen}s ➡ %s\n" "$2" "$1"
                fi
            fi
            shift 3
        done
    }
}

define-command snippets-menu %{
    evaluate-commands %sh{
        eval set -- "$kak_quoted_opt_snippets"
        if [ $# -eq 0 ]; then
            printf 'fail "No snippets defined"'
            exit
        fi
        if [ $(($#%3)) -ne 0 ]; then
            printf 'fail "Invalid snippets option"'
            exit
        fi
        printf 'menu'
        while [ $# -ne 0 ]; do
            name="$1"
            display=$(printf '%s' "$name" | sed "s/'/''/g")
            printf " '%s' 'snippets %s'" "$display" "$display"
            shift 3
        done
    }
}

define-command -hidden snippets-insert-date %{
    evaluate-commands %sh{
        current_date=$(date +%Y-%m-%d)
        escaped=$(printf '%s' "$current_date" | sed "s/'/''/g")
        printf "snippets-insert '%s'\n" "$escaped"
    }
}

define-command -hidden snippets-insert-uuid %{
    evaluate-commands %sh{
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
        escaped=$(printf '%s' "$uuid" | sed "s/'/''/g")
        printf "snippets-insert '%s'\n" "$escaped"
    }
}
