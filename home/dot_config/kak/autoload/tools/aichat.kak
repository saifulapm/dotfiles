# Session-specific aichat configuration options
declare-option -docstring "Selected aichat model" str aichat_model ""
declare-option -docstring "Selected aichat role" str aichat_role ""
declare-option -docstring "Selected aichat session" str aichat_session ""
declare-option -docstring "Selected aichat agent" str aichat_agent ""
declare-option -docstring "Selected aichat RAG" str aichat_rag ""
declare-option -docstring "Additional aichat flags" str aichat_flags ""

define-command aichat -docstring %{
    aichat [OPTIONS] [TEXT]...: All-in-one LLM CLI Tool

    Uses session-configured options (aichat_model, aichat_role, etc.) if set.
    Use aichat-model, aichat-role, etc. commands to configure.

    Options:
      --model <MODEL>         Select a LLM model
      --prompt <PROMPT>       Use the system prompt
      --role <ROLE>           Select a role
      --session [<SESSION>]   Start or join a session
      --empty-session         Ensure the session is empty
      --save-session          Save the conversation to the session
      --agent <AGENT>         Start an agent
      --agent-variable        Set agent variables
      --rag <RAG>             Start a RAG
      --rebuild-rag           Rebuild the RAG to sync changes
      --macro <MACRO>         Execute a macro
      --serve [<ADDRESS>]     Serve the LLM API and WebAPP
      --execute               Execute commands in natural language
      --code                  Output code only
      --file <FILE>           Include files, directories, or URLs
      --no-stream             Turn off stream mode
      --dry-run               Display the message without sending
      --info                  Display information
      --sync-models           Sync models updates
      --list-models           List all available chat models
      --list-roles            List all roles
      --list-sessions         List all sessions
      --list-agents           List all agents
      --list-rags             List all RAGs
      --list-macros           List all macros
      --help                  Print help
      --version               Print version
} -params 0.. %{
    evaluate-commands %sh{
        # Build command with configured options
        cmd="aichat"

        # Add configured options
        [ -n "$kak_opt_aichat_model" ] && cmd="$cmd --model $kak_opt_aichat_model"
        [ -n "$kak_opt_aichat_role" ] && cmd="$cmd --role $kak_opt_aichat_role"
        [ -n "$kak_opt_aichat_session" ] && cmd="$cmd --session $kak_opt_aichat_session"
        [ -n "$kak_opt_aichat_agent" ] && cmd="$cmd --agent $kak_opt_aichat_agent"
        [ -n "$kak_opt_aichat_rag" ] && cmd="$cmd --rag $kak_opt_aichat_rag"
        [ -n "$kak_opt_aichat_flags" ] && cmd="$cmd $kak_opt_aichat_flags"

        printf "fifo -name '*aichat*' -scroll -- %s %%arg{@}\n" "$cmd"
    }
}

