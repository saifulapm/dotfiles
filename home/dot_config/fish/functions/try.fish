# tobi/try, vendored at vendor/try; try.rb prints shell code on stdout and draws its picker on /dev/tty, so the cd it prints runs here.
function try -d "fresh directories for trying things (~/Tries)"
    set -l dir ~/Tries
    set -q TRY_PATH; and set dir $TRY_PATH
    # Fedora's unversioned ruby comes from rubypick; ruby-mri is the interpreter itself.
    set -l ruby ruby
    command -q ruby; or set ruby ruby-mri
    # This file is chezmoi's link into the repo's home/dot_config/fish/functions, so the repo is five folders up from the file it points to.
    set -l repo (path resolve (functions -D try) | path dirname | path dirname | path dirname | path dirname | path dirname)
    set -l out (command $ruby $repo/vendor/try/try.rb exec --path $dir $argv 2>/dev/tty | string collect)
    if test $pipestatus[1] -eq 0
        eval $out
    else
        echo $out
    end
end
