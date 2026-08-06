# Insert Mode
map -docstring 'insert clipboard contents' global insert <c-y> '<c-r>"'
map -docstring 'move cursors to the start of the line' global insert <c-a> '<home>'
map -docstring 'move cursors to the end of the line' global insert <c-e> '<end>'
map global insert <c-u> '<a-;>:erase_characters_before_cursor_to_line_begin<ret>'
map global insert <c-w> '<a-;>:erase_word_before_cursor<ret>'
# map global insert <backspace> '<a-;>:decrease_indent_or_erase_character_before_cursor<ret>'
# map global insert <tab> '<a-;>:increase_indent<ret>'
# map global insert <s-tab> '<a-;>:decrease_indent<ret>'
# map global insert <c-l> '<right>'
# map global insert <c-j> '<down>'
# map global insert <c-k> '<up>'
# map global insert <c-h> '<left>'

# Normal mode
map -docstring 'extend selected text to line begin' global normal <a-h> '<a-:><a-h>'
map -docstring 'extend selected text to line end' global normal <a-l> '<a-:><a-;><a-l>'
map -docstring 'delete current buffer' global normal <c-w> ':delete-buffer<ret>'
map -docstring 'quit current client' global normal <c-q> ':quit<ret>'
map global normal <c-down> ':move_selected_lines_down<ret>'
map global normal <c-up> ':move_selected_lines_up<ret>'
map global normal <c-a> ':increment_selected_numbers %val{count}<ret>'
map global normal <c-x> ':decrement_selected_numbers %val{count}<ret>'

# Tree-sitter expand/shrink & split/join
map global normal <a-ret> ':tree-expand<ret>' -docstring 'expand selection'
map global normal <a-s-ret> ':tree-shrink<ret>' -docstring 'shrink selection'
map global normal <a-j> ':tree-toggle<ret>' -docstring 'split/join toggle'

# Some Globals
map global normal "#" ": smart-comment<ret>" -docstring "smart comment"
map global normal "<a-#>" ": comment-block<ret>" -docstring "comment block"
map global normal D '<a-l>d' -docstring 'delete to end of line'
map global normal Y '<a-l>y' -docstring 'yank to end of line'

# phantom selection
# map global normal f     ": phantom-selection-add-selection<ret>"
# map global normal F     ": phantom-selection-select-all; phantom-selection-clear<ret>"
# map global normal <a-f> ": phantom-selection-iterate-next<ret>"
# map global normal <a-F> ": phantom-selection-iterate-prev<ret>"

# this would be nice, but currrently doesn't work
# see https://github.com/mawww/kakoune/issues/1916
# map global insert <a-f> "<a-;>: phantom-selection-iterate-next<ret>"
# map global insert <a-F> "<a-;>: phantom-selection-iterate-prev<ret>"
# so instead, have an approximate version that uses 'i'
map global insert <a-f> "<esc>: phantom-selection-iterate-next<ret>i"
map global insert <a-F> "<esc>: phantom-selection-iterate-prev<ret>i"

## Pickers
declare-user-mode picker
map global user f ':enter-user-mode picker<ret>' -docstring 'pickers'
map global picker f ':open_file_picker<ret>'   -docstring 'file picker'
map global picker d ':swiper-file-picker<ret>'   -docstring 'swiper file picker'
map global picker l ':open_line_picker<ret>' -docstring 'open line picker'
map global picker b ':buffer<space>'   -docstring 'buffer picker'
map global picker m ':open_changed_file_picker<ret>'   -docstring 'pick modified file'
map global picker z ':fzf<ret>'   -docstring 'fzf picker'
map global picker s ':sk<ret>'   -docstring 'sk picker'
map global picker g ':zf<ret>'   -docstring 'zf picker'
map global picker e ':lf<ret>'   -docstring 'Explorer (lf)'

# Goto Mode
map global goto u '<esc>: url-open<ret>' -docstring 'Open url in browser'
map global goto w '<esc>:hop-kak-words<ret>' -docstring 'Jump to word (Hop)'
map -docstring "file non-recursive" global goto '<a-f>' '<esc>gf'
map -docstring "file" global goto 'f' '<esc>: goto-file %val{selection}<ret>'
map global goto d <esc>:lsp-definition<ret> -docstring 'LSP definition'
map global goto r <esc>:lsp-references<ret> -docstring 'LSP references'
map global goto y <esc>:lsp-type-definition<ret> -docstring 'LSP type definition'

# local leader mode
map global normal "'" ':enter-user-mode local<ret>' -docstring 'Local Leader'

# Match Mode (Helix like Matching)
map global normal m ':enter-user-mode match<ret>' -docstring 'Match mode'
map global normal M ':enter-user-mode match-extend<ret>' -docstring 'match mode (extend)'

## User mappings
map global user <space> ':open_file_picker<ret>'   -docstring 'pick file'
map global user , ':buffer<space>'   -docstring 'buffer picker'
map global user / ':live-grep<ret>'   -docstring 'Grep Search'
map global user "\" ':sk-live-grep<ret>'   -docstring 'SK Grep Search'

# Git support
map global user g ':enter-user-mode git<ret>' -docstring 'git mode'
map global user e ':explore<ret>'   -docstring 'Explorer'
map global user p ':extra-paste-system<ret>' -docstring 'Paste Sys Clipboard'
map global user y ':extra-yank-system<ret>'  -docstring 'yank to system clipboard'
map global user Y ':extra-yank-cursor<ret>'  -docstring 'yank cursor'
map global user l ':enter-user-mode lsp<ret>' -docstring 'LSP mode'
map global user n ':enter-user-mode notes<ret>' -docstring 'Notes mode'

