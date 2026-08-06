# Tangere 17-color light theme for Kakoune
# Author: François Tonneau

# Builtin

set-face global PrimaryCursor               black,bright-cyan+b
set-face global PrimaryCursorEol            black,bright-cyan+b
set-face global SecondaryCursor             black,white+b
set-face global SecondaryCursorEol          black,white+b
set-face global PrimarySelection            default,bright-white
set-face global SecondarySelection          default,rgb:e6e4d3

set-face global BufferPadding               white
set-face global DiagnosticError             red,+b
set-face global DiagnosticWarning           yellow,+b
set-face global Error                       black,red
set-face global Information                 default,bright-white+i
set-face global InlineInformation           default,bright-white
set-face global LineNumberCursor            default,+b
set-face global LineNumbers                 white
set-face global LineNumbersWrapped          white
set-face global MatchingChar                default,+biu
set-face global MenuBackground              default,bright-white
set-face global MenuForeground              black,cyan+fg
set-face global MenuInfo                    default,bright-white+i

set-face global Prompt                      default,+b
set-face global StatusLine                  default,bright-white
set-face global StatusLineMode              default,+b
set-face global StatusLineInfo              default,+b
set-face global StatusLineValue             default
set-face global StatusCursor                default,+u

set-face global Whitespace                  white
set-face global WrapMarker                  red,+b

# Custom

set-face global LineNumbersSeparator        bright-white

# Code

set-face global attribute                   default
set-face global builtin                     +i
set-face global comment                     cyan,+i
set-face global documentation               bright-yellow,+i
set-face global function                    green,+b
set-face global keyword                     blue,+bi
set-face global meta                        +i
set-face global module                      blue,+b
set-face global operator                    default
set-face global string                      bright-yellow
set-face global type                        cyan,+bi
set-face global value                       cyan,+b
set-face global variable                    default

# Lsp

set-face global DiagnosticError             default
set-face global DiagnosticHint              default
set-face global DiagnosticInfo              default
set-face global DiagnosticWarning           default

set-face global DiagnosticTagDeprecated     default
set-face global DiagnosticTagUnnecessary    default

set-face global InlayDiagnosticError        comment
set-face global InlayDiagnosticHint         comment
set-face global InlayDiagnosticInfo         comment
set-face global InlayDiagnosticWarning      comment

set-face global InlayCodeLens               comment
set-face global InlayHint                   comment

set-face global LineFlagError               white
set-face global LineFlagHint                white
set-face global LineFlagInfo                white
set-face global LineFlagWarning             white

set-face global Reference                   default
set-face global ReferenceBind               default

set-face global SnippetsNextPlaceholders    black,green
set-face global SnippetsOtherPlaceholders   black,yellow

# Markup

set-face global block                       @distinct
set-face global bullet                      @faded
set-face global header                      @strong
set-face global link                        @salient
set-face global list                        default
set-face global mono                        @adjunct
set-face global title                       @strong

set-face global adjunct                     cyan
set-face global distinct                    bright-cyan,+i
set-face global emphatic                    +i
set-face global faded                       white
set-face global salient                     yellow,+ba
set-face global strong                      +b

# Mode changes

remove-hooks global tangere-.*

hook -group tangere-16-light global ModeChange push:.*:insert %{
    set-face window PrimaryCursor           black,red+bu
    set-face window PrimaryCursorEol        black,red+bu
    set-face window SecondaryCursor         black,red+b
    set-face window SecondaryCursorEol      black,red+b
    set-face window PrimarySelection        default,rgb:e6e4d3
    set-face window MatchingChar            default
}

hook -group tangere-16-light global ModeChange pop:insert:.* %{
    set-face window PrimaryCursor           black,bright-cyan+b
    set-face window PrimaryCursorEol        black,bright-cyan+b
    set-face window SecondaryCursor         black,white+b
    set-face window SecondaryCursorEol      black,white+b
    set-face window PrimarySelection        default,bright-white
    set-face window MatchingChar            default,+biu
}

