; Command definitions (define-command)
(define_command
  body: (_) @function.inside) @function.around

; Modules (provide-module)
(provide_module
  body: (_) @class.inside) @class.around

; Comments
(comment) @comment.inside

(comment)+ @comment.around

; Command arguments and switch values
(command
  (argument) @parameter.inside)

(set_option
  value: (argument) @parameter.inside)

; Config entries — hooks, maps, highlighters, options, etc.
(hook_definition) @entry.around

(hook_definition
  body: (_) @entry.inside)

(map_definition) @entry.around

(set_option) @entry.around

(add_highlighter) @entry.around

(set_face) @entry.around

(alias_definition) @entry.around

(try_statement) @entry.around

(try_statement
  body: (_) @entry.inside)
