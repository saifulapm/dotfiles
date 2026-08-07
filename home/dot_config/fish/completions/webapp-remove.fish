# webapp-remove [name…] — installed web apps only, recognized the same way
# the script itself does: the X-Qshell-WebApp marker (user pick 2026-08-08)
function __qshell_webapp_names
    set -l files (grep -l '^X-Qshell-WebApp=true$' ~/.local/share/applications/*.desktop 2>/dev/null)
    test (count $files) -gt 0; or return
    sed -n 's/^Name=//p' $files
end
complete -c webapp-remove -f -a '(__qshell_webapp_names)'
