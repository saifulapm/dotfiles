function cml -d "claude memory localize: move global auto-memory into the project"
    set -l proj $argv[1]
    test -n "$proj"; or set proj $PWD
    if not test -d "$proj"
        echo "✗ Not a directory: $proj" >&2
        return 1
    end
    set proj (path resolve $proj)

    # Claude encodes the absolute path: every non-alphanumeric char → '-'
    set -l encoded (string replace -ra '[^a-zA-Z0-9]' '-' $proj)
    set -l src "$HOME/.claude/projects/$encoded/memory"
    set -l dest "$proj/.claude/memory"
    set -l settings "$proj/.claude/settings.local.json"

    if not test -d $src
        echo "✗ No auto-memory at: $src" >&2
        return 1
    end
    if test -e $dest
        echo "✗ Destination already exists: $dest" >&2
        echo "  Merge/remove it manually, then re-run." >&2
        return 1
    end
    command -q jq; or begin
        echo "✗ jq required" >&2
        return 1
    end
    # Validate settings JSON BEFORE moving, so a malformed file can't leave a
    # half-applied state.
    if test -f $settings; and not jq empty $settings 2>/dev/null
        echo "✗ Invalid JSON: $settings" >&2
        return 1
    end

    mkdir -p "$proj/.claude"
    mv $src $dest; or return 1
    echo "✓ Memory moved → $dest"

    set -l tmp (mktemp)
    if test -f $settings
        jq --arg p $dest '. + {autoMemoryDirectory: $p}' $settings >$tmp
    else
        jq -n --arg p $dest '{autoMemoryDirectory: $p}' >$tmp
    end
    mv $tmp $settings
    echo "✓ Settings updated → $settings"
end
