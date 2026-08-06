#--------------------------------
# LocalLeader Mode
# -------------------------------
declare-user-mode local
map global local ',' ':toggle-comasemi ,<ret>' -docstring 'Toggle comma'
map global local ';' ':toggle-comasemi \;<ret>' -docstring 'Toggle semicolon'
map global local g ':enter-user-mode local-goto<ret>' -docstring 'Goto Mode'
map global local n ':tree-next-sibling<ret>' -docstring 'next sibling'
map global local p ':tree-prev-sibling<ret>' -docstring 'prev sibling'

declare-user-mode local-goto
map global local-goto e ':e -existing .env<ret>' -docstring 'ENV file'
map global local-goto l ':e -existing storage/logs/laravel.log<ret>' -docstring 'Log file'
map global local-goto p ':e -existing package.json<ret>' -docstring 'Package json'
map global local-goto c ':e -existing composer.json<ret>' -docstring 'Composer json'
map global local-goto C ':e -existing Cargo.toml<ret>' -docstring 'Cargo toml'
map global local-goto u ':e -existing pubspec.yaml<ret>' -docstring 'p[u]bspec.yaml'

# tree-sitter
map global user t ':enter-user-mode tree<ret>' -docstring 'tree-sitter'

# Toggle Mode
declare-user-mode toggle
map global user T ":enter-user-mode toggle<ret>" -docstring "toggle..."
map global toggle i ':show-tab-info<ret>' -docstring "tab settings"
define-command show-tab-info %{
  info -title "tab settings" "tabstop: %opt{tabstop}
softtabstop: %opt{softtabstop}
indentwidth: %opt{indentwidth}"
}
map global toggle s ':show-session-info<ret>' -docstring "session info"
define-command -hidden show-session-info %{
  info -title "session info" "%val{client}/%val{session}
%sh{pwd}"
}
map global toggle t ":grep '(BUG|FIXME|TODO|TEMPORARY):'<ret>" -docstring "TODOs"

# -------------------------------
# Search
# -------------------------------
declare-user-mode search
map global user s ':enter-user-mode search<ret>' -docstring 'search'
map global search s ':syms<ret>'                 -docstring 'Symbols (Project)'
map global search S ':syms -buffer<ret>'         -docstring 'Symbols (Buffer)'
map global search y ':enter-user-mode symbol<ret>' -docstring 'Symbols by kind'
map global search w ':swiper-search<ret>'        -docstring 'search current buffer'
map global search r ':swiper-resume<ret>'        -docstring 'swiper-resume'
map global search k ':find-and-replace<ret>'     -docstring 'find and replace'

# -------------------------------
# Symbol Kind Mode
# -------------------------------
declare-user-mode symbol
map global symbol f ':syms -kind fn<ret>'          -docstring 'functions'
map global symbol m ':syms -kind method<ret>'      -docstring 'methods'
map global symbol c ':syms -kind class<ret>'       -docstring 'classes'
map global symbol s ':syms -kind struct<ret>'      -docstring 'structs'
map global symbol e ':syms -kind enum<ret>'        -docstring 'enums'
map global symbol t ':syms -kind type<ret>'        -docstring 'types'
map global symbol i ':syms -kind interface<ret>'   -docstring 'interfaces'
map global symbol k ':syms -kind const<ret>'       -docstring 'constants'
map global symbol M ':syms -kind mod<ret>'         -docstring 'modules'
map global symbol T ':syms -kind trait<ret>'       -docstring 'traits'
map global symbol C ':syms -kind component<ret>'   -docstring 'components'
map global symbol h ':syms -kind hook<ret>'        -docstring 'hooks'
map global symbol x ':syms -kind test<ret>'        -docstring 'tests'
map global symbol p ':syms -exported<ret>'         -docstring 'public/exported'

# -------------------------------
# Spell
# -------------------------------
declare-user-mode spell
map -docstring 'autospell toggle' global spell t ': autospell-toggle<ret>'
map -docstring 'show spell' global spell s ': spell<ret>'
map -docstring 'spell next' global spell i ': spell-next<ret>'
map -docstring 'spell prev' global spell m ': spell-prev<ret>'
map -docstring 'spell clear' global spell c ': spell-clear<ret>'
map -docstring 'spell add' global spell a ': spell-add<ret>'
map -docstring 'spell replace' global spell r ': spell-replace<ret>'

