# Tree-sitter highlight group faces
# Maps tree-sitter capture names to Kakoune faces
# Naming: @capture.name → ts_capture_name (dots → underscores)

# --- Variables ---
set-face global ts_variable                          variable
set-face global ts_variable_builtin                  builtin
set-face global ts_variable_parameter                variable
set-face global ts_variable_parameter_builtin        builtin
set-face global ts_variable_member                   variable
set-face global ts_variable_other_member             variable
set-face global ts_variable_other_member_private     variable

# --- Constants ---
set-face global ts_constant                          value
set-face global ts_constant_builtin                  builtin
set-face global ts_constant_builtin_boolean          value
set-face global ts_constant_character                value
set-face global ts_constant_character_escape         value
set-face global ts_constant_macro                    meta
set-face global ts_constant_numeric                  value

# --- Numbers (alternative captures) ---
set-face global ts_constant_integer                  value
set-face global ts_constant_float                    value
set-face global ts_number                            value
set-face global ts_number_float                      value
set-face global ts_boolean                           value
set-face global ts_character                         value
set-face global ts_character_special                 value

# --- Modules ---
set-face global ts_module                            module
set-face global ts_module_builtin                    builtin
set-face global ts_namespace                         module
set-face global ts_label                             meta

# --- Strings ---
set-face global ts_string                            string
set-face global ts_string_documentation              string
set-face global ts_string_regexp                     meta
set-face global ts_string_escape                     value
set-face global ts_string_special                    meta
set-face global ts_string_special_symbol             meta
set-face global ts_string_special_url                link
set-face global ts_string_special_path               string

# --- Types ---
set-face global ts_type                              type
set-face global ts_type_builtin                      builtin
set-face global ts_type_definition                   type
set-face global ts_type_parameter                    type
set-face global ts_type_enum                         type
set-face global ts_type_enum_variant                 value

# --- Attributes ---
set-face global ts_attribute                         attribute
set-face global ts_attribute_builtin                 attribute
set-face global ts_property                          variable

# --- Functions ---
set-face global ts_function                          function
set-face global ts_function_builtin                  builtin
set-face global ts_function_call                     function
set-face global ts_function_macro                    function
set-face global ts_function_method                   function
set-face global ts_function_method_call              function
set-face global ts_function_method_private           function
set-face global ts_function_special                  function
set-face global ts_constructor                       function

# --- Operators ---
set-face global ts_operator                          operator

# --- Keywords ---
set-face global ts_keyword                           keyword
set-face global ts_keyword_coroutine                 keyword
set-face global ts_keyword_function                  keyword
set-face global ts_keyword_operator                  operator
set-face global ts_keyword_import                    keyword
set-face global ts_keyword_type                      keyword
set-face global ts_keyword_modifier                  keyword
set-face global ts_keyword_repeat                    keyword
set-face global ts_keyword_return                    keyword
set-face global ts_keyword_debug                     keyword
set-face global ts_keyword_exception                 keyword
set-face global ts_keyword_conditional               keyword
set-face global ts_keyword_conditional_ternary       keyword
set-face global ts_keyword_directive                 meta
set-face global ts_keyword_directive_define          meta
set-face global ts_keyword_storage                   keyword
set-face global ts_keyword_storage_type              type
set-face global ts_keyword_storage_modifier          keyword
set-face global ts_keyword_deprecated                keyword
set-face global ts_keyword_control                   keyword
set-face global ts_keyword_control_conditional       keyword
set-face global ts_keyword_control_repeat            keyword
set-face global ts_keyword_control_import            keyword
set-face global ts_keyword_control_return            keyword
set-face global ts_keyword_control_exception         keyword

# --- Punctuation ---
set-face global ts_punctuation                       default
set-face global ts_punctuation_delimiter             default
set-face global ts_punctuation_bracket               default
set-face global ts_punctuation_special               meta

# --- Comments ---
set-face global ts_comment                           comment
set-face global ts_comment_line                      comment
set-face global ts_comment_line_documentation        documentation
set-face global ts_comment_block                     comment
set-face global ts_comment_block_documentation       documentation
set-face global ts_comment_unused                    comment
set-face global ts_comment_documentation             documentation
set-face global ts_comment_error                     Error
set-face global ts_comment_warning                   Error
set-face global ts_comment_todo                      comment
set-face global ts_comment_note                      comment

# --- Markup ---
set-face global ts_markup                            default
set-face global ts_markup_strong                     default
set-face global ts_markup_bold                       default
set-face global ts_markup_italic                     default
set-face global ts_markup_strikethrough              default
set-face global ts_markup_underline                  default
set-face global ts_markup_heading                    title
set-face global ts_markup_heading_marker             title
set-face global ts_markup_heading_1                  title
set-face global ts_markup_heading_2                  title
set-face global ts_markup_heading_3                  title
set-face global ts_markup_heading_4                  title
set-face global ts_markup_heading_5                  title
set-face global ts_markup_heading_6                  title
set-face global ts_markup_quote                      comment
set-face global ts_markup_math                       value
set-face global ts_markup_link                       link
set-face global ts_markup_link_label                 link
set-face global ts_markup_link_url                   link
set-face global ts_markup_link_text                  link
set-face global ts_markup_raw                        mono
set-face global ts_markup_raw_block                  mono
set-face global ts_markup_raw_inline                 mono
set-face global ts_markup_list                       bullet
set-face global ts_markup_list_checked               bullet
set-face global ts_markup_list_unchecked             bullet
set-face global ts_markup_list_unnumbered            bullet
set-face global ts_markup_list_numbered              bullet

