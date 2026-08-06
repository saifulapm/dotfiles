
/**
 * List all available Laravel configuration keys (from config/*.php) in dot notation.
 * @typedef {Object} Args

 * @param {Args} args
 */
exports.list_available_config_keys = function (args) {
  return callTool('list-available-config-keys', args)
}

/**
 * Get details of the last error/exception created in this application on the backend. Use browser-log tool for browser errors.
 * @typedef {Object} Args

 * @param {Args} args
 */
exports.last_error = function (args) {
  return callTool('last-error', args)
}

/**
 * List all available Artisan commands registered in this application.
 * @typedef {Object} Args

 * @param {Args} args
 */
exports.list_artisan_commands = function (args) {
  return callTool('list-artisan-commands', args)
}

/**
 * Read the database schema for this application, including table names, columns, data types, indexes, foreign keys, and more.
 * @typedef {Object} Args
 * @property {string} [database] - Name of the database connection to dump (defaults to app's default connection, often not needed)
 * @property {string} [filter] - Filter the tables by name
 * @param {Args} args
 */
exports.database_schema = function (args) {
  return callTool('database-schema', args)
}

/**
 * Report feedback from the user on what would make Boost, or their experience with Laravel, better. Ask the user for more details before use if ambiguous or unclear. This is only for feedback related to Boost or the Laravel ecosystem.
Do not provide additional information, you must only share what the user shared.
 * @typedef {Object} Args
 * @property {string} feedback - Detailed feedback from the user on what would make Boost, or their experience with Laravel, better. Ask the user for more details if ambiguous or unclear.
 * @param {Args} args
 */
exports.report_feedback = function (args) {
  return callTool('report-feedback', args)
}

/**
 * Execute a read-only SQL query against the configured database.
 * @typedef {Object} Args
 * @property {string} query - The SQL query to execute. Only read-only queries are allowed (i.e. SELECT, SHOW, EXPLAIN, DESCRIBE).
 * @property {string} [database] - Optional database connection name to use. Defaults to the application's default connection.
 * @param {Args} args
 */
exports.database_query = function (args) {
  return callTool('database-query', args)
}

/**
 * Get the value of a specific config variable using dot notation (e.g., "app.name", "database.default")
 * @typedef {Object} Args
 * @property {string} key - The config key in dot notation (e.g., "app.name", "database.default")
 * @param {Args} args
 */
exports.get_config = function (args) {
  return callTool('get-config', args)
}

/**
 * Get comprehensive application information including PHP version, Laravel version, database engine, all installed packages with their versions, and all Eloquent models in the application. You should use this tool on each new chat, and use the package & version data to write version specific code for the packages that exist.
 * @typedef {Object} Args

 * @param {Args} args
 */
exports.application_info = function (args) {
  return callTool('application-info', args)
}

/**
 * Search for up-to-date version-specific documentation related to this project and its packages. This tool will search Laravel hosted documentation based on the packages installed and is perfect for all Laravel ecosystem packages. Laravel, Inertia, Pest, Livewire, Filament, Nova, Tailwind, and more. You must use this tool to search for Laravel-ecosystem docs before using other approaches. The results provided are for this project's package version and does not cover all versions of the package.
 * @typedef {Object} Args
 * @property {String[]} queries - List of queries to perform, pass multiple if you aren't sure if it is "toggle" or "switch", for example
 * @property {String[]} [packages] - Package names to limit searching to from application-info. Useful if you know the package(s) you need. i.e. laravel/framework, inertiajs/inertia-laravel, @inertiajs/react
 * @property {Integer} [token_limit] - Maximum number of tokens to return in the response. Defaults to 10,000 tokens, maximum 1,000,000 tokens.
 * @param {Args} args
 */
exports.search_docs = function (args) {
  return callTool('search-docs', args)
}

/**
 * 🔧 List all available environment variable names from a given .env file (default .env).
 * @typedef {Object} Args
 * @property {string} [filename] - The name of the .env file to read (e.g. .env, .env.example). Defaults to .env if not provided.
 * @param {Args} args
 */
exports.list_available_env_vars = function (args) {
  return callTool('list-available-env-vars', args)
}

/**
 * Get the absolute URL for a given relative path or named route. If no arguments are provided, you will get the absolute URL for "/"
 * @typedef {Object} Args
 * @property {string} [path] - The relative URL/path (e.g. "/dashboard") to convert to an absolute URL.
 * @property {string} [route] - The named route to generate an absolute URL for (e.g. "home").
 * @param {Args} args
 */
exports.get_absolute_url = function (args) {
  return callTool('get-absolute-url', args)
}

/**
 * Read the last N log entries from the application log, correctly handling multi-line PSR-3 formatted logs. Only works for log files.
 * @typedef {Object} Args
 * @property {Integer} entries - Number of log entries to return.
 * @param {Args} args
 */
exports.read_log_entries = function (args) {
  return callTool('read-log-entries', args)
}

/**
 * Read the last N log entries from the BROWSER log. Very helpful for debugging the frontend and JS/Javascript
 * @typedef {Object} Args
 * @property {Integer} entries - Number of log entries to return.
 * @param {Args} args
 */
exports.browser_logs = function (args) {
  return callTool('browser-logs', args)
}

/**
 * Execute PHP code in the Laravel application context, like artisan tinker. Use this for debugging issues, checking if functions exist, and testing code snippets. You should not create models directly without explicit user approval. Prefer Unit/Feature tests using factories for functionality testing. Prefer existing artisan commands over custom tinker code. Returns the output of the code, as well as whatever is "returned" using "return".
 * @typedef {Object} Args
 * @property {string} code - PHP code to execute (without opening <?php tags)
 * @property {Integer} timeout - Maximum execution time in seconds (default: 180)
 * @param {Args} args
 */
exports.tinker = function (args) {
  return callTool('tinker', args)
}

/**
 * List all available routes defined in the application, including Folio routes if used
 * @typedef {Object} Args
 * @property {string} [method] - Filter the routes by HTTP method (e.g., GET, POST, PUT, DELETE).
 * @property {string} [action] - Filter the routes by controller action (e.g., UserController@index, ChatController, show).
 * @property {string} [name] - Filter the routes by route name (no wildcards supported).
 * @property {string} [domain] - Filter the routes by domain.
 * @property {string} [path] - Only show routes matching the given path pattern.
 * @property {string} [except_path] - Do not display the routes matching the given path pattern.
 * @property {boolean} [except_vendor] - Do not display routes defined by vendor packages.
 * @property {boolean} [only_vendor] - Only display routes defined by vendor packages.
 * @param {Args} args
 */
exports.list_routes = function (args) {
  return callTool('list-routes', args)
}

/**
 * List the configured database connection names for this application.
 * @typedef {Object} Args

 * @param {Args} args
 */
exports.database_connections = function (args) {
  return callTool('database-connections', args)
}

/**
 * Helper to call mcphub tool endpoint.
 * @param {string} tool - The tool name to call
 * @param {Object} args - The arguments to pass to the tool
 * @returns {Promise<any>}
 */
async function callTool(tool, args = {}) {
  const res = await fetch('http://localhost:3123/api/servers/tools', {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      server_name: 'laravel',
      tool,
      arguments: args,
      request_options: {}
    })
  });

  if (!res.ok) {
    throw new Error(`Error calling tool ${tool}: ${res.status} ${res.statusText}`);
  }
  return res.json();
}
