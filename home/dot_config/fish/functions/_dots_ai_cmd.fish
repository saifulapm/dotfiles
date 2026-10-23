function _dots_ai_cmd -d "Alt+E: replace the typed task with a shell command from pxy's chat model"
    set -l query (commandline -b)
    test -n "$query"; or return
    set -l url http://127.0.0.1:4100
    set -q DOTS_AI_URL; and set url $DOTS_AI_URL
    set -l os (string match -rg '^PRETTY_NAME="?([^"]*)' </etc/os-release)
    # aichat's %shell% role, as aichat -e sends it.
    set -l sys "Provide only fish commands for $os (linux) without any description.
Ensure the output is a valid fish command.
If there is a lack of details, provide most logical solution.
If multiple steps are required, try to combine them using '&&' (For PowerShell, use ';' instead).
Output only plain text without any markdown formatting."
    set -l body (jq -n --arg s "$sys" --arg q "$query" \
        '{model:"chat", stream:false, temperature:0, messages:[{role:"system",content:$s},{role:"user",content:$q}]}')
    # The body goes to a file so the substitution captures only curl's own error message.
    set -l out (mktemp)
    set -l err (curl -sS --fail-with-body --max-time 20 -o $out $url/v1/chat/completions \
        -H "Authorization: Bearer pxy-local" -H "Content-Type: application/json" -d "$body" 2>&1)
    set -l rc $status
    # Keys typed during the wait sit in the terminal's input queue and would act on the answer, a queued Enter running it unseen, so they are dropped.
    python3 -c 'import sys, termios; termios.tcflush(sys.stdin, termios.TCIFLUSH)' 2>/dev/null
    set -l reply (cat $out)
    rm -f $out

    # The answer and pxy's error come from a model or a remote, so whole escape sequences go first, a tab becomes a space, then every other control character and bidi mark goes.
    set -l escape '\e\[[0-?]*[ -/]*[@-~]|\e\][^\a\e]*(\a|\e\\\\)?'
    set -l strip '[\x00-\x1f\x7f-\x9f\x{200e}\x{200f}\x{061c}\x{202a}-\x{202e}\x{2066}-\x{2069}]'
    set -l cmd
    if test $rc -eq 0
        for line in (printf '%s\n' $reply | jq -r '.choices[0].message.content // empty' 2>/dev/null)
            set line (string replace -ra -- $escape '' $line | string replace -a \t ' ' | string replace -ra -- $strip '' | string trim)
            if test -n "$line"; and not string match -q -- '```*' $line
                set cmd $line
                break
            end
        end
    end
    if test -n "$cmd"
        commandline -r -- $cmd
        commandline -f end-of-line repaint
        return
    end

    set -l reason (printf '%s\n' $reply | jq -r '.error.message // empty' 2>/dev/null)
    test -n "$reason"; or set reason $err
    test -n "$reason"; or set reason "pxy gave no command"
    set reason (string join ' ' -- $reason | string replace -ra -- $escape '' | string replace -a \t ' ' | string replace -ra -- $strip '' | string trim | string sub -l 200)
    commandline -r -- $query
    printf '\nAlt+E: %s\n' $reason
    commandline -f repaint
end
