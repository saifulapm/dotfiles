declare-option str-list root_globs .kakrc kakrc .git 
declare-option str root_path %sh{ echo "$PWD" }
declare-option -hidden str root_prev_pwd %opt{root_path}
# recursively discovers the root dir based on root_globs
define-command root-discover %{
    evaluate-commands %sh{
        globs="$kak_opt_root_globs"
        dir="$PWD"
        root="$dir"

        while [ "$dir" != "/" ]; do
        	for glob in $globs; do
        		match=$(fd -H -td -1 --glob "$glob" "$dir" --max-depth 1 2>/dev/null | head -n1)
        		if [ -n "$match" ]; then
        			root="$(dirname "$match")"
        			break
        		fi
        	done
        	dir="$(dirname "$dir")"
        done
        printf 'set-option global root_path "%s"\n' "$root"
        printf 'echo "Discovered root: %s"\n' "$root"
    }
}

# change the cwd to root
define-command -hidden root-cd-root-impl %{
    set-option global root_prev_pwd %sh{ echo "$PWD" }
    change-directory %opt{root_path}
    echo "CWD: %opt{root_path}"
}
# change cwd back to what it was before
define-command -hidden root-cd-return-impl %{
    change-directory %opt{root_prev_pwd}
    echo "CWD: %opt{root_prev_pwd}"
}

# toggle between root and previous cwd
define-command root-cd %{
    evaluate-commands %sh{
        if [ "$PWD" != "$kak_opt_root_path" ]; then
            echo "root-cd-root-impl"
        else
            echo "root-cd-return-impl"
        fi
    }
}

# edit a file, relative to root
define-command -params 1 root-edit %{
    edit %exp{%opt{root_path}/%arg{1}}
}
complete-command root-edit shell-script-candidates %{
    fd -H -tf --exclude '.git' --base-directory "$kak_opt_root_path" .
}
