# try — fresh directories for every vibe (~/Sites/tries). tobi/try, vendored
# at vendor/try (see vendor/README.md); this file is the fish wrapper its
# `try init fish` emits, written out rather than sourced.
#
# Upstream's install is `try init | source` from config.fish, which spawns
# ruby on every shell start to print these eight lines. They do not change,
# so they live here instead and fish startup pays nothing.
#
# The contract: try.rb writes shell commands to stdout and its own UI to
# /dev/tty, so the picker can draw while the caller still captures the `cd`.
# eval only on success — a nonzero exit means stdout is a message, not code.
function try -d "fresh directories for every vibe (~/Sites/tries)"
    set -l dir "$HOME/Sites/tries"
    set -q TRY_PATH; and set dir "$TRY_PATH"

    # Fedora's `ruby` package owns /usr/bin/ruby-mri; the unversioned
    # /usr/bin/ruby belongs to rubypick, a WEAK dependency that this repo's
    # install_weak_deps=False drops. rubypick is declared in the manifest now,
    # but naming the interpreter we actually want keeps `try` working on a
    # machine that only has the versioned one.
    set -l ruby ruby
    command -q ruby; or set ruby ruby-mri
    command -q $ruby; or begin
        echo "try: no ruby interpreter (dnf install ruby rubypick)" >&2
        return 1
    end

    set -l out ($ruby "$HOME/.dotfiles/vendor/try/try.rb" exec --path "$dir" $argv 2>/dev/tty | string collect)
    if test $pipestatus[1] -eq 0
        eval $out
    else
        echo $out
    end
end
