# Load Plugin
evaluate-commands %sh{kak-lsp}

# removing all default hooks
remove-hooks global lsp-filetype-.*
remove-hooks global lsp-language-id

# workspace/didChangeWatchedFiles
set-option global lsp_file_watch_support true

# lsp debug
# set global lsp_debug true

# snippets
set-option global lsp_snippet_support true

# Disable semantic token
# set-option global lsp_semantic_tokens []

hook -group lsp-enable global WinSetOption filetype=(rust|php|dart|javascript|typescript|tsx|astro|liquid) %{
	lsp-enable-window
    # lsp-inlay-hints-enable window
}

declare-option -hidden str biome_server %{
    [biome]
    root_globs = ["biome.json", "package.json", "tsconfig.json", "jsconfig.json", ".git", ".hg"]
    args = ["lsp-proxy"]
}

declare-option -hidden str eslint_server %{
    [eslint]
    command = "eslint-language-server"
    root_globs = ["eslint.config.js", "eslint.config.mjs", "eslint.config.ts"]
    args = ["--stdio"]
    workaround_eslint = true
    [eslint.settings]
    nodePath = ""
    run = "onType"
    validate = "on"
    workingDirectory = { mode = 'auto' }
    packageManager = "pnpm"
    useESLintClass = false
    useFlatConfig = true
    format = false
    quiet = false
    rulesCustomizations = [
        { rule = 'style/*', severity = 'off', fixable = true },
        { rule = 'format/*', severity = 'off', fixable = true },
        { rule = '*-indent', severity = 'off', fixable = true },
        { rule = '*-spacing', severity = 'off', fixable = true },
        { rule = '*-spaces', severity = 'off', fixable = true },
        { rule = '*-order', severity = 'off', fixable = true },
        { rule = '*-dangle', severity = 'off', fixable = true },
        { rule = '*-newline', severity = 'off', fixable = true },
        { rule = '*quotes', severity = 'off', fixable = true },
        { rule = '*semi', severity = 'off', fixable = true }
    ]
    problems = { shortenToSingleLine = false }
    codeAction.disableRuleComment = {enable = true, location = "separateLine"}
    codeAction.showDocumentation = {enable = true}
}

declare-option -hidden str vtsls_server %{
    [vtsls]
    args = [ "--stdio" ]
    root_globs = ["package.json", "tsconfig.json", "jsconfig.json", ".git", ".hg"]
    settings_section = "_"
    [vtsls.settings._]
    complete_function_calls = true
    vtsls.enableMoveToFileCodeAction = false
    vtsls.autoUseWorkspaceTsdk = true
    vtsls.experimental.maxInlayHintLength = 30
    vtsls.experimental.completion.enableServerSideFuzzyMatch = true
    typescript.updateImportsOnFileMove.enabled = "always"
    typescript.suggest.completeFunctionCalls = true
    typescript.tsserver.maxTsServerMemory = 16384
    # typescript.tsserver.log = "verbose"  # Disabled for performance
    typescript.inlayHints.enumMemberValues.enabled = true
    typescript.inlayHints.functionLikeReturnTypes.enabled = true
    typescript.inlayHints.parameterNames.enabled = "literals"
    typescript.inlayHints.parameterNames.suppressWhenArgumentMatchesName = false
    typescript.inlayHints.parameterTypes.enabled = true
    typescript.inlayHints.propertyDeclarationTypes.enabled = true
    typescript.inlayHints.variableTypes.enabled = false
    typescript.inlayHints.variableTypes.suppressWhenArgumentMatchesName = true
}

declare-option -hidden str astro_server %{
    [astro-ls]
    args = [ "--stdio" ]
    root_globs = ["package.json", "tsconfig.json", "jsconfig.json", ".git", ".hg"]
    settings_section = "_"
    [astro-ls.settings._]
    typescript = {tsdk = "node_modules/typescript/lib"}
}

hook -group lsp-filetype-php global BufSetOption filetype=php %{
    set-option buffer lsp_servers %{
        [intelephense]
        root_globs = [".htaccess", "composer.json"]
        args = ["--stdio"]
        settings_section = "_"
        [intelephense.settings._]
        storagePath = "/tmp/intelephense"
        licenceKey = "00RGAST1YB2NVQ5"
    }
}

