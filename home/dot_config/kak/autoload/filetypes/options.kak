define-command -hidden -params 2 config-set-formatter %{
	evaluate-commands %sh{ echo "
		hook global WinSetOption \"filetype=$1\" %{
			set-option buffer formatcmd '$2'
			hook -once -always buffer WinSetOption filetype=.* %{
				unset-option buffer formatcmd
			}
		}
	" }
}

define-command -hidden -params 2 config-set-linter %{
	evaluate-commands %sh{ echo "
		hook global WinSetOption \"filetype=$1\" %{
			set-option buffer lintcmd '$2'
			hook -once -always buffer WinSetOption filetype=.* %{
				unset-option buffer lintcmd
			}
		}
	" }
}

# PHP
hook global WinSetOption filetype=php %{
    map -docstring "format" buffer normal <a-=> ": format-php<ret>"
}

# Dart
hook global WinSetOption filetype=dart %{
    map -docstring "format" buffer normal <a-=> ": format-dart<ret>"
}

define-command format-php %{ eval %sh{ pint --silent -n "$kak_buffile" } }
define-command format-dart %{ eval %sh{ dart format "$kak_buffile" } }

define-command -hidden -params 1 lint-by %{
    set buffer lintcmd %arg{1}
    lint-buffer
}

# Formatters
config-set-formatter css        'dprint fmt --stdin css'
config-set-formatter json       'dprint fmt --stdin json'
config-set-formatter jsonc      'dprint fmt --stdin jsonc'
config-set-formatter yaml       'dprint fmt --stdin yaml'
config-set-formatter html       'dprint fmt --stdin html'
config-set-formatter toml       'dprint fmt --stdin toml'
config-set-formatter javascript 'dprint fmt --stdin js'
config-set-formatter typescript 'dprint fmt --stdin ts'
config-set-formatter jsx        'dprint fmt --stdin jsx'
config-set-formatter tsx        'dprint fmt --stdin tsx'
# config-set-formatter astro      'dprint fmt --stdin astro'
config-set-formatter rust       'rustfmt'
config-set-formatter liquid     'dprint fmt --stdin liquid'
