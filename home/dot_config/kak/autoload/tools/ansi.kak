declare-option -hidden range-specs ansi_color_ranges
declare-option -hidden str ansi_command_file
declare-option -hidden str ansi_filter "~/.local/bin/kak-ansi-filter"

define-command -params 0 ansi-render-selection -docstring "ansi-render-selection: colorize ANSI codes contained inside selection" %{
  	try ansi-setup-buffer
  	ansi-render-selection-impl
}

define-command -hidden ansi-setup-buffer %{
  	add-highlighter buffer/ansi ranges ansi_color_ranges
  	set-option buffer ansi_color_ranges %val{timestamp}
  	set-option buffer ansi_command_file %sh{mktemp}
  	hook -always -once buffer BufClose .* %{
    		nop %sh{rm ${kak_opt_ansi_command_file}}
    		set-option buffer ansi_command_file /dev/null
  	}
}

define-command -hidden ansi-render-selection-impl %{
  	evaluate-commands -save-regs | %{
    		set-register '|' "%opt{ansi_filter} -range %val{selection_desc} 2>%opt{ansi_command_file}"
    		execute-keys "|<ret>"
    		update-option buffer ansi_color_ranges
    		source "%opt{ansi_command_file}"
    		trigger-user-hook "AnsiColored=%val(selection_desc)"
  	}
}

define-command -params 0 ansi-render -docstring "ansi-render: colorize buffer by using ANSI codes" %{
  	evaluate-commands -draft %{
    		execute-keys '%'
    		ansi-render-selection
  	}
}

define-command -docstring "ansi-enable: start rendering new fifo data in current buffer." -params 0 ansi-enable %{
    try ansi-setup-buffer
    ansi-render
    remove-hooks buffer ansi
    hook -group ansi buffer BufReadFifo .* %{
        evaluate-commands -draft %{
            select "%val{hook_param}"
            ansi-render-selection-impl
        }
    }
}

define-command -docstring "ansi-clear: clear highlighting for current buffer." -params 0 ansi-clear %{
    set-option buffer ansi_color_ranges %val{timestamp}
}

define-command -docstring "ansi-disable: stop rendering new fifo content in current buffer." -params 0 ansi-disable %{
    remove-hooks buffer ansi
}

hook -group ansi global BufCreate '\*stdin(?:-\d+)?\*' ansi-enable
