# Line comments
declare-option -docstring "characters inserted at the beginning of a commented line" str comment_line '#'

# Block comments
declare-option -docstring "characters inserted before a commented block" str comment_block_begin
declare-option -docstring "characters inserted after a commented block" str comment_block_end

# Default comments for all languages (fallback when tree-sitter is unavailable)
hook global BufSetOption filetype=asciidoc %{
    set-option buffer comment_line '//'
    set-option buffer comment_block_begin '////'
    set-option buffer comment_block_end '////'
}

hook global BufSetOption filetype=(c|cpp|dart|gluon|go|java|javascript|objc|odin|php|pony|protobuf|rust|sass|scala|scss|swift|typescript|typst|groovy) %{
    set-option buffer comment_line '//'
    set-option buffer comment_block_begin '/*'
    set-option buffer comment_block_end '*/'
}

hook global BufSetOption filetype=conf %{
    set-option buffer comment_line '#'
}

hook global BufSetOption filetype=css %{
    set-option buffer comment_line ''
    set-option buffer comment_block_begin '/*'
    set-option buffer comment_block_end '*/'
}

hook global BufSetOption filetype=(fennel|gas|ini) %{
    set-option buffer comment_line ';'
}

hook global BufSetOption filetype=(html|xml) %{
    set-option buffer comment_line ''
    set-option buffer comment_block_begin '<!--'
    set-option buffer comment_block_end '-->'
}

hook global BufSetOption filetype=lua %{
    set-option buffer comment_line '--'
    set-option buffer comment_block_begin '--[['
    set-option buffer comment_block_end ']]'
}

hook global BufSetOption filetype=markdown %{
    set-option buffer comment_line ''
    set-option buffer comment_block_begin '[//]: # "'
    set-option buffer comment_block_end '"'
}

hook global BufSetOption filetype=(pug|zig|cue|hare|gleam) %{
    set-option buffer comment_line '//'
}

hook global BufSetOption filetype=python %{
    set-option buffer comment_block_begin "'''"
    set-option buffer comment_block_end "'''"
}

hook global BufSetOption filetype=ruby %{
    set-option buffer comment_block_begin '^begin='
    set-option buffer comment_block_end '^=end'
}

hook global BufSetOption filetype=sql %{
    set-option buffer comment_line '--'
    set-option buffer comment_block_begin '/*'
    set-option buffer comment_block_end '*/'
}

define-command comment-block -docstring '(un)comment selections using block comments' %{
  	evaluate-commands %sh{
        if [ -z "${kak_opt_comment_block_begin}" ] || [ -z "${kak_opt_comment_block_end}" ]; then
            echo "fail \"The 'comment_block' options are empty, could not comment the selection\""
        fi
    }

		evaluate-commands -save-regs '"/' -draft %{
				# Keep non-empty selections
				execute-keys <a-K>\A\s*\z<ret>
				try %{
            # Assert that the selection has been commented
            set-register / "\A\Q%opt{comment_block_begin}\E.*\Q%opt{comment_block_end}\E\n*\z"
            execute-keys "s<ret>"
            # Uncomment it
            set-register / "\A\Q%opt{comment_block_begin}\E|\Q%opt{comment_block_end}\E\n*\z"
            execute-keys s<ret>d
        } catch %{
            # Comment the selection
            set-register '"' "%opt{comment_block_begin}"
            execute-keys -draft P
            set-register '"' "%opt{comment_block_end}"
            execute-keys p
        }
		}
}

define-command comment-line -docstring '(un)comment selected lines using line comments' %{
		evaluate-commands %sh{
        if [ -z "${kak_opt_comment_line}" ]; then
            echo "fail \"The 'comment_line' option is empty, could not comment the line\""
        fi
    }

		evaluate-commands -save-regs '"/' -draft %{
        # Select the content of the lines, without indentation
        execute-keys <a-s>gi<a-l>

        try %{
            # Keep non-empty lines
            execute-keys <a-K>\A\s*\z<ret>
        }

        try %{
            set-register / "\A\Q%opt{comment_line}\E\h?"

            try %{
                # See if there are any uncommented lines in the selection
                execute-keys -draft <a-K><ret>

                # There are uncommented lines, so comment everything
                set-register '"' "%opt{comment_line} "
                align-selections-left
                execute-keys P
            } catch %{
                # All lines were commented, so uncomment everything
                execute-keys s<ret>d
            }
        }
    }
}

define-command align-selections-left -docstring 'extend selections to the left to align with the leftmost selected column' %{
    evaluate-commands %sh{
        leftmost_column=$(echo "$kak_selections_desc" | tr ' ' '\n' | cut -d',' -f1 | cut -d'.' -f2 | sort -n | head -n1)
        aligned_selections=$(echo "$kak_selections_desc" | sed -E "s/\.[0-9]+,/.$leftmost_column,/g")
        echo "select $aligned_selections"
    }
}

define-command comment-line-as-block %{
    execute-keys -draft 'xs[^\n]<ret><a-_>: comment-block<ret>'
}