# --- Diff ---
set-face global ts_diff                              default
set-face global ts_diff_plus                         green
set-face global ts_diff_plus_gutter                  green
set-face global ts_diff_minus                        red
set-face global ts_diff_minus_gutter                 red
set-face global ts_diff_delta                        yellow
set-face global ts_diff_delta_moved                  yellow
set-face global ts_diff_delta_conflict               red
set-face global ts_diff_delta_gutter                 yellow

# --- Tags (HTML/XML) ---
set-face global ts_tag                               keyword
set-face global ts_tag_builtin                       keyword
set-face global ts_tag_attribute                     attribute
set-face global ts_tag_delimiter                     default

# --- Special ---
set-face global ts_text                              default
set-face global ts_text_reference                    link
set-face global ts_none                              default
set-face global ts_special                           meta
set-face global ts_conceal                           default
set-face global ts_embedded                          default

# Rainbow bracket faces (depth-cycled)
set-face global ts_rainbow_1 red
set-face global ts_rainbow_2 green
set-face global ts_rainbow_3 yellow
set-face global ts_rainbow_4 blue
set-face global ts_rainbow_5 magenta
set-face global ts_rainbow_6 cyan

# Highlight markup (set by tree-sitter-highlight command)
declare-option str tree_sitter_markup ""

# Cursor query options (set by tree-query-cursor command)
declare-option str tree_cursor_lang ""
declare-option str tree_cursor_node_type ""
declare-option str tree_cursor_parent_type ""
declare-option str tree_cursor_ancestors ""
declare-option str tree_cursor_in_string "false"
declare-option str tree_cursor_in_comment "false"

# Auto-enable tree-sitter highlighting on filetype change
hook -group tree-sitter-auto global WinSetOption filetype=.+ %{
    try %{ add-highlighter window/tree-sitter tree-sitter }
}

hook -group tree-sitter-auto global WinSetOption filetype= %{
    try %{ remove-highlighter window/tree-sitter }
}

# Catch windows where filetype was set before this script loaded (autoload order)
# Use a one-shot hook: remove itself after first execution
hook -group tree-sitter-late-init global WinDisplay .* %{
    evaluate-commands %sh{
        if [ -n "$kak_opt_filetype" ]; then
            printf 'try %%{ add-highlighter window/tree-sitter tree-sitter }\n'
        fi
    }
    remove-hooks global tree-sitter-late-init
}

# Auto-indent on newline using tree-sitter
hook -group tree-sitter-indent global WinSetOption filetype=.+ %{
    hook -group tree-sitter-indent window InsertChar \n %{
        try %{ tree-indent-newline }
    }
}

hook -group tree-sitter-indent global WinSetOption filetype= %{
    remove-hooks window tree-sitter-indent
}

# Tree-sitter text object key mappings
# Enter with: map global user t ': enter-user-mode tree<ret>'
declare-user-mode tree

map global tree f ': tree-select function around<ret>' -docstring 'function (around)'
map global tree F ': tree-select function inside<ret>' -docstring 'function (inside)'
map global tree c ': tree-select class around<ret>' -docstring 'class (around)'
map global tree C ': tree-select class inside<ret>' -docstring 'class (inside)'
map global tree a ': tree-select parameter around<ret>' -docstring 'parameter (around)'
map global tree A ': tree-select parameter inside<ret>' -docstring 'parameter (inside)'
map global tree o ': tree-select comment around<ret>' -docstring 'comment'
map global tree n ': tree-select-next function<ret>' -docstring 'next function'
map global tree p ': tree-select-prev function<ret>' -docstring 'prev function'
map global tree s ': tree-select-node<ret>' -docstring 'select node'
map global tree P ': tree-parent<ret>' -docstring 'parent'
map global tree i ': tree-first-child<ret>' -docstring 'first child'
map global tree ] ': tree-next-sibling<ret>' -docstring 'next sibling'
map global tree [ ': tree-prev-sibling<ret>' -docstring 'prev sibling'
map global tree e ': tree-expand<ret>' -docstring 'expand selection'
map global tree E ': tree-shrink<ret>' -docstring 'shrink selection'
map global tree '*' ': tree-select-all function<ret>' -docstring 'select all functions'
map global tree '/' ': tree-filter function<ret>' -docstring 'filter to functions'
map global tree j  ': tree-toggle<ret>' -docstring 'split/join toggle'
map global tree J  ': tree-split<ret>' -docstring 'split to multi-line'
map global tree <a-j> ': tree-join<ret>' -docstring 'join to single-line'
map global tree '?' ': tree-sitter-scopes<ret>' -docstring 'show scopes at cursor'
map global tree h ': tree-sitter-highlight-name<ret>' -docstring 'show highlight face'
map global tree t ': tree-sitter-subtree<ret>' -docstring 'show AST subtree'
map global tree l ': tree-sitter-layers<ret>' -docstring 'show injection layers'