define-command aichat-model -params ..1 -docstring "aichat-model [model]: Set or show the aichat model" %{
    evaluate-commands %sh{
        if [ $# -eq 0 ]; then
            if [ -n "$kak_opt_aichat_model" ]; then
                printf "echo -markup '{Information}Current model: %s'\n" "$kak_opt_aichat_model"
            else
                printf "echo -markup '{Information}No model set'\n"
            fi
        else
            printf "set-option global aichat_model '%s'\n" "$1"
            printf "echo -markup '{Information}Model set to: %s'\n" "$1"
        fi
    }
}

define-command aichat-role -params ..1 -docstring "aichat-role [role]: Set or show the aichat role" %{
    evaluate-commands %sh{
        if [ $# -eq 0 ]; then
            if [ -n "$kak_opt_aichat_role" ]; then
                printf "echo -markup '{Information}Current role: %s'\n" "$kak_opt_aichat_role"
            else
                printf "echo -markup '{Information}No role set'\n"
            fi
        else
            printf "set-option global aichat_role '%s'\n" "$1"
            printf "echo -markup '{Information}Role set to: %s'\n" "$1"
        fi
    }
}

define-command aichat-session -params ..1 -docstring "aichat-session [session]: Set or show the aichat session" %{
    evaluate-commands %sh{
        if [ $# -eq 0 ]; then
            if [ -n "$kak_opt_aichat_session" ]; then
                printf "echo -markup '{Information}Current session: %s'\n" "$kak_opt_aichat_session"
            else
                printf "echo -markup '{Information}No session set'\n"
            fi
        else
            printf "set-option global aichat_session '%s'\n" "$1"
            printf "echo -markup '{Information}Session set to: %s'\n" "$1"
        fi
    }
}

define-command aichat-agent -params ..1 -docstring "aichat-agent [agent]: Set or show the aichat agent" %{
    evaluate-commands %sh{
        if [ $# -eq 0 ]; then
            if [ -n "$kak_opt_aichat_agent" ]; then
                printf "echo -markup '{Information}Current agent: %s'\n" "$kak_opt_aichat_agent"
            else
                printf "echo -markup '{Information}No agent set'\n"
            fi
        else
            printf "set-option global aichat_agent '%s'\n" "$1"
            printf "echo -markup '{Information}Agent set to: %s'\n" "$1"
        fi
    }
}

define-command aichat-rag -params ..1 -docstring "aichat-rag [rag]: Set or show the aichat RAG" %{
    evaluate-commands %sh{
        if [ $# -eq 0 ]; then
            if [ -n "$kak_opt_aichat_rag" ]; then
                printf "echo -markup '{Information}Current RAG: %s'\n" "$kak_opt_aichat_rag"
            else
                printf "echo -markup '{Information}No RAG set'\n"
            fi
        else
            printf "set-option global aichat_rag '%s'\n" "$1"
            printf "echo -markup '{Information}RAG set to: %s'\n" "$1"
        fi
    }
}

define-command aichat-flags -params ..1 -docstring "aichat-flags [flags]: Set or show additional aichat flags" %{
    evaluate-commands %sh{
        if [ $# -eq 0 ]; then
            if [ -n "$kak_opt_aichat_flags" ]; then
                printf "echo -markup '{Information}Current flags: %s'\n" "$kak_opt_aichat_flags"
            else
                printf "echo -markup '{Information}No flags set'\n"
            fi
        else
            printf "set-option global aichat_flags '%s'\n" "$*"
            printf "echo -markup '{Information}Flags set to: %s'\n" "$*"
        fi
    }
}

define-command aichat-reset -docstring "Reset all aichat options" %{
    set-option global aichat_model ""
    set-option global aichat_role ""
    set-option global aichat_session ""
    set-option global aichat_agent ""
    set-option global aichat_rag ""
    set-option global aichat_flags ""
    echo -markup "{Information}All aichat options reset"
}

define-command aichat-show -docstring "Show all configured aichat options" %{
    info -title "AIChat Configuration" %sh{
        printf "Model:   %s\n" "${kak_opt_aichat_model:-<not set>}"
        printf "Role:    %s\n" "${kak_opt_aichat_role:-<not set>}"
        printf "Session: %s\n" "${kak_opt_aichat_session:-<not set>}"
        printf "Agent:   %s\n" "${kak_opt_aichat_agent:-<not set>}"
        printf "RAG:     %s\n" "${kak_opt_aichat_rag:-<not set>}"
        printf "Flags:   %s\n" "${kak_opt_aichat_flags:-<not set>}"
    }
}

# Add completions for the new commands
complete-command aichat-model shell-script-candidates %{ aichat --list-models 2>/dev/null }
complete-command aichat-role shell-script-candidates %{ aichat --list-roles 2>/dev/null }
complete-command aichat-session shell-script-candidates %{ aichat --list-sessions 2>/dev/null }
complete-command aichat-agent shell-script-candidates %{ aichat --list-agents 2>/dev/null }
complete-command aichat-rag shell-script-candidates %{ aichat --list-rags 2>/dev/null }

define-command aichat-messages -docstring %{
    aichat-messages [session]: Show messages with syntax highlighting

    If session is provided, shows session YAML file
    Otherwise shows all messages from ~/.config/aichat/messages.md

    Examples:
      aichat-messages          # Show all messages from messages.md
      aichat-messages test     # Show session YAML for 'test' session
} -params 0..1 %{
    evaluate-commands %sh{
        session="$1"

        if [ -n "$session" ]; then
            # Show session YAML file
            session_file="${HOME}/.config/aichat/sessions/${session}.yaml"

            if [ ! -f "$session_file" ]; then
                printf "fail 'Session file not found: %s'\n" "$session_file"
                exit
            fi

            buffer_name="*aichat-${session}*"
            printf "fifo -name '%s' -- bat --color=always --style=plain '%s'\n" "$buffer_name" "$session_file"
        else
            # Show messages.md file
            messages_file="${HOME}/.config/aichat/messages.md"

            if [ ! -f "$messages_file" ]; then
                printf "fail 'Messages file not found: %s'\n" "$messages_file"
                exit
            fi

            printf "fifo -name '*aichat-messages*' -- bat --color=always --style=plain '%s'\n" "$messages_file"
        fi
    }
}

complete-command aichat-messages shell-script-candidates %{
    # Suggest available sessions
    if [ -d "${HOME}/.config/aichat/sessions" ]; then
        ls -1 "${HOME}/.config/aichat/sessions" 2>/dev/null | sed 's/\.yaml$//'
    fi
}

# Shared completion logic for aichat commands
declare-option -hidden str aichat_completion_script %{
    # Get the previous argument if it exists
    if [ "$kak_token_to_complete" -gt 0 ]; then
        prev_index=$((kak_token_to_complete))
        eval "prev_arg=\${$prev_index}"
    else
        prev_arg=""
    fi

    # Provide completions based on the previous argument
    case "$prev_arg" in
        --model)
            # Complete with model names from aichat
            aichat --list-models 2>/dev/null
            ;;
        --role)
            # Complete with role names
            aichat --list-roles 2>/dev/null
            ;;
        --session)
            # Complete with session names
            aichat --list-sessions 2>/dev/null
            ;;
        --agent)
            # Complete with agent names
            aichat --list-agents 2>/dev/null
            ;;
        --rag)
            # Complete with RAG names
            aichat --list-rags 2>/dev/null
            ;;
        --macro)
            # Complete with macro names
            aichat --list-macros 2>/dev/null
            ;;
        *)
            # Default: show all available options/flags
            printf "%s\n" \
                "--model" \
                "--prompt" \
                "--role" \
                "--session" \
                "--empty-session" \
                "--save-session" \
                "--agent" \
                "--agent-variable" \
                "--rag" \
                "--rebuild-rag" \
                "--macro" \
                "--serve" \
                "--execute" \
                "--code" \
                "--file" \
                "--no-stream" \
                "--dry-run" \
                "--info" \
                "--sync-models" \
                "--list-models" \
                "--list-roles" \
                "--list-sessions" \
                "--list-agents" \
                "--list-rags" \
                "--list-macros" \
                "--help" \
                "--version"
            ;;
    esac
}

