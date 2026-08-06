; Command definitions
(define_command
  name: (command_name) @name) @definition.function

; Module definitions
(provide_module
  name: (word) @name) @definition.module

; Option declarations
(declare_option
  type: (option_type) @type
  name: (word) @name) @definition.var

; User mode declarations
(declare_user_mode
  name: (word) @name) @definition.type

; Alias definitions
(alias_definition
  name: (word) @name
  command: (word)) @definition.function

; Hook definitions (named groups)
(hook_definition
  (switch
    (word) @name)) @reference.call

; Module references
(require_module
  name: (word) @name) @reference.module

; Source imports
(source_command
  filename: (argument) @name) @reference.call
