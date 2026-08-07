# tui-remove [name…] — installed TUI launchers via the X-Qshell-TUI marker
# (user pick 2026-08-08)
function __qshell_tui_names
    set -l files (grep -l '^X-Qshell-TUI=true$' ~/.local/share/applications/*.desktop 2>/dev/null)
    test (count $files) -gt 0; or return
    sed -n 's/^Name=//p' $files
end
complete -c tui-remove -f -a '(__qshell_tui_names)'
