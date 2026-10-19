define-command -params ..1 -docstring %{
	copy git url with line numbers.
	Switches:
		-permalink  Generate a permalink (uses commit hash instead of branch).
} get-git-url %{
	evaluate-commands %sh{
		PERMALINK=false
		while [ $# -gt 0 ]; do
			case "$1" in
				-permalink) PERMALINK=true; shift ;;
				--) shift; break ;;
				-*) echo "fail Unknown switch $1"; exit 1 ;;
				*) break ;;
			esac
		done

		# Check if inside git repo
		if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			echo "fail Not inside a git repository."
			exit 1
		fi

		# Get remote
		REMOTE="$(git config --get remote.origin.url)"
		[ -z "$REMOTE" ] && echo "fail No remote origin." && exit 1

		# Extract path from remote URL
		path="$(echo "$REMOTE" | sed -E 's#(git@|ssh://git@|https://)[^:/]+(:[0-9]+)?[:/]##; s#\.git$##; s#^/##')"

		# Get ref (commit hash or branch)
		if [ "$PERMALINK" = true ]; then
			ref="$(git rev-parse HEAD)"
		else
			ref="$(git rev-parse --abbrev-ref HEAD)"
		fi

		# Get relative filename (portable version)
		toplevel="$(git rev-parse --show-toplevel)"
		filename="${kak_buffile#$toplevel/}"

		# Parse selection for line numbers
		start=${kak_selection_desc%%.*}
		tmp=${kak_selection_desc#*,}
		end=${tmp%%.*}

		# Build URL based on provider
		case "$REMOTE" in
			*github.com*)
				[ "$kak_selection_length" -gt 1 ] && lines="#L$start-L$end" || lines="#L$start"
				url="https://github.com/$path/blob/$ref/$filename$lines"
				;;
			*gitlab.com*)
				[ "$kak_selection_length" -gt 1 ] && lines="#L$start-$end" || lines="#L$start"
				url="https://gitlab.com/$path/-/blob/$ref/$filename$lines"
				;;
			*git.sr.ht*)
				[ "$kak_selection_length" -gt 1 ] && lines="#L$start-$end" || lines="#L$start"
				url="https://git.sr.ht/$path/tree/$ref/item/$filename$lines"
				;;
			*codeberg.org*)
				[ "$kak_selection_length" -gt 1 ] && lines="#L$start-L$end" || lines="#L$start"
				url="https://codeberg.org/$path/src/branch/$ref/$filename$lines"
				;;
			*gitea* | *forgejo*)
				[ "$kak_selection_length" -gt 1 ] && lines="#L$start-L$end" || lines="#L$start"
				# Extract host from remote
				host="$(echo "$REMOTE" | sed -E 's#(git@|ssh://git@|https://)##; s#[:/].*##')"
				url="https://$host/$path/src/branch/$ref/$filename$lines"
				;;
			*)
				echo "fail Unsupported git provider: $REMOTE"
				exit 1
				;;
		esac

		# URL encode and output
		encoded="$(printf '%s' "$url" | python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read(), safe=":/?#&="))')"
		echo "info %{$encoded}"
		{ printf '%s' "$encoded" | pbcopy 2>/dev/null || printf '%s' "$encoded" | wl-copy 2>/dev/null; } &
	}
}

complete-command -menu get-git-url shell-script-candidates %{
	echo "-permalink"
}
