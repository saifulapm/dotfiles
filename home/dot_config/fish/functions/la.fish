function la -d "lsd -la for dirs, bat for files"
    if test (count $argv) -eq 0
        lsd -la
    else if test -d "$argv[1]"
        lsd -la "$argv[1]"
    else if test -f "$argv[1]"
        bat "$argv[1]"
    else
        echo "Error: '$argv[1]' not found"
    end
end
