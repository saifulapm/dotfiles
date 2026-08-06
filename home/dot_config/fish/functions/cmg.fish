function cmg -d "claude memory globalize: rollback of cml"
    set -l proj $argv[1]
    test -n "$proj"; or set proj $PWD
    if not test -d "$proj"
        echo "✗ Not a directory: $proj" >&2
        return 1
    end
    set proj (path resolve $proj)

    set -l encoded (string replace -ra '[^a-zA-Z0-9]' '-' $proj)
    set -l src "$proj/.claude/memory"
    set -l dest "$HOME/.claude/projects/$encoded/memory"
    set -l settings "$proj/.claude/settings.local.json"

    if not test -d $src
        echo "✗ No local memory at: $src" >&2
        return 1
    end
    if test -e $dest
        echo "✗ Global location already exists: $dest" >&2
        echo "  Merge/remove it manually, then re-run." >&2
        return 1
    end
    command -q jq; or begin
        echo "✗ jq required" >&2
        return 1
    end
    if test -f $settings; and not jq empty $settings 2>/dev/null
        echo "✗ Invalid JSON: $settings" >&2
        return 1
    end

    mkdir -p "$HOME/.claude/projects/$encoded"
    mv $src $dest; or return 1
    echo "✓ Memory moved → $dest"

    if test -f $settings
        set -l tmp (mktemp)
        jq 'del(.autoMemoryDirectory)' $settings >$tmp
        if test (jq -c . $tmp) = '{}'
            rm $tmp $settings
            echo "✓ Removed empty $settings"
        else
            mv $tmp $settings
            echo "✓ Settings updated → $settings"
        end
    end
end
