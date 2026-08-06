; Inject bash into -shell-script-candidates and -shell-script switch values
((switch
  (percent_string
    content: (string_content) @injection.content)) @_sw
  (#match? @_sw "^-shell-script")
  (#set! injection.language "bash")
  (#set! injection.include-children))

; Inject bash into complete-command shell-script-candidates param
((complete_command
  type: (completion_type) @_type
  param: (argument
    (percent_string
      content: (string_content) @injection.content)))
  (#match? @_type "^shell-script")
  (#set! injection.language "bash")
  (#set! injection.include-children))

; Inject bash into %sh{...} expansion content (works at any nesting level)
((expansion
  type: (expansion_type) @_type
  content: (string_content) @injection.content)
 (#eq? @_type "sh")
 (#set! injection.language "bash"))

; Self-inject kak into block body string_content segments
; (the string_content between expansions in block_body nodes)
(try_statement
  body: (block_body
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(try_statement
  body: (expansion
    content: (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(try_statement
  handler: (block_body
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(try_statement
  handler: (expansion
    content: (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(try_statement
  body: (single_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(try_statement
  body: (double_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(try_statement
  handler: (single_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(try_statement
  handler: (double_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(hook_definition
  body: (block_body
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(hook_definition
  body: (expansion
    content: (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(hook_definition
  body: (single_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(hook_definition
  body: (double_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(define_command
  body: (block_body
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(define_command
  body: (expansion
    content: (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(define_command
  body: (single_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(define_command
  body: (double_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(provide_module
  body: (block_body
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(provide_module
  body: (expansion
    content: (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(provide_module
  body: (single_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(provide_module
  body: (double_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(evaluate_commands
  (argument
    (percent_string
      content: (string_content) @injection.content))
  (#set! injection.language "kak")
  (#set! injection.include-children))

(evaluate_commands
  (argument
    (expansion
      content: (string_content) @injection.content))
  (#set! injection.language "kak")
  (#set! injection.include-children))

(evaluate_commands
  (argument
    (single_quoted_string
      (string_content) @injection.content))
  (#set! injection.language "kak")
  (#set! injection.include-children))

(evaluate_commands
  (argument
    (double_quoted_string
      (string_content) @injection.content))
  (#set! injection.language "kak")
  (#set! injection.include-children))

(prompt_command
  body: (block_body
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(prompt_command
  body: (expansion
    content: (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(prompt_command
  body: (single_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(prompt_command
  body: (double_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(on_key_command
  body: (block_body
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(on_key_command
  body: (expansion
    content: (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(on_key_command
  body: (single_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))

(on_key_command
  body: (double_quoted_string
    (string_content) @injection.content)
  (#set! injection.language "kak")
  (#set! injection.include-children))