## buffers
map global user b ':enter-buffers-mode<ret>'              -docstring 'buffers…'
map global user B ':enter-user-mode -lock buffers<ret>'   -docstring 'buffers (lock)…'

# Spell
map -docstring 'spelling' global user S ': enter-user-mode spell<ret>'

# Tree-sitter objects (works with ] [ <a-i> <a-a>)
# ]f = next function, [f = prev function, <a-i>f = inner, <a-a>f = around
define-command -hidden tree-object -params 2 %{
    echo -debug "tree-object: %arg{1} flags='%arg{2}'"
    evaluate-commands %sh{
        case "$2" in
            *inner*) echo "tree-select $1 inside" ;;
            *to_begin*to_end*|*to_end*to_begin*) echo "tree-select $1 around" ;;
            *to_end*) echo "tree-select-next $1" ;;
            *to_begin*) echo "tree-select-prev $1" ;;
            *) echo "tree-select $1 around" ;;
        esac
    }
}
map global object f '<a-;>tree-object function %val{object_flags}<ret>' -docstring 'function (ts)'
map global object t '<a-;>tree-object class %val{object_flags}<ret>' -docstring 'class (ts)'
map global object a '<a-;>tree-object parameter %val{object_flags}<ret>' -docstring 'parameter (ts)'
map global object c '<a-;>tree-object comment %val{object_flags}<ret>' -docstring 'comment (ts)'
map -docstring 'double quotation mark' global object <a-Q> 'c“,”<ret>'
map -docstring 'single quotation mark' global object <a-q> 'c‘,’<ret>'
map -docstring 'double angle quotation mark' global object <a-G> 'c«,»<ret>'
map -docstring 'single angle quotation mark' global object <a-g> 'c‹,›<ret>'
map -docstring 'line' global object x 'c<a-;>x^\h*,\h*\n<ret>'
map -docstring 'tag' global object T 'c<lt>\w[\w-]*\h*[^<gt>]*?(?<lt>!/)<gt>,<lt>/\w[\w-]*(?<lt>!/)<gt><ret>'
map -docstring 'previous parenthesis blocks' global object ( 'c<a-;><a-f>(\(,\)<ret>'
map -docstring 'next parenthesis blocks' global object ) 'c<a-;>f(\(,\)<ret>'
map -docstring 'previous brace blocks' global object { 'c<a-;><a-f>{\{,\}<ret>'
map -docstring 'next brace blocks' global object } 'c<a-;>f{\{,\}<ret>'
map -docstring 'previous bracket blocks' global object [ 'c<a-;><a-f>[\[,\]<ret>'
map -docstring 'next bracket blocks' global object ] 'c<a-;>f[\[,\]<ret>'
map -docstring 'previous angle blocks' global object <lt> 'c<a-;><a-f><lt><lt>,<gt><ret>'
map -docstring 'next angle blocks' global object <gt> 'c<a-;>f<lt><lt>,<gt><ret>'

# Tab Completion# Lsp Snippets
hook global InsertCompletionShow .* %{ map window insert <tab> <c-n>; map window insert <s-tab> <c-p> }
hook global InsertCompletionHide .* %{ unmap window insert <tab> <c-n>; unmap window insert <s-tab> <c-p> }

# Select View
map global normal <a-%> ': select-view<ret>' -docstring 'select view'
map global view s '<esc>: select-view<ret>' -docstring 'select view'

# Byline
map global normal "X" ": byline-drag-down<ret>"
map global normal "<a-X>" ": byline-drag-up<ret>"

# formatting / indent
map -docstring "tree-sitter indent" global normal = ":tree-indent<ret>"
map -docstring "format buffer" global normal <a-=> ": format-buffer<ret>"

map -docstring 'open text highlighter prompt' global user '*' ':open_text_highlighter_prompt<ret>'
map -docstring 'open goto line prompt' global user G ':open_goto_line_prompt<ret>'
map -docstring 'convert selected text to ASCII' global user @ ':convert_selected_text_to_ascii<ret>'
map -docstring 'enter letter case mode' global user ` ':enter-user-mode letter_case<ret>'

# fifo mappings
hook global -always BufOpenFifo '\*grep\*' %{ map global normal <minus> ': grep-next-match<ret>' }
hook global -always BufOpenFifo '\*make\*' %{ map global normal <minus> ': make-next-error<ret>' }
hook global -always BufOpenFifo '\*sg-grep\*' %{ map global normal <minus> ': sg-grep-next-match<ret>' }

# Case-insensitive Search
# map -docstring 'case insensitive search' global user '/' /(?i)
# map -docstring 'case insensitive backward search' global user '<a-/>' <a-/>(?i)
# map -docstring 'case insensitive extend search' global user '?' ?(?i)
# map -docstring 'case insensitive backward extend-search' global user '<a-?>' <a-?>(?i)

# Emmet
# map global insert <c-'> '<a-;>:emmet-expand<ret>' -docstring 'Emmet expand'
map global insert <c-j> '<a-;>:try snippets-or-emmet-expand<ret>' -docstring 'Placeholder/Snippet/Emmet expand'
map global normal <c-'> '<a-;>:emmet-wrap<ret>' -docstring 'Emmet wrap'
