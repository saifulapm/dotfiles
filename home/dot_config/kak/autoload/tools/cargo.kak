declare-option -docstring "shell command run to build the project" str cargocmd cargo

declare-option -docstring "regex describing cargo error references" \
    regex \
    cargo_error_pattern \
    "^\h*(?:error|warning|note)(?:\[[A-Z0-9]+\])?: ([^\n]*)\n *--> ([^\n]*?):(\d+)(?::(\d+))?"

declare-option -docstring "name of the client in which utilities display information" str toolsclient
declare-option -docstring "name of the client in which all source code jumps will be executed" str jumpclient
declare-option -hidden int cargo_current_error_line
declare-option -hidden str cargo_workspace_root

define-command -params .. \
    -docstring %{cargo [<arguments>]: cargo utility wrapper
All the optional arguments are forwarded to the cargo utility} \
    cargo %{
    evaluate-commands %sh{
        workspace_root=$(
            cargo metadata --format-version=1 |
            grep -o '"workspace_root":"[^"]*' |
            grep -o '[^"]*$'
        )
        quoted_workspace_root="'""$(
            printf %s "$workspace_root" |
            sed -e "s/'/''/g"
        )""/'"

        output=$(mktemp -d "${TMPDIR:-/tmp}"/kak-cargo.XXXXXXXX)/fifo
        mkfifo ${output}
        ( trap - INT QUIT; eval ${kak_opt_cargocmd} "$@" > ${output} 2>&1 ) > /dev/null 2>&1 < /dev/null &

        printf %s\\n "
            evaluate-commands -try-client '$kak_opt_toolsclient' %{
               edit! -fifo ${output} -scroll *cargo*
               set-option buffer filetype cargo
               set-option buffer cargo_current_error_line 1
               set-option buffer cargo_workspace_root $quoted_workspace_root
               hook -once buffer BufCloseFifo .* %{
                   nop %sh{ rm -r $(dirname ${output}) }
                   evaluate-commands -try-client '$kak_client' %{
                       echo -- Completed cargo $*
                   }
               }
           }
        "
    }
}

add-highlighter shared/cargo group
add-highlighter shared/cargo/error regex "^(error(?:\[[A-Z0-9]+\])?:)" 1:red
add-highlighter shared/cargo/warning regex "^(warning(?:\[[A-Z0-9]+\])?:)" 1:yellow
add-highlighter shared/cargo/note regex "^(note(?:\[[A-Z0-9]+\])?:)" 1:green
add-highlighter shared/cargo/info-ascription regex "^ +\|[ |]+(-+[^\n]*)$" 1:cyan
add-highlighter shared/cargo/error-ascription regex "^ +\|[ |]+(\^+[^\n]*)$" 1:red
add-highlighter shared/cargo/current-error-line line '%opt{cargo_current_error_line}' default+b
add-highlighter shared/cargo/action-header regex "^\h+(Checking|Compiling|Updating|Locking|Finished|Running|Doc-tests|Packaging|Packaged|Verifying|Adding)\b[^\n]+$" 1:green+b
add-highlighter shared/cargo/building regex "^\s+Building[^\n]+$" 1:cyan+b

hook -group cargo-highlight global WinSetOption filetype=cargo %{
    add-highlighter window/cargo ref cargo
	hook -once -always window WinSetOption filetype=.* %{
	    remove-highlighter window/cargo
	}
}

hook global WinSetOption filetype=cargo %{
    #hook buffer -group cargo-hooks NormalKey <ret> cargo-jump
    map -docstring "Jump to current error" buffer normal <ret> %{: cargo-jump<ret>}
}

hook global WinSetOption filetype=(?!cargo).* %{
    #remove-hooks buffer cargo-hooks
    unmap buffer normal <ret> %{: cargo-jump<ret>}
}

declare-option -docstring "name of the client in which all source code jumps will be executed" \
    str jumpclient

define-command -hidden cargo-open-error -params 4 %{
    evaluate-commands -try-client %opt{jumpclient} %{
        edit -existing "%arg{1}" "%arg{2}" "%arg{3}"
        info -anchor "%arg{2}.%arg{3}" "%arg{4}"
        try %{ focus }
    }
}

define-command -hidden cargo-jump %{
    evaluate-commands %{
        # We may be in the middle of an error.
        # To find it, we search for the next error
        # (which definitely moves us past the end of this error)
        # and then search backward
        execute-keys "/" %opt{cargo_error_pattern} <ret>
        execute-keys <a-/> %opt{cargo_error_pattern} <ret><a-:> "<a-;>"

        # We found a Cargo error, let's open it.
        set-option buffer cargo_current_error_line "%val{cursor_line}"
        cargo-open-error \
            "%opt{cargo_workspace_root}%reg{2}" \
            "%reg{3}" \
            "%sh{ echo ${kak_main_reg_4:-1} }" \
            "%reg{1}"
    }
}

define-command cargo-next-error -docstring 'Jump to the next cargo error' %{
    try %{
        evaluate-commands -try-client %opt{jumpclient} %{
            buffer '*cargo*'
            execute-keys "%opt{cargo_current_error_line}gl" "/%opt{cargo_error_pattern}<ret>"
            cargo-jump
        }
        # Make sure the selected error is visible
        try %{
            evaluate-commands -client %opt{toolsclient} %{
                buffer '*cargo*'
                execute-keys %opt{cargo_current_error_line}gvv
            }
        }
    } catch %{
    	fail "No Cargo errors found"
    }
}

define-command cargo-previous-error -docstring 'Jump to the previous cargo error' %{
    try %{
        evaluate-commands -try-client %opt{jumpclient} %{
            buffer '*cargo*'
            execute-keys "%opt{cargo_current_error_line}gl" "<a-/>%opt{cargo_error_pattern}<ret>"
            cargo-jump
        }
        # Make sure the selected error is visible
        try %{
            evaluate-commands -client %opt{toolsclient} %{
                buffer '*cargo*'
                execute-keys %opt{cargo_current_error_line}gvv
            }
        }
    } catch %{
    	fail "No Cargo errors found"
    }
}

declare-user-mode cargo

map -docstring "Run tests" global cargo t %{: cargo test<ret>}
map -docstring "Check syntax" global cargo c %{: cargo check --all-targets<ret>}
map -docstring "Build documentation" global cargo d %{: cargo doc<ret>}
map -docstring "Next error" global cargo n %{: cargo-next-error<ret>}
map -docstring "Previous error" global cargo p %{: cargo-previous-error<ret>}

