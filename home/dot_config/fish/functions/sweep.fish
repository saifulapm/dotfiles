# sweep — reclaim disk by deleting reinstallable dependency dirs under ~/Sites.
# Removes every `node_modules`, and every `vendor` that has a composer.json
# beside it. Restore any project later with `pnpm i` / `composer install`.
#
# The composer.json check is the whole safety story, not a nicety: plenty of
# `vendor` dirs are real source (published Blade views, public assets, Rust/
# Dart vendor dirs) and would be gone for good. Only a vendor sitting next to
# a composer.json is a Composer install.
function sweep -d "delete node_modules + composer vendor dirs under ~/Sites"
    argparse n/dry-run y/yes 'd/days=!_validate_int' h/help -- $argv; or return 1

    if set -q _flag_help
        echo "Usage: sweep [-n|--dry-run] [-y|--yes] [-d|--days N] [PATH]"
        echo "  Deletes node_modules, and vendor dirs beside a composer.json."
        echo "  PATH defaults to \$SITES_PATH or ~/Sites"
        return 0
    end

    set -l days 0
    set -q _flag_days; and set days $_flag_days

    set -l root "$HOME/Sites"
    test -n "$SITES_PATH"; and set root $SITES_PATH
    test -n "$argv[1]"; and set root $argv[1]
    if not test -d "$root"
        echo "✗ Not a directory: $root" >&2
        return 1
    end
    set root (path resolve $root)

    # A typo'd argument must never turn this into `rm -rf ~`.
    if test "$root" = /; or test "$root" = "$HOME"
        echo "✗ Refusing to sweep $root — too broad. Pass a projects dir." >&2
        return 1
    end
    command -q fd; or begin
        echo "✗ fd required (dnf install fd-find)" >&2
        return 1
    end

    # --no-ignore: these dirs are gitignored, fd would otherwise skip them.
    # --prune: don't descend into a match — nested node_modules never listed.
    echo "Scanning $root …"
    set -l found (fd --type d --no-ignore --prune --absolute-path \
        '^(node_modules|vendor)$' $root 2>/dev/null)
    if test (count $found) -eq 0
        echo "✓ Nothing to sweep under $root"
        return 0
    end

    set -l rows
    set -l skipped
    set -l now (date +%s)

    for t in $found
        set t (string trim -r -c / -- $t)

        if test (path basename $t) = vendor; and not test -f (path dirname $t)/composer.json
            set -a skipped $t
            continue
        end

        # -d N filters on the dir's own mtime — untouched since last install.
        if test $days -gt 0
            set -l mt (stat -c %Y $t 2>/dev/null); or continue
            test (math "floor(($now - $mt) / 86400)") -ge $days; or continue
        end

        set -l kb (du -sk -- $t 2>/dev/null | awk '{print $1}')
        string match -qr '^[0-9]+$' -- "$kb"; or set kb 0
        set -a rows "$kb $t"
    end

    if test (count $rows) -eq 0
        echo "✓ Nothing to sweep under $root"
        test (count $skipped) -gt 0
        and echo "  ("(count $skipped)" vendor dir(s) kept — no composer.json beside them)"
        return 0
    end

    set rows (printf '%s\n' $rows | sort -rn)
    set -l total 0
    for line in $rows
        set total (math "$total + "(string split -m1 ' ' -- $line)[1])
    end

    echo ""
    for line in $rows
        set -l parts (string split -m1 ' ' -- $line)
        printf "  %8s  %s\n" (_sweep_size $parts[1]) (string replace "$root/" "" -- $parts[2])
    end
    echo ""
    echo "  "(count $rows)" dir(s), "(_sweep_size $total)" reclaimable under $root"

    if test (count $skipped) -gt 0
        echo ""
        echo "  Kept — source, not a Composer install:"
        for t in $skipped
            echo "    "(string replace "$root/" "" -- $t)
        end
    end

    if set -q _flag_dry_run
        echo ""
        echo "Dry run — nothing deleted."
        return 0
    end

    echo ""
    if not set -q _flag_yes
        if command -q gum
            gum confirm "Delete "(count $rows)" dir(s) and free "(_sweep_size $total)"?"; or begin
                echo "Aborted."
                return 1
            end
        else
            read -l -P "Delete "(count $rows)" dir(s) and free "(_sweep_size $total)"? [y/N] " reply
            string match -qir '^y' -- "$reply"; or begin
                echo "Aborted."
                return 1
            end
        end
    end

    set -l freed 0
    set -l fails 0
    for line in $rows
        set -l parts (string split -m1 ' ' -- $line)
        if rm -rf -- $parts[2]
            set freed (math "$freed + $parts[1]")
        else
            set fails (math "$fails + 1")
            echo "  ✗ failed: $parts[2]" >&2
        end
    end

    echo "✓ Freed "(_sweep_size $freed)" from "(math (count $rows)" - $fails")" dir(s)"
    echo "  Reinstall any project with: pnpm i  /  composer install"
    test $fails -gt 0; and return 1
    return 0
end