#--------------------------------
# Match Mode
# -------------------------------
declare-user-mode match
map -docstring 'Goto matching bracket' global match m m
map -docstring 'Select inner object' global match i <a-i>
map -docstring 'Select around object' global match a <a-a>
map -docstring 'Surround delete' global match d ':match-delete-surround<ret>'
map -docstring 'Surrounding replace' global match r ':surround-replace<ret>'
map -docstring 'Surrounding add' global match s ':enter-user-mode surround-add<ret>' 

declare-user-mode match-extend
map global match-extend a '<A-a>' -docstring 'Extend around object'
map global match-extend i '<A-i>' -docstring 'Extend inner object'
map global match-extend A '<A-a>' -docstring 'Extend around object'
map global match-extend I '<A-i>' -docstring 'Extend inner object'
map global match-extend m M -docstring 'Extend matching delimiter'
map global match-extend M M -docstring 'Extend matching delimiter'

# -------------------------
# Git Mode — magit porcelain (magit.kak) + magit-git.kak low-level layer.
# -------------------------
declare-user-mode git
map global user g ':enter-user-mode git<ret>' -docstring 'magit'

# --- Top-level entry points ---------------------------------------------
map global git g     ':magit-status<ret>'                  -docstring 'magit status'
map global git l     ':magit-log<ret>'                     -docstring 'log'
map global git L     ':magit-reflog<ret>'                  -docstring 'HEAD reflog'
map global git b     ':magit-branch-dispatch<ret>'         -docstring 'branches buffer'

# --- Buffer-local operations (gutter, blame, hunk nav, stage-selection) -
map global git n     ':magit-next-hunk<ret>'               -docstring 'next hunk'
map global git p     ':magit-prev-hunk<ret>'               -docstring 'previous hunk'
map global git m     ':magit-blame-toggle<ret>'            -docstring 'toggle blame'
map global git s     ':magit-stage-selection<ret>'         -docstring 'stage selection'
map global git u     ':magit-unstage-selection<ret>'       -docstring 'unstage selection'
map global git <ret> ':magit-log-line<ret>'                -docstring 'commit for current line'

# --- Diff -----------------------------------------------------------------
map global git d     ':magit-diff-dispatch<ret>'           -docstring 'diff (menu)'
map global git D     ':magit-diff-staged<ret>'             -docstring 'diff staged preview'
map global git "'"   ':magit-diff-dwim<ret>'               -docstring 'diff (context-aware)'

# --- Commit + sequence verbs ---------------------------------------------
map global git c     ':magit-commit-dispatch<ret>'         -docstring 'commit transient'
map global git P     ':magit-push-transient<ret>'          -docstring 'push transient'
map global git F     ':magit-fetch-transient<ret>'         -docstring 'fetch transient'
map global git f     ':magit-pull-transient<ret>'          -docstring 'pull transient'
map global git M     ':magit-merge-transient<ret>'         -docstring 'merge transient'
map global git A     ':magit-cherry-transient<ret>'        -docstring 'cherry-pick transient'
map global git V     ':magit-revert-transient<ret>'        -docstring 'revert transient'
map global git r     ':magit-rebase-transient<ret>'        -docstring 'rebase transient'

# --- Repo-scoped transients ----------------------------------------------
map global git t     ':magit-tag-transient<ret>'           -docstring 'tag transient'
map global git X     ':magit-reset-transient<ret>'         -docstring 'reset transient'
map global git e     ':magit-remote-transient<ret>'        -docstring 'remote transient'
map global git z     ':magit-stash-transient<ret>'         -docstring 'stash (create) transient'
map global git w     ':magit-worktree-dispatch<ret>'       -docstring 'worktree transient'
map global git o     ':magit-submodule-dispatch<ret>'      -docstring 'submodule transient'
map global git i     ':magit-bisect-dispatch<ret>'         -docstring 'bisect transient'
map global git C     ':magit-clone-dispatch<ret>'          -docstring 'clone transient'
map global git I     ':magit-gitignore-dispatch<ret>'      -docstring 'gitignore transient'
map global git N     ':magit-patch-dispatch<ret>'          -docstring 'patch transient (create/apply/am)'

# --- Working-tree helpers -------------------------------------------------
map global git x     ':enter-user-mode magit-conflict<ret>' -docstring 'conflict resolve'
map global git .     ':magit-file-dispatch<ret>'           -docstring 'file dispatch (this file)'
map global git W     ':magit-wip-toggle<ret>'              -docstring 'toggle WIP auto-snapshot'

