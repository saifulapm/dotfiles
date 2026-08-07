# Completions for the `a` alias (php artisan) — native fish, no framework
# (user pick 2026-08-08). Dynamic: artisan's command set is per-project
# (packages and app/Console add commands), so there is nothing static to ship.
# `php artisan list --raw` boots the framework (~300ms), so results are cached
# per directory in XDG_RUNTIME_DIR, invalidated by artisan/composer.lock mtime
# or 5 minutes, whichever first (custom app commands appear without composer
# activity, hence the TTL).

function __a_artisan_commands
    test -f artisan; or return
    set -l dir /tmp
    test -n "$XDG_RUNTIME_DIR"; and set dir "$XDG_RUNTIME_DIR"
    set -l cache "$dir/fish-artisan-"(string replace -a / _ -- $PWD | string sub -s -80)

    if test -f "$cache"
        set -l fresh 1
        test "$cache" -nt artisan; or set fresh 0
        test -f composer.lock; and not test "$cache" -nt composer.lock; and set fresh 0
        test -n "$(find "$cache" -mmin +5 2>/dev/null)"; and set fresh 0
        if test $fresh = 1
            cat "$cache"
            return
        end
    end

    php artisan list --raw 2>/dev/null | string replace -r '\s\s+' \t | tee "$cache"
end

complete -c a -n '__fish_use_subcommand' -x -a '(__a_artisan_commands)'
