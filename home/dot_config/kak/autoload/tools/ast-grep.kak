declare-option -hidden str last_sg_command
declare-option -hidden int sg_jump_current_line 0

define-command -params 1..4 -docstring %{
    sg <pattern> [<rewrite>] [<path>] [<filetype>]: Search and rewrite code using AST patterns

    pattern (required): AST pattern to search for
    rewrite (optional): replacement pattern
    path (optional): directory to search in (default: current directory)
    filetype (optional): file extension filter (e.g., js, py, ts)

    Examples:
        sg 'console.log($A)'                    # Search only
        sg 'console.log($A)' ''                 # Remove console.log
        sg 'var $A' 'let $A' ./src js          # Replace var with let in js files under src/
} sg %{
    evaluate-commands -save-regs prtf %{
        set-register p %arg{1}                  # pattern
        set-register r %arg{2}                  # rewrite (can be empty)
        set-register t %arg{3}                  # path (can be empty)
        set-register f %arg{4}                  # filetype (can be empty)

        evaluate-commands %sh{
            pattern="$1"
            rewrite="$2"
            path="${3:-.}"                      # default to current directory
            filetype="$4"

            # Build sg command based on provided arguments
            cmd="sg --color=ansi --heading=always --pattern '$pattern'"

            if [ -n "$rewrite" ]; then
                cmd="$cmd --rewrite '$rewrite'"
            fi

            if [ -n "$filetype" ]; then
                cmd="$cmd --lang '$filetype'"
            fi

            # Add path at the end
            cmd="$cmd '$path'"

            printf 'sg-execute-command %%{%s}' "$cmd"
        }
    }
}

define-command sg-write -docstring "Apply sg rewrite changes to all files" %{
    nop %sh{eval "$kak_opt_last_sg_command" --update-all 2>&1}
}

define-command -hidden sg-execute-command -params 1 %{
    evaluate-commands -try-client %opt{toolsclient} %{
        fifo -name *sg-grep* -scroll -script %{
            trap - INT QUIT

            # Check if sg command exists
            if ! command -v sg >/dev/null 2>&1; then
                echo "Error: 'sg' command not found. Please install ast-grep or ensure it's in your PATH."
                exit 1
            fi

            # Execute the sg command with proper error handling
            eval "$1" 2>&1 || echo "Command failed: $1"
        } -- %arg{@}
        set-option buffer filetype sg-grep
        set-option buffer sg_jump_current_line 0
        set-option window last_sg_command "%arg{@}"
    }
}

hook -group ast-grep-highlight global WinSetOption filetype=sg-grep %{
    add-highlighter window/sg-grep group
    add-highlighter window/sg-grep/ regex "[│]" 0:comment
    add-highlighter window/sg-grep/ line %{%opt{sg_jump_current_line}} default+b
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/sg-grep }
}

hook global WinSetOption filetype=sg-grep %{
    hook buffer -group sg-grep-hooks NormalKey <ret> sg-jump
    hook -once -always window WinSetOption filetype=.* %{ remove-hooks buffer sg-grep-hooks }
}

define-command -hidden sg-jump %{
    evaluate-commands -save-regs abc %{
        try %{
            try %{
                evaluate-commands -draft %{
                    execute-keys ',xs^(\d+)<ret>'
                    set-register b %reg{1}
                }
            }
            evaluate-commands -draft %{
                execute-keys ',<a-i>ps^([^:\n\d\s@]+)<ret>'
                set-register a %reg{1}
            }

            set-register c %sh{
                if [ -n "$kak_reg_b" ]; then
                    # If line number exists, filter by both file and line
                    result=$(eval sg run "$kak_opt_last_sg_command" --json=pretty | \
                    jq -r --arg file "$kak_reg_a" --argjson line "$kak_reg_b" \
                    '.[] | .range.start.line += 1 | .range.end.line += 1 | 
                    select(.file == $file and .range.start.line <= $line and .range.end.line >= $line) | 
                    "\(.range.end.line).\(.range.end.column + 1),\(.range.start.line).\(.range.start.column + 1)"' | \
                    head -n 1)

                    # If no result found, fallback to current line position
                    if [ -z "$result" ]; then
                        printf "%d.1,%d.1" "$kak_reg_b" "$kak_reg_b"
                    else
                        printf "%s" "$result"
                    fi
                else
                    # If no line number, get first selection for the file
                    result=$(eval sg run "$kak_opt_last_sg_command" --json=pretty | \
                    jq -r --arg file "$kak_reg_a" \
                    '.[] | .range.start.line += 1 | .range.end.line += 1 | 
                    select(.file == $file) | 
                    "\(.range.end.line).\(.range.end.column + 1),\(.range.start.line).\(.range.start.column + 1)"' | \
                    head -n 1)

                    # If no result found, fallback to line 1
                    if [ -z "$result" ]; then
                        printf "1.1,1.1"
                    else
                        printf "%s" "$result"
                    fi
                fi
            }

            set-option buffer sg_jump_current_line %val{cursor_line}
            evaluate-commands -try-client %opt{jumpclient} -verbatim -- edit -existing -- %reg{a}
            echo -debug %reg{a} %reg{b} %reg{c}
            try %{ focus %opt{jumpclient} }
            try %{
            	select %reg{c}
                execute-keys 'vv'
        	}
        }
    }
}

define-command -hidden sg-jump-select-next %{
    execute-keys ge %opt{sg_jump_current_line}g<a-l> /^(\d+)<ret>
}

define-command sg-jump-next -params 1.. -docstring %{
    sg-jump-next <bufname>: jump to next location listed in the given *sg-grep*-like location list buffer.
} %{
    evaluate-commands -try-client %opt{jumpclient} -save-regs / %{
        buffer %arg{@}
        sg-jump-select-next
        sg-jump
    }
    try %{
        evaluate-commands -client %opt{toolsclient} %{
            buffer %arg{@}
            execute-keys gg %opt{sg_jump_current_line}g
        }
    }
}

define-command sg-jump-previous -params 1.. -docstring %{
    sg-jump-previous <bufname>: jump to previous location listed in the given *sg-grep*-like location list buffer.
} %{
    evaluate-commands -try-client %opt{jumpclient} -save-regs / %{
        buffer %arg{@}
        sg-jump-select-previous
        sg-jump
    }
    try %{
        evaluate-commands -client %opt{toolsclient} %{
            buffer %arg{@}
            execute-keys gg %opt{sg_jump_current_line}g
        }
    }
}

define-command -hidden sg-jump-select-previous %{
    execute-keys ge %opt{sg_jump_current_line}g<a-h> <a-/>^(\d+)<ret>
}

define-command sg-grep-next-match -docstring %{alias for "jump-next *sg-grep*"} %{
    sg-jump-next -matching \*sg-grep(-.*)?\*
}

define-command sg-grep-previous-match -docstring %{alias for "jump-previous *sg-grep*"} %{
    sg-jump-previous -matching \*sg-grep(-.*)?\*
}

complete-command sg-jump-next buffer
complete-command sg-jump-previous buffer
