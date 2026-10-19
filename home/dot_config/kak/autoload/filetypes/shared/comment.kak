# Comments

provide-module comment %§
    add-highlighter shared/comment group

    # User mention (@user)
    add-highlighter shared/comment/mention regex @[a-zA-Z0-9_-]+ 0:ts_tag

    # Tag with user - base pattern
    add-highlighter shared/comment/tag regex \b([A-Z]{2,})(\(\s*@?[a-zA-Z0-9_-]+\s*\)):? 1:ts_tag 2:ts_constant

    # Hint level tags
    add-highlighter shared/comment/hint regex \b(HINT|MARK|PASSED|STUB|MOCK)\b 0:ts_hint

    # Info level tags
    add-highlighter shared/comment/info regex \b(INFO|NOTE|TODO|PERF|OPTIMIZE|PERFORMANCE|QUESTION|ASK)\b 0:ts_info

    # Warning level tags
    add-highlighter shared/comment/warning regex \b(HACK|WARN|WARNING|TEST|TEMP)\b 0:ts_warning

    # Error level tags
    add-highlighter shared/comment/error regex \b(BUG|FIXME|ISSUE|XXX|FIX|SAFETY|FIXIT|FAILED|DEBUG|INVARIANT|COMPLIANCE)\b 0:ts_error

    # Issue number (#123)
    add-highlighter shared/comment/issue regex [#]\d+ 0:ts_constant_numeric

    # URI/URL
    add-highlighter shared/comment/uri regex \b\w+://\S+ 0:ts_markup_link_url

§