# Wrap each line with block comment markers, preserving indentation
# e.g. "  <div/>" → "  {/* <div/> */}"
define-command comment-line-wrap -docstring '(un)comment each line using block comment markers' %{
    evaluate-commands %sh{
        if [ -z "${kak_opt_comment_block_begin}" ] || [ -z "${kak_opt_comment_block_end}" ]; then
            echo "fail \"The 'comment_block' options are empty\""
        fi
    }

    evaluate-commands -save-regs '"/' -draft %{
        # Select the content of the lines, without indentation
        execute-keys <a-s>gi<a-l>

        try %{
            # Keep non-empty lines
            execute-keys <a-K>\A\s*\z<ret>
        }

        try %{
            set-register / "\A\Q%opt{comment_block_begin}\E\h?|\h?\Q%opt{comment_block_end}\E\z"

            try %{
                # See if there are any uncommented lines in the selection
                execute-keys -draft <a-K><ret>

                # There are uncommented lines, so comment everything
                align-selections-left
                execute-keys -draft "i%opt{comment_block_begin} <esc>"
                execute-keys -draft "a %opt{comment_block_end}<esc>"
            } catch %{
                # All lines were commented, so uncomment: delete begin/end markers
                execute-keys s<ret>d
            }
        }
    }
}

# Tree-sitter-aware commenting: uses injection language + AST node ancestry
# to pick the correct comment style (e.g. {/* */} in JSX, // in JS, <!-- --> in HTML)
define-command smart-comment -docstring 'toggle comment using tree-sitter context' %{
    try %{
        tree-query-cursor
        evaluate-commands %sh{
            lang="$kak_opt_tree_cursor_lang"
            ancestors="$kak_opt_tree_cursor_ancestors"

            comment_line=
            comment_block_begin=
            comment_block_end=
            use_block=false

            # Language-based comment strings (injection-aware)
            case "$lang" in
                bash|sh|zsh|python|ruby|elixir|perl|r|fish|nu|nix|just|toml|yaml|dockerfile|make|awk|sed|tcl|hcl|terraform|graphql|gdscript|kak|hyprlang|ipynb|rego)
                    comment_line='#' ;;
                c|cpp|c_sharp|dart|go|java|javascript|typescript|tsx|rust|swift|odin|kotlin|scala|zig|hare|gleam|cue|php|protobuf|pony|groovy|slang|hlsl|glsl|wgsl|d|fsharp|bicep|rescript|blueprint)
                    comment_line='//'
                    comment_block_begin='/*'
                    comment_block_end='*/' ;;
                scss|sass|less)
                    comment_line='//'
                    comment_block_begin='/*'
                    comment_block_end='*/' ;;
                css|styled)
                    use_block=true
                    comment_block_begin='/*'
                    comment_block_end='*/' ;;
                html|xml|svg|vue|svelte|astro|axaml|xaml|cs_project|fsharp_project)
                    use_block=true
                    comment_block_begin='<!--'
                    comment_block_end='-->' ;;
                lua)
                    comment_line='--'
                    comment_block_begin='--[['
                    comment_block_end=']]' ;;
                sql|plsql)
                    comment_line='--'
                    comment_block_begin='/*'
                    comment_block_end='*/' ;;
                clojure)
                    comment_line=';' ;;
                fennel|scheme|racket|common_lisp|janet)
                    comment_line=';;' ;;
                haskell|purescript)
                    comment_line='--' ;;
                ocaml)
                    use_block=true
                    comment_block_begin='(*'
                    comment_block_end='*)' ;;
                latex|tex)
                    comment_line='%' ;;
                vim)
                    comment_line='"' ;;
                ini|desktop)
                    comment_line=';' ;;
                twig)
                    use_block=true
                    comment_block_begin='{#'
                    comment_block_end='#}' ;;
                handlebars|glimmer)
                    use_block=true
                    comment_block_begin='{{!'
                    comment_block_end='}}' ;;
                erlang)
                    comment_line='%' ;;
                gas)
                    comment_line=';' ;;
                asciidoc)
                    comment_line='//' ;;
                markdown)
                    use_block=true
                    comment_block_begin='[//]: # "'
                    comment_block_end='"' ;;
                *)
                    # Unknown language: fall back to buffer defaults
                    comment_line="$kak_opt_comment_line"
                    comment_block_begin="$kak_opt_comment_block_begin"
                    comment_block_end="$kak_opt_comment_block_end"
                    ;;
            esac

            # Node-type overrides: check ancestors for context-specific comments
            case "$lang" in
                javascript|typescript|tsx)
                    # JSX contexts use {/* */} block comments
                    case " $ancestors " in
                        *' jsx_element '*|*' jsx_fragment '*|*' jsx_self_closing_element '*|*' jsx_opening_element '*|*' jsx_closing_element '*)
                            use_block=true
                            comment_block_begin='{/*'
                            comment_block_end='*/}'
                            comment_line=
                            ;;
                    esac
                    ;;
                templ)
                    case " $ancestors " in
                        *' component_block '*)
                            use_block=true
                            comment_block_begin='<!--'
                            comment_block_end='-->'
                            comment_line=
                            ;;
                    esac
                    ;;
            esac

            # Set window-scoped options (overrides buffer defaults for this action)
            printf "set-option window comment_line '%s'\n" "$comment_line"
            printf "set-option window comment_block_begin '%s'\n" "$comment_block_begin"
            printf "set-option window comment_block_end '%s'\n" "$comment_block_end"

            if [ "$use_block" = true ] || [ -z "$comment_line" ]; then
                if [ -n "$comment_block_begin" ]; then
                    echo 'comment-line-wrap'
                else
                    echo 'fail "no comment style for this context"'
                fi
            else
                echo 'comment-line'
            fi
        }
    } catch %{
        # Fallback: no tree-sitter — use static buffer options
        evaluate-commands %sh{
            if [ -z "$kak_opt_comment_line" ]; then
                echo 'comment-line-as-block'
            else
                echo 'comment-line'
            fi
        }
    }
}
