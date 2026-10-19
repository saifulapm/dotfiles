hook global -group window-display WinDisplay .* %{
  set-option -add global ui_options "terminal_title=%val{bufname}"
  # Diff gutter hooks (WinDisplay/FocusIn/BufReload/BufWritePost) live in
  # autoload/tools/magit-git.kak under the magit-gutter group.
}

hook global -group trim-indent ModeChange pop:insert:.* trim-indent

# Avoid the escape key
hook global InsertChar j %{
  try %{
    exec -draft hH <a-k>jj<ret> d
    exec -with-hooks <esc>
  }
}

# hook global InsertChar \n indent_on_inserted_character_with_indentation_rules

hook global RuntimeError "1:1: '(?:e|edit|o|open)': (.+): is a directory" %{
  ls %val{hook_param_capture_1}
}

declare-option -hidden str-list js_linters 'Eslint' 'lint-by eslint' 'Biome' 'lint-by biome'
hook global RuntimeError "The lintcmd option is not set" %{
  evaluate-commands %sh{
    if [ $kak_opt_filetype == 'javascript' ] || [ $kak_opt_filetype == 'typescript' ] || [ $kak_opt_filetype == 'tsx' ]; then
      echo "menu $kak_js_linters"
    fi
  }
}

hook global BufSetOption formatcmd=.+ %{
  hook -group format-hook buffer BufWritePre .* format
  hook -once -always buffer BufSetOption formatcmd= %{
    remove-hooks buffer format-hook
  }
}

hook global BufSetOption lintcmd=.+ %{
  hook -group lint-hook buffer BufWritePost .* lint
  hook -once -always buffer BufSetOption lintcmd= %{
    remove-hooks buffer lint-hook
  }
}

# git-branches / git_blame filetype hooks: git-extra.kak stays disabled.
# If we need them later, port into magit-git.kak.

hook global BufCreate .*/\.claude/plans/.* %{
  add-highlighter buffer/wrap wrap -word -indent
}

declare-option -hidden str js_linter_lsp
hook global KakBegin .* %{
  evaluate-commands %sh{
    if [ -f "eslint.config.js" ] || [ -f "eslint.config.mjs" ] || [ -f "eslint.config.ts" ]; then
      echo "set-option global js_linter_lsp eslint"
    elif [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
      echo "set-option global js_linter_lsp biome"
    fi
  }
}