complete-command aichat shell-script-candidates %opt{aichat_completion_script}

define-command chat-buffer -docstring ' opens a *chat-buffer* buffer for writing prompts to pass to ai agents ' %{
  edit -scratch *chat-buffer* ; set-option buffer filetype chat-buffer
}

define-command aichat-send -docstring 'Send selection to aichat (uses configured options)' -params 0.. %{
  buffer *chat-buffer*
  execute-keys '%'
  evaluate-commands %sh{
    # Build command with configured options
    cmd="aichat"

    # Add configured options
    [ -n "$kak_opt_aichat_model" ] && cmd="$cmd --model $kak_opt_aichat_model"
    [ -n "$kak_opt_aichat_role" ] && cmd="$cmd --role $kak_opt_aichat_role"
    [ -n "$kak_opt_aichat_session" ] && cmd="$cmd --session $kak_opt_aichat_session"
    [ -n "$kak_opt_aichat_agent" ] && cmd="$cmd --agent $kak_opt_aichat_agent"
    [ -n "$kak_opt_aichat_rag" ] && cmd="$cmd --rag $kak_opt_aichat_rag"
    [ -n "$kak_opt_aichat_flags" ] && cmd="$cmd $kak_opt_aichat_flags"

    printf "fifo -name '*aichat*' -scroll -- %s %%arg{@} %%val{selection}\n" "$cmd"
  }
}

complete-command aichat-send shell-script-candidates %opt{aichat_completion_script}

hook global BufSetOption filetype=chat-buffer %{
  alias buffer write aichat-send
  alias buffer w aichat-send
}
