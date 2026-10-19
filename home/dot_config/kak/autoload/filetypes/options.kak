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

# PHP snippets
hook global WinSetOption filetype=php %{
    set-option -add buffer snippets \
          "Function"           "fn" "snippets-insert '${1:public }function ${2:FunctionName}(${3:Type} \$${4:var}${5: = null}) {$n    ${0:# code...}$n}'" \
          "For Loop"          "for" "snippets-insert 'for (\$${1:i}=${2:0}; \$${1:i} < ${3:count}; \$${1:i}++) {$n    ${0:# code...}$n}'" \
          "Foreach loop"     "fore" "snippets-insert 'foreach (\$${1:variable} as \$${2:key}${3: => \$value}) {$n    ${0:# code...}$n}'" \
          "Try catch"         "try" "snippets-insert 'try {$n    ${1://code...}$n} catch (${2:Throwable} ${3:\$th}) {$n    ${4://throw \$th;}$n}'" \
          "Throw exception" "throw" %{snippets-insert %{throw new ${1:Runtime}Exception("${2:Error Processing Request}");}} \
          "Switch block"   "switch" "snippets-insert 'switch (\$${1:variable}) {$n    case ''${2:value}'':$n        ${3:# code...}$n        break;$n    ${4}$n    default:$n        ${0:# code...}$n break;$n}'" \
          "Case Block"       "case" "snippets-insert 'case ''${1:value}'':$n    ${2:# code...}$n    break;'" \
          "Do-While loop"      "do" "snippets-insert 'do {$n    ${1:# code...}$n} while (${2:\$i <= 10});'" \
          "While-loop"      "while" "snippets-insert 'while (${1:\$i <= 10}) {$n    ${0:# code...}$n}'" \
          "If block"           "if" "snippets-insert 'if (${1:condition}) {$n    ${0:# code...}$n}'" \
          "If Else block"  "ifelse" "snippets-insert 'if (${1:condition}) {$n    ${2:# code...}$n} else {$n    ${3:# code...}$n}$n${0}'" \
          "Ternary if/else"   "if?" "snippets-insert '\$${1:retVal} = (${2:condition}) ? ${3:a} : ${4:b};'" \
          "Echo"                "e" %{snippets-insert %{echo "${1:string}";}} \
          "Log debug"        "logd" %{snippets-insert %{Log::debug("${1:message}");}} \
          "Log info"         "logi" %{snippets-insert %{Log::info("${1:message}");}} \
          "Log notice"       "logn" %{snippets-insert %{Log::notice("${1:message}");}} \
          "Log warning"      "logw" %{snippets-insert %{Log::warning("${1:message}");}} \
          "Log error"        "loge" %{snippets-insert %{Log::error("${1:message}");}} \
          "Log critical"     "logc" %{snippets-insert %{Log::critical("${1:message}");}} \
          "Log alert"        "loga" %{snippets-insert %{Log::alert("${1:message}");}} \
          "Log emergency"   "logem" %{snippets-insert %{Log::emergency("${1:message}");}} \
          "$this->..."       "this" "snippets-insert '\$this->${1:val};'" \
          "Echo this"       "ethis" "snippets-insert 'echo \$this->${1:val};'"
}

# Javascript snippets
hook global WinSetOption filetype=(javascript|typescript|tsx) %{
    set-option -add buffer snippets \
          "Console Log" "cl" %{snippets-insert %{console.log('${1:message}');}} \
          "Console variable" "cv" %{snippets-insert %{console.log('${1}:', ${1});}} \
          "Console Error" "ce" %{snippets-insert %{console.error('${1:message}');}} \
          "Console Warn" "cw" %{snippets-insert %{console.warn('${1:message}');}}
}