declare-user-mode magit-conflict
map global magit-conflict n ': magit-conflict-next<ret>'   -docstring 'next conflict'
map global magit-conflict p ': magit-conflict-prev<ret>'   -docstring 'previous conflict'
map global magit-conflict o ': magit-conflict-ours<ret>'   -docstring 'keep ours'
map global magit-conflict t ': magit-conflict-theirs<ret>' -docstring 'keep theirs'
map global magit-conflict b ': magit-conflict-both<ret>'   -docstring 'keep both'

# --------------------------------
# Surround Mode
# --------------------------------
declare-user-mode surround-add
map global surround-add "'" ":add-surrounding-pair ""'"" ""'""<ret>" -docstring 'surround selections with quotes'
map global surround-add ' ' ':add-surrounding-pair " " " "<ret>' -docstring 'surround selections with pipes'
map global surround-add '"' ':add-surrounding-pair ''"'' ''"''<ret>' -docstring 'surround selections with double quotes'
map global surround-add '(' ':add-surrounding-pair ( )<ret>' -docstring 'surround selections with curved brackets'
map global surround-add ')' ':add-surrounding-pair ( )<ret>' -docstring 'surround selections with curved brackets'
map global surround-add '*' ':add-surrounding-pair * *<ret>' -docstring 'surround selections with stars'
map global surround-add '<' ':add-surrounding-pair <lt> <gt><ret>' -docstring 'surround selections with chevrons'
map global surround-add '>' ':add-surrounding-pair <lt> <gt><ret>' -docstring 'surround selections with chevrons'
map global surround-add '[' ':add-surrounding-pair [ ]<ret>' -docstring 'surround selections with square brackets'
map global surround-add ']' ':add-surrounding-pair [ ]<ret>' -docstring 'surround selections with square brackets'
map global surround-add '_' ':add-surrounding-pair "_" "_"<ret>' -docstring 'surround selections with underscores'
map global surround-add '{' ':add-surrounding-pair { }<ret>' -docstring 'surround selections with angle brackets'
map global surround-add '|' ':add-surrounding-pair | |<ret>' -docstring 'surround selections with pipes'
map global surround-add '}' ':add-surrounding-pair { }<ret>' -docstring 'surround selections with angle brackets'
map global surround-add '«' ':add-surrounding-pair « »<ret>' -docstring 'surround selections with French chevrons'
map global surround-add '»' ':add-surrounding-pair « »<ret>' -docstring 'surround selections with French chevrons'
map global surround-add '“' ':add-surrounding-pair “ ”<ret>' -docstring 'surround selections with French chevrons'
map global surround-add '”' ':add-surrounding-pair “ ”<ret>' -docstring 'surround selections with French chevrons'
map global surround-add ` ':add-surrounding-pair ` `<ret>' -docstring 'surround selections with ticks'
map global surround-add t ':surround-tag<ret>' -docstring 'surround selections with a <tag>'

define-command -hidden match-delete-surround -docstring 'delete surrounding key' %{
  on-key %{
    match-delete-surround-key %val{key}
  }
}

define-command -hidden match-delete-surround-key -params 1 %{
  execute-keys -draft "<a-a>%arg{1}i<del><esc>a<backspace><esc>"
}

define-command -hidden add-surrounding-pair -params 2 -docstring 'add surrounding pairs left and right to selection' %{
  evaluate-commands -no-hooks -save-regs '"' %{
    set-register '"' %arg{1}
    execute-keys -draft P
    set-register '"' %arg{2}
    execute-keys -draft p
  }
}

define-command -hidden surround-key -docstring 'surround key' %{
  on-key %{
    add-surrounding-pair %val{key} %val{key}
  }
}

define-command -hidden surround-tag -docstring 'surround tag' %{
  prompt surround-tag: %{
    add-surrounding-pair "<%val{text}>" "</%val{text}>"
  }
}

define-command -hidden surround-replace -docstring 'prompt for a surrounding pair and replace it with another' %{
  on-key %{
    surround-replace-sub %val{key}
  }
}

define-command -hidden surround-replace-sub -params 1 %{
  on-key %{
    evaluate-commands -no-hooks -draft %{
      execute-keys "<a-a>%arg{1}"

      # select the surrounding pair and add the new one around it
      enter-user-mode surround-add
      execute-keys %val{key}
    }

    # delete the old one
    match-delete-surround-key %arg{1}
  }
}
