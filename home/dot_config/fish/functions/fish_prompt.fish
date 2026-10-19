function fish_prompt -d "Directory, git branch, a failed status, then ›; colours from the theme's colors.fish"
    set -l last $status
    set_color $fish_color_cwd
    echo -n (prompt_pwd)
    set_color $fish_color_comment
    fish_vcs_prompt ' %s'
    if test $last -ne 0
        set_color $fish_color_status
        echo -n " [$last]"
    end
    set_color normal
    echo -n ' › '
end
