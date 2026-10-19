function zd -d "cd wrapper: real dirs directly, zoxide for the rest"
    if test (count $argv) -eq 0
        builtin cd ~
    else if test -d "$argv[1]"
        builtin cd "$argv[1]"
    else if functions -q __zoxide_z
        __zoxide_z $argv; and begin
            printf "\U000F17A9 "
            pwd
        end; or echo "Error: Directory not found"
    else
        builtin cd "$argv[1]"
    end
end
