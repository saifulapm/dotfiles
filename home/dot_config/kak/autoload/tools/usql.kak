# Simple usql integration for Kakoune
# Place this in your kakrc or a separate plugin file
# Define option for database connection string
declare-option -hidden -docstring "Database connection string for usql" str usql_connection

# Single usql command
define-command usql -params 0..1 -shell-script-candidates %{ printf "env\nd1\nkv\n" } -docstring "Open usql database client (env|d1|kv)" %{
    evaluate-commands %sh{
        if [ $# -eq 1 ]; then
            case "$1" in
                "env")
                    echo "usql-from-env"
                    echo "usql"
                    ;;
                "d1")
                    echo "usql-from-wrangler d1"
                    echo "usql"
                    ;;
                "kv")
                    echo "usql-from-wrangler kv"
                    echo "usql"
                    ;;
                *)
                    # Treat as direct connection string
                    echo "terminal usql '$1'"
                    ;;
            esac
        elif [ -n "$kak_opt_usql_connection" ]; then
            # Use configured connection string
            echo "terminal usql '$kak_opt_usql_connection'"
        else
            # No configuration, open plain usql
            echo "terminal usql"
        fi
    }
}

# Command to configure usql from Laravel .env file
define-command -hidden usql-from-env -docstring "Configure usql connection from .env file" %{
    evaluate-commands %sh{
        if [ ! -f ".env" ]; then
            echo "echo -markup '{Error}.env file not found'"
            exit
        fi
        
        # Parse .env file for database configuration
        db_connection=""
        db_host=""
        db_port=""
        db_database=""
        db_username=""
        db_password=""
        database_url=""
        
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            case "$key" in
                "#"* | "") continue ;;
            esac
            
            # Remove quotes and whitespace
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | sed 's/^["'\'']*//;s/["'\'']*$//' | tr -d ' ')
            
            case "$key" in
                "DATABASE_URL") database_url="$value" ;;
                "DB_CONNECTION") db_connection="$value" ;;
                "DB_HOST") db_host="$value" ;;
                "DB_PORT") db_port="$value" ;;
                "DB_DATABASE") db_database="$value" ;;
                "DB_USERNAME") db_username="$value" ;;
                "DB_PASSWORD") db_password="$value" ;;
            esac
        done < .env
        
        # Build connection string
        if [ -n "$database_url" ]; then
            connection_string="$database_url"
        else
            # Set defaults
            db_connection=${db_connection:-mysql}
            db_host=${db_host:-127.0.0.1}
            db_username=${db_username:-root}
            
            if [ -z "$db_database" ]; then
                echo "echo -markup '{Error}DB_DATABASE not set in .env file'"
                exit
            fi
            
            case "$db_connection" in
                "sqlite")
                    connection_string="sqlite://$db_database"
                    ;;
                "mysql")
                    db_port=${db_port:-3306}
                    connection_string="mysql://$db_username:$db_password@$db_host:$db_port/$db_database"
                    ;;
                "pgsql"|"postgresql")
                    db_port=${db_port:-5432}
                    connection_string="postgres://$db_username:$db_password@$db_host:$db_port/$db_database"
                    ;;
                *)
                    echo "echo -markup '{Error}Unsupported database connection: $db_connection'"
                    exit
                    ;;
            esac
        fi
        
        if [ -n "$connection_string" ]; then
            echo "set-option buffer usql_connection '$connection_string'"
            echo "echo -markup '{Information}usql configured for $db_connection database: $db_database'"
        else
            echo "echo -markup '{Error}Could not build database connection string'"
        fi
    }
}

# Command to configure usql from Wrangler project
define-command -hidden usql-from-wrangler -params 0..1 -docstring "Configure usql connection from Wrangler project (d1|kv)" %{
    evaluate-commands %sh{
        if [ ! -f "wrangler.toml" ] && [ ! -f "wrangler.jsonc" ]; then
            echo "echo -markup '{Error}wrangler.toml or wrangler.jsonc file not found'"
            exit
        fi
        
        db_type=${1:-d1}  # default to d1 if no parameter
        
        case "$db_type" in
            "d1")
                # Find D1 database
                sqlite_file=$(find .wrangler/state/v3/d1/miniflare-D1DatabaseObject/ -name "*.sqlite" 2>/dev/null | head -1)
                if [ -n "$sqlite_file" ]; then
                    echo "set-option buffer usql_connection 'file:$sqlite_file'"
                    echo "echo -markup '{Information}usql configured for Wrangler D1 database: $(basename "$sqlite_file")'"
                else
                    echo "echo -markup '{Error}No D1 sqlite file found in .wrangler/state/'"
                fi
                ;;
            "kv")
                # Find KV database
                sqlite_file=$(find .wrangler/state/v3/kv/miniflare-KVNamespaceObject/ -name "*.sqlite" 2>/dev/null | head -1)
                if [ -n "$sqlite_file" ]; then
                    echo "set-option buffer usql_connection 'file:$sqlite_file'"
                    echo "echo -markup '{Information}usql configured for Wrangler KV database: $(basename "$sqlite_file")'"
                else
                    echo "echo -markup '{Error}No KV sqlite file found in .wrangler/state/'"
                fi
                ;;
            *)
                echo "echo -markup '{Error}Invalid database type. Use: d1 or kv'"
                ;;
        esac
    }
}
