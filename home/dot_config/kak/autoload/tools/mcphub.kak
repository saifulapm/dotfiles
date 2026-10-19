# MCPHub Kakoune Plugin
declare-option -hidden int mcphub_port 3123

define-command -params 1.. -docstring %{
mcphub <config1> [config2] ... [options]: start MCP Hub server

Arguments:
  config1, config2...   Config names from ~/.config/mcphub/configs/ (without .json)
                        At least one config is required

Options (passed to mcp-hub):
  -p, --port <port>     Port to run the server on (default: 3123)
  -w, --watch           Watch for config file changes
      --auto-shutdown   Automatically shutdown when no clients are connected
      --shutdown-delay <ms> Delay in milliseconds before shutting down
  -h, --help            Show help

Examples:
  mcphub shopify laravel              # Uses shopify.json + laravel.json, port 3123
  mcphub shopify --port 8080          # Uses shopify.json, port 8080
  mcphub global project --watch       # Multiple configs with watch mode
} mcphub %{
    evaluate-commands %sh{
        config_dir="$HOME/.config/mcphub/configs"
        configs=""
        cmd_args=""
        port="3123"

        # Parse arguments
        while [ $# -gt 0 ]; do
            case "$1" in
                -p|--port)
                    port="$2"
                    shift 2
                    ;;
                --shutdown-delay)
                    cmd_args="$cmd_args --shutdown-delay $2"
                    shift 2
                    ;;
                -w|--watch|--auto-shutdown)
                    cmd_args="$cmd_args $1"
                    shift
                    ;;
                -h|--help)
                    cmd_args="$cmd_args $1"
                    shift
                    ;;
                *)
                    # Try to match config file
                    if [ -f "$config_dir/$1.json" ]; then
                        configs="$configs --config $config_dir/$1.json"
                    else
                        cmd_args="$cmd_args $1"
                    fi
                    shift
                    ;;
            esac
        done

        # Build the full command - always include port
        full_cmd="mcp-hub$configs --port $port$cmd_args"

        printf %s\\n "set-option global mcphub_port $port"
        printf %s\\n "fifo -name '*mcphub*' -scroll -script %{
            $full_cmd
        }"
    }
}

define-command -params 1.. -docstring %{
mcphub-api <endpoint> [args] [options]: interact with MCPHub REST API

Endpoints:
  health                            Get health status
  servers                           List MCP servers
  workspaces                        List active workspaces
  refresh                           Refresh all servers
  server-info <server_name>         Get specific server info
  server-refresh <server_name>      Refresh specific server capabilities
  server-start <server_name>        Start a server
  server-stop <server_name> [--disable] Stop a server (optionally disable)

Options:
  -p, --port <port>                 MCPHub server port (uses mcphub port if not specified)
  -h, --host <host>                 MCPHub server host (default: localhost)
  --disable                         For server-stop: disable server in config

Examples:
  mcphub-api health                 # Get health status
  mcphub-api servers                # List all servers
  mcphub-api workspaces             # List active workspaces
  mcphub-api server-info github     # Get github server info
  mcphub-api server-stop github --disable  # Stop and disable github server
} mcphub-api %{
    evaluate-commands %sh{
        host="localhost"
        port="$kak_opt_mcphub_port"
        endpoint=""
        server_name=""
        disable=""

        # Parse arguments
        while [ $# -gt 0 ]; do
            case "$1" in
                -p|--port) port="$2"; shift 2 ;;
                -h|--host) host="$2"; shift 2 ;;
                --disable) disable="?disable=true"; shift ;;
                *)
                    if [ -z "$endpoint" ]; then
                        endpoint="$1"
                    else
                        server_name="$1"
                    fi
                    shift
                    ;;
            esac
        done

        url="http://$host:$port/api"

        case "$endpoint" in
            health|servers|workspaces)
                # Simple GET endpoints
                printf %s\\n "fifo -name '*mcphub-api*' -scroll -script %{
                    curl -s '$url/$endpoint' | jq
                }"
                ;;
            refresh)
                # POST refresh all servers
                printf %s\\n "fifo -name '*mcphub-api*' -scroll -script %{
                    curl -s -X POST '$url/refresh' | jq
                }"
                ;;
            server-info|server-refresh|server-start)
                # Server-specific POST endpoints
                if [ -z "$server_name" ]; then
                    echo "echo -markup '{Error}$endpoint requires server name'"
                    exit
                fi
                # Extract operation name (remove 'server-' prefix)
                operation="${endpoint#server-}"
                printf %s\\n "fifo -name '*mcphub-api*' -scroll -script %{
                    curl -s -X POST '$url/servers/$operation' \\
                        -H 'Content-Type: application/json' \\
                        -d '{\"server_name\": \"$server_name\"}' | jq
                }"
                ;;
            server-stop)
                # Server stop with optional disable
                if [ -z "$server_name" ]; then
                    echo "echo -markup '{Error}server-stop requires server name'"
                    exit
                fi
                printf %s\\n "fifo -name '*mcphub-api*' -scroll -script %{
                    curl -s -X POST '$url/servers/stop$disable' \\
                        -H 'Content-Type: application/json' \\
                        -d '{\"server_name\": \"$server_name\"}' | jq
                }"
                ;;
            *)
                echo "echo -markup '{Error}Unknown endpoint: $endpoint'"
                ;;
        esac
    }
}

