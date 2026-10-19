# Emmet plugin for Kakoune
# https://github.com/saifulapm/emmet-cli
# Requires: kak-lsp for snippet/placeholder handling

declare-option -hidden -docstring "emmet CLI command" str emmet_cmd "emmet"

define-command emmet-expand -docstring "Expand Emmet abbreviation at cursor" %{
    evaluate-commands -draft %{
        # Select emmet abbreviation using regex (excludes surrounding parens and HTML tags)
        execute-keys 'h<a-?>[.#a-zA-Z][a-zA-Z0-9.#>+^*@|\-:=_\[\]{}]*<ret>'

        # Old approach (commented out):
        # execute-keys '<a-;><a-B><a-;>'

        evaluate-commands %sh{
            abbr="$kak_selection"

            if [ -z "$abbr" ]; then
                echo "fail 'No abbreviation selected'"
                exit
            fi

            # Detect syntax based on filetype
            syntax="html"
            case "$kak_opt_filetype" in
                css|scss|sass|less) syntax="css" ;;
                javascript|typescript|tsx) syntax="jsx" ;;
                vue|liquid|blade|astro) syntax="html" ;;
            esac

            # Expand abbreviation with tab stops
            expanded=$($kak_opt_emmet_cmd expand "$abbr" -s "$syntax" 2>/dev/null)

            if [ $? -ne 0 ]; then
                echo "fail 'Failed to expand abbreviation: $abbr'"
                exit
            fi

            # Escape for Kakoune
            escaped=$(printf '%s' "$expanded" | sed "s/'/''/g")

            # Delete abbreviation and insert snippet
            printf "execute-keys _d\n"
            printf "evaluate-commands -draft -verbatim lsp-snippets-insert '%s'\n" "$escaped"
        }
    }
    lsp-snippets-select-next-placeholders
}

define-command emmet-wrap -docstring "Wrap selection with Emmet abbreviation" %{
    prompt 'Emmet abbreviation: ' %{
        evaluate-commands %sh{
            abbr="$kak_text"
            content="$kak_selection"

            if [ -z "$abbr" ]; then
                echo "fail 'No abbreviation provided'"
                exit
            fi

            # Detect syntax
            syntax="html"
            case "$kak_opt_filetype" in
                css|scss|sass|less) syntax="css" ;;
                javascript|typescript) syntax="jsx" ;;
                vue) syntax="html" ;;
            esac

            # Wrap with emmet
            wrapped=$(printf '%s' "$content" | $kak_opt_emmet_cmd wrap "$abbr" -s "$syntax" 2>/dev/null)

            if [ $? -ne 0 ]; then
                echo "fail 'Failed to wrap with abbreviation'"
                exit
            fi

            # Escape for Kakoune
            escaped=$(printf '%s' "$wrapped" | sed "s/'/''/g")

            # Replace selection with wrapped content using kak-lsp snippet
            printf "execute-keys -draft _c\n"
            printf "evaluate-commands -draft -verbatim lsp-snippets-insert '%s'\n" "$escaped"
        }
    }
}