hook -group lsp-filetype-rust global BufSetOption filetype=rust %{
    set-option buffer lsp_servers %{
        [rust-analyzer]
        root_globs = ["Cargo.toml"]
        single_instance = true
        [rust-analyzer.experimental]
        commands.commands = ["rust-analyzer.runSingle"]
        hoverActions = true
        [rust-analyzer.settings.rust-analyzer]
        # See https://rust-analyzer.github.io/manual.html#configuration
        # cargo.features = []
        check.command = "clippy"
        [rust-analyzer.symbol_kinds]
        Constant = "const"
        Enum = "enum"
        EnumMember = ""
        Field = ""
        Function = "fn"
        Interface = "trait"
        Method = "fn"
        Module = "mod"
        Object = ""
        Struct = "struct"
        TypeParameter = "type"
        Variable = "let"
    }
}

hook -group lsp-filetype-dart global BufSetOption filetype=dart %{
    set-option buffer lsp_servers %{
        [dart-lsp]
        root_globs = ["pubspec.yaml", ".git", ".hg"]
        command = "dart"
        args = ["language-server", "--protocol=lsp"]
        settings_section = "_"
        [dart-lsp.settings._]
        onlyAnalyzeProjectsWithOpenFiles = true
        suggestFromUnimportedLibraries = true
        closingLabels = false
        outline = false
        flutterOutline = false
    }
}

hook -group lsp-filetype-ruby global BufSetOption filetype=ruby %{
    set-option buffer lsp_servers %{
        [ruby-lsp]
        args = ["stdio"]
        root_globs = ["Gemfile"]
    }
}


hook -group lsp-filetype-javascript global BufSetOption filetype=(?:javascript|typescript|tsx) %{
    set-option buffer lsp_servers %sh{
        echo "${kak_opt_vtsls_server}"
        if [ "$kak_opt_js_linter_lsp" = "eslint" ]; then
            echo "${kak_opt_eslint_server}"
        elif [ "$kak_opt_js_linter_lsp" = "biome" ]; then
            echo "${kak_opt_biome_server}"
        fi
    }
}

hook -group lsp-filetype-astro global BufSetOption filetype=astro %{
    set-option buffer lsp_servers %sh{
        echo "${kak_opt_astro_server}"
        if [ "$kak_opt_js_linter_lsp" = "eslint" ]; then
            echo "${kak_opt_eslint_server}"
        elif [ "$kak_opt_js_linter_lsp" = "biome" ]; then
            echo "${kak_opt_biome_server}"
        fi
    }
}

hook global BufSetOption filetype=liquid %{
    set-option buffer lsp_servers %{
        [shopify-theme-language-server]
        command = "shopify"
        args = ["theme", "language-server"]
        root_globs = [".theme-check.yml", ".shopify", "config/settings_schema.json", ".git"]
    }
}

## Language ID
hook -group lsp-language-id global BufSetOption filetype=((?!javascript)(?!typescript)(?!tsx).*) %{
    set-option buffer lsp_language_id %val{hook_param_capture_1}
}

hook -group lsp-language-id global BufSetOption filetype=javascript %{
    try %{
        "lsp-nop-with-0%opt{lsp_language_id}"
        set-option buffer lsp_language_id javascript
    }
}

hook -group lsp-language-id global BufCreate .*[.]jsx %{
    set-option buffer lsp_language_id javascriptreact
}

hook -group lsp-language-id global BufSetOption filetype=sh %{
    set-option buffer lsp_language_id shellscript
}

hook -group lsp-language-id global BufSetOption filetype=typescript %{
    try %{
        "lsp-nop-with-0%opt{lsp_language_id}"
        set-option buffer lsp_language_id typescript
    }
}

hook -group lsp-language-id global BufCreate .*[.]tsx %{
    set-option buffer lsp_language_id typescriptreact
}

hook -group lsp-language-id global BufSetOption filetype=liquid %{
    set-option buffer lsp_language_id liquid
}
