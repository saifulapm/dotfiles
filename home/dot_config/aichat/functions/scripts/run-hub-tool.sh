#!/usr/bin/env bash

# Usage: ./run-hub-tool.sh <tool-name> <tool-data>

set -e

main() {
    root_dir="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd)"
    self_name=run-hub-tool.sh
    parse_argv "$@"
    load_env "$root_dir/.env" 
    run
}

parse_argv() {
    if [[ "$0" == *"$self_name" ]]; then
        tool_name="$1"
        tool_data="$2"
    else
        tool_name="$(basename "$0")"
        tool_data="$1"
    fi
    if [[ "$tool_name" == *.sh ]]; then
        tool_name="${tool_name:0:$((${#tool_name}-3))}"
    fi
    if [[ -z "$tool_data" ]] || [[ -z "$tool_name" ]]; then
        die "usage: ./run-tool.sh <tool-name> <tool-data>"
    fi
}

die() {
    echo "error: $*" >&2
    exit 1
}

load_env() {
    local env_file="$1" env_vars
    if [[ -f "$env_file" ]]; then
        while IFS='=' read -r key value; do
            if [[ "$key" == $'#'* ]] || [[ -z "$key" ]]; then
                continue
            fi
            if [[ -z "${!key+x}" ]]; then
                env_vars="$env_vars $key=$value"
            fi
        done < <(cat "$env_file"; echo "")
        if [[ -n "$env_vars" ]]; then
            eval "export $env_vars"
        fi
    fi
}

run() {
    if [[ -z "$tool_data" ]]; then
        die "error: no JSON data"
    fi

    # Parse server_name and tool from tool_name using dot separator
    if [[ "$tool_name" == *.* ]]; then
        server_name="${tool_name%%.*}"
        tool="${tool_name#*.}"
    else
        die "error: tool_name must be in format 'server_name.tool_name'"
    fi

    if [[ "$OS" == "Windows_NT" ]]; then
        set -o igncr
        tool_data="$(echo "$tool_data" | sed 's/\\/\\\\/g')"
    fi

    if [[ -z "$LLM_OUTPUT" ]]; then
        is_temp_llm_output=1
        export LLM_OUTPUT="$(mktemp)"
    fi

    if [[ -n "$LLM_MCP_SKIP_CONFIRM" ]]; then
        if grep -q -w -E "$LLM_MCP_SKIP_CONFIRM" <<<"$tool_name"; then
            skip_confirm=1
        fi
    fi
    if [[ -n "$LLM_MCP_NEED_CONFIRM" ]]; then
        if grep -q -w -E "$LLM_MCP_NEED_CONFIRM" <<<"$tool_name"; then
            skip_confirm=0
        fi
    fi
    if [[ -t 1 ]] && [[ "$skip_confirm" -ne 1 ]]; then
        read -r -p "Are you sure you want to continue? [Y/n] " ans
        if [[ "$ans" == "N" || "$ans" == "n" ]]; then
            echo "error: canceled!" >&2
            exit 1
        fi
    fi

    # Validate that tool_data is valid JSON
    if ! echo "$tool_data" | jq empty > /dev/null 2>&1; then
        die "error: invalid JSON in tool_data (arguments)"
    fi

    # Create the complete API payload structure
    # tool_data contains the arguments, we need to wrap it in the proper API structure
    api_payload=$(jq -n \
        --arg server_name "$server_name" \
        --arg tool "$tool" \
        --argjson arguments "$tool_data" \
        '{
            server_name: $server_name,
            tool: $tool,
            arguments: $arguments,
            request_options: {}
        }')
    
    # Debug output (uncomment for debugging)
    # echo "DEBUG: API Payload:" >&2
    # echo "$api_payload" | jq . >&2
    
    curl -sS "http://localhost:${MCP_BRIDGE_PORT:-3123}/api/servers/tools" \
        -X POST \
        -H 'content-type: application/json' \
        -d "$api_payload" > "$LLM_OUTPUT"

    if [[ "$is_temp_llm_output" -eq 1 ]]; then
        cat "$LLM_OUTPUT"
    else
        dump_result "$tool_name" 
    fi
}

dump_result() {
    if [[ "$LLM_OUTPUT" == "/dev/stdout" ]] || [[ -z "$LLM_DUMP_RESULTS" ]] ||  [[ ! -t 1 ]]; then
        return;
    fi
    if grep -q -w -E "$LLM_DUMP_RESULTS" <<<"$1"; then
            cat <<EOF
$(echo -e "\e[2m")----------------------
$(cat "$LLM_OUTPUT")
----------------------$(echo -e "\e[0m")
EOF
    fi
}

main "$@"
