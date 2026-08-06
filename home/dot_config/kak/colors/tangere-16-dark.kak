# Tangere 16-color dark theme for Kakoune
# Author: François Tonneau

# Builtin

set-face global PrimaryCursor               black,white+b
set-face global PrimaryCursorEol            black,white+b
set-face global SecondaryCursor             black,bright-black+b
set-face global SecondaryCursorEol          black,bright-black+b
set-face global PrimarySelection            black,green
set-face global SecondarySelection          default,bright-white

set-face global BufferPadding               bright-white
set-face global DiagnosticError             red,+b
set-face global DiagnosticWarning           yellow,+b
set-face global Error                       black,red
set-face global Information                 default,bright-white+i
set-face global InlineInformation           default,bright-white
set-face global LineNumberCursor            default,+b
set-face global LineNumbers                 bright-black
set-face global LineNumbersWrapped          bright-white
set-face global MatchingChar                default,+biu
set-face global MenuBackground              default,bright-white
set-face global MenuForeground              black,bright-black+fg
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
set-face global keyword                     cyan,+bi
set-face global meta                        +i
set-face global module                      cyan,+b
set-face global operator                    default
set-face global string                      bright-yellow
set-face global type                        blue,+b
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

set-face global adjunct                     white
set-face global distinct                    bright-cyan,+i
set-face global emphatic                    +i
set-face global faded                       bright-black
set-face global salient                     yellow,+ba
set-face global strong                      +b

# Mode changes

remove-hooks global tangere-.*

hook -group tangere-16-dark global ModeChange push:.*:insert %{
    set-face window PrimaryCursor           black,red+bu
    set-face window PrimaryCursorEol        black,red+bu
    set-face window SecondaryCursor         black,red+b
    set-face window SecondaryCursorEol      black,red+b
    set-face window SecondarySelection      black,green
    set-face window MatchingChar            default
}

hook -group tangere-16-dark global ModeChange pop:insert:.* %{
    set-face window PrimaryCursor           black,white+b
    set-face window PrimaryCursorEol        black,white+b
    set-face window SecondaryCursor         black,bright-black+b
    set-face window SecondaryCursorEol      black,bright-black+b
    set-face window SecondarySelection      default,bright-white
    set-face window MatchingChar            default,+biu
}

