; Keywords — specific commands
(try_statement "try" @keyword)
(try_statement "catch" @keyword)
(hook_definition "hook" @keyword)
(define_command "define-command" @keyword)
(evaluate_commands "evaluate-commands" @keyword)
(execute_keys "execute-keys" @keyword)
(map_definition "map" @keyword)
(unmap_definition "unmap" @keyword)
(provide_module "provide-module" @keyword)
(require_module "require-module" @keyword)
(set_face "set-face" @keyword)
(remove_hooks "remove-hooks" @keyword)
(remove_highlighter "remove-highlighter" @keyword)
(declare_user_mode "declare-user-mode" @keyword)
(enter_user_mode "enter-user-mode" @keyword)
(set_option "set-option" @keyword)
(declare_option "declare-option" @keyword)
(unset_option "unset-option" @keyword)
(add_highlighter "add-highlighter" @keyword)
(source_command "source" @keyword.import)
(alias_definition "alias" @keyword)
(unalias_definition "unalias" @keyword)
(set_register "set-register" @keyword)
(echo_command "echo" @keyword)
(fail_command "fail" @keyword)
(nop_command "nop" @keyword)
(prompt_command "prompt" @keyword)
(on_key_command "on-key" @keyword)
(select_command "select" @keyword)
(complete_command "complete-command" @keyword)
(complete_command
  type: (completion_type) @type.builtin)

; Generic command names
(command
  name: (command_name) @function)

; Define-command name gets special treatment
(define_command
  name: (command_name) @function.definition)

; Strings
(single_quoted_string) @string
(double_quoted_string) @string

; Percent strings
(percent_string) @string

; Block body string content — fallback when injection isn't available
(block_body (string_content) @string)

; Expansions
(expansion_type) @keyword.directive
(expansion) @embedded

; Hook names
(hook_definition
  name: (word) @constant)

; Face names
(set_face
  name: (word) @variable.other.member)

; Option names
(set_option
  name: (word) @variable.other.member)
(unset_option
  name: (word) @variable.other.member)
(declare_option
  name: (word) @variable.other.member)

; Module names
(provide_module
  name: (word) @module)
(require_module
  name: (word) @module)

; Alias names
(alias_definition
  name: (word) @variable.other.member)
(unalias_definition
  name: (word) @variable.other.member)

; Register names
(set_register
  name: (word) @variable.other.member)

; User mode names
(declare_user_mode
  name: (word) @constant)
(enter_user_mode
  name: (word) @constant)

; Complete-command target name
(complete_command
  name: (word) @function)

; Remove-hooks group
(remove_hooks
  group: (word) @variable.other.member)

; Scopes
(scope) @constant.builtin

; Highlighter path: scope name and type
(highlighter_path
  name: (word) @variable.other.member)
(add_highlighter
  type: (word) @function)
(path_separator) @punctuation.delimiter

; Modes
(mode) @constant.builtin

; Option types
(option_type) @type.builtin

; Switches (includes aliased _keyword_switch and _plain_switch)
(switch) @variable.parameter

; Switch terminator
(switch_terminator) @punctuation.delimiter

; Comments
(comment) @comment
