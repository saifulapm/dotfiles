function _sweep_size -a kb -d "KB → human size (shared by sweep's table + summary)"
    test -n "$kb"; or set kb 0
    if test $kb -ge 1048576
        printf '%.1fG' (math "$kb / 1048576")
    else if test $kb -ge 1024
        printf '%.0fM' (math "$kb / 1024")
    else
        printf '%dK' $kb
    end
end
