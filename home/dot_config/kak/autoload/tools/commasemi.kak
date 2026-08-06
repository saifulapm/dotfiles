define-command toggle-comasemi -params 1 -docstring 'toggle char at the end of line before comment' %{
    evaluate-commands -save-regs '"/' -draft %{
        # Select the content of the lines, without indentation
        execute-keys <a-s>gi<a-l> # Select the content of the lines, without indentation

        try %{
            # Keep non-empty lines
            execute-keys <a-K>\A\s*\z<ret> # Keep non-empty lines
        }

        # Reduce selection to exclude inline comments
        try %{
            set-register / "\h+(?=%opt{comment_line})"
            execute-keys S<ret>
        }

        # Skip lines that start with comment
        try %{
            set-register / "\A\Q%opt{comment_line}\E\h?"
            execute-keys <a-K><ret>
        }

        try %{
            set-register / "%arg{1}\z"
            execute-keys s<ret>d
        } catch %{
            try %{
                set-register / ",\z|;\z"
                execute-keys "s<ret>"
                set-register '"' "%arg{1}"
                execute-keys R
            } catch %{
                set-register '"' "%arg{1}"
                execute-keys p
            }
        }
    } 
}

# Key mappings
map global normal <c-,> ':toggle-comasemi ,<ret>' -docstring 'toggle comma'
map global normal <c-\;> ':toggle-comasemi \;<ret>' -docstring 'toggle semicolon'
map global insert <c-,> '<a-;>:toggle-comasemi ,<ret>' -docstring 'toggle comma'
map global insert <c-\;> '<a-;>:toggle-comasemi \;<ret>' -docstring 'toggle semicolon'