define-command -params 1.. -docstring %{
mcphub-restart <config1> [config2] ... [options]: restart MCP Hub with new configs

This command stops the current MCP Hub server and starts a new one with the specified configs.
Useful for adding/removing servers without manually stopping first.

Examples:
  mcphub-restart laravel shopify    # Restart with laravel + shopify
  mcphub-restart global --watch     # Restart with watch mode
} mcphub-restart %{
    mcphub-stop
    mcphub %arg{@}
}

define-command mcphub-stop -docstring "Stop the running MCP Hub server" %{
    evaluate-commands %sh{
        port="$kak_opt_mcphub_port"
        pids=$(lsof -ti:$port 2>/dev/null)
        if [ -n "$pids" ]; then
            kill $pids
            echo "echo -markup '{Information}MCP Hub server on port $port stopped'"
        else
            echo "echo -markup '{Error}No MCP Hub server found on port $port'"
        fi
    }
}

complete-command mcphub shell-script-candidates %{
    config_dir="$HOME/.config/mcphub/configs"

    case $kak_token_to_complete in
        0|1|2|3|4|5|6|7|8|9)
            # Offer config files and common options
            if [ -d "$config_dir" ]; then
                ls "$config_dir"/*.json 2>/dev/null | xargs -n1 basename -s .json
            fi
            printf -- "--port\n--watch\n--auto-shutdown\n--shutdown-delay\n"
            ;;
    esac
}

complete-command mcphub-restart shell-script-candidates %{
    config_dir="$HOME/.config/mcphub/configs"

    case $kak_token_to_complete in
        0|1|2|3|4|5|6|7|8|9)
            # Offer config files and common options
            if [ -d "$config_dir" ]; then
                ls "$config_dir"/*.json 2>/dev/null | xargs -n1 basename -s .json
            fi
            printf -- "--port\n--watch\n--auto-shutdown\n--shutdown-delay\n"
            ;;
    esac
}

complete-command mcphub-api shell-script-candidates %{
    case $kak_token_to_complete in
        0)
            # Complete endpoint names
            printf "health\nservers\nworkspaces\nrefresh\nserver-info\nserver-refresh\nserver-start\nserver-stop\n"
            ;;
        1)
            # Complete server names for server-* endpoints
            case "$1" in
                server-*)
                    # Try to get server list from running mcphub instance
                    curl -s "http://localhost:$kak_opt_mcphub_port/api/servers" 2>/dev/null |
                        jq -r '.servers[]?.name // empty' 2>/dev/null
                    ;;
            esac
            ;;
        2)
            # Complete options for specific endpoints
            case "$1" in
                server-stop)
                    printf -- "--disable\n"
                    ;;
            esac
            ;;
    esac
}
