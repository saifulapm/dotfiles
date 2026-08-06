define-command repl -docstring "create kak repl buffer" %{
    new %{ edit -scratch; set buffer filetype kak }
}
define-command execute-selection -docstring "execute kakoune script" %{
    evaluate-commands -draft -save-regs 'a|' %{
        execute-keys '"ay'
        edit -scratch
        execute-keys '"aR'
        set-register | %{
            awk -v cmds="define-command|provide-module" '
            $0 ~ cmds {
                if ($0 !~ /-override/) {
                    sub(/(foo-bar|define-command)/, "& -override")
                }
            }
            { print }
            '
        }
        execute-keys '%|<ret>%:<c-r>.<ret>'
        delete-buffer!
    }
}

define-command execute-file -docstring "execute kak file" %{
    execute-keys -draft '%: execute-selection<ret>'
}
