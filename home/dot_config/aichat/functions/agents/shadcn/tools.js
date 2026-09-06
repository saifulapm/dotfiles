
/**
 * Get configured registry names from components.json - Returns error if no components.json exists (use init_project to create one)
 * @typedef {Object} Args

 * @param {Args} args
 */
exports.get_project_registries = function (args) {
  return callTool('get_project_registries', args)
}

/**
 * List items from registries (requires components.json - use init_project if missing)
 * @typedef {Object} Args
 * @property {String[]} registries - Array of registry names to search (e.g., ['@shadcn', '@acme'])
 * @property {Integer} [limit] - Maximum number of items to return
 * @property {Integer} [offset] - Number of items to skip for pagination
 * @param {Args} args
 */
exports.list_items_in_registries = function (args) {
  return callTool('list_items_in_registries', args)
}

/**
 * Search for components in registries using fuzzy matching (requires components.json). After finding an item, use get_item_examples_from_registries to see usage examples.
 * @typedef {Object} Args
 * @property {String[]} registries - Array of registry names to search (e.g., ['@shadcn', '@acme'])
 * @property {string} query - Search query string for fuzzy matching against item names and descriptions
 * @property {Integer} [limit] - Maximum number of items to return
 * @property {Integer} [offset] - Number of items to skip for pagination
 * @param {Args} args
 */
exports.search_items_in_registries = function (args) {
  return callTool('search_items_in_registries', args)
}

/**
 * View detailed information about specific registry items including the name, description, type and files content. For usage examples, use get_item_examples_from_registries instead.
 * @typedef {Object} Args
 * @property {String[]} items - Array of item names with registry prefix (e.g., ['@shadcn/button', '@shadcn/card'])
 * @param {Args} args
 */
exports.view_items_in_registries = function (args) {
  return callTool('view_items_in_registries', args)
}

/**
 * Find usage examples and demos with their complete code. Search for patterns like 'accordion-demo', 'button example', 'card-demo', etc. Returns full implementation code with dependencies.
 * @typedef {Object} Args
 * @property {String[]} registries - Array of registry names to search (e.g., ['@shadcn', '@acme'])
 * @property {string} query - Search query for examples (e.g., 'accordion-demo', 'button demo', 'card example', 'tooltip-demo', 'example-booking-form', 'example-hero'). Common patterns: '{item-name}-demo', '{item-name} example', 'example {item-name}'
 * @param {Args} args
 */
exports.get_item_examples_from_registries = function (args) {
  return callTool('get_item_examples_from_registries', args)
}

/**
 * Get the shadcn CLI add command for specific items in a registry. This is useful for adding one or more components to your project.
 * @typedef {Object} Args
 * @property {String[]} items - Array of items to get the add command for prefixed with the registry name (e.g., ['@shadcn/button', '@shadcn/card'])
 * @param {Args} args
 */
exports.get_add_command_for_items = function (args) {
  return callTool('get_add_command_for_items', args)
}

/**
 * After creating new components or generating new code files, use this tool for a quick checklist to verify that everything is working as expected. Make sure to run the tool after all required steps have been completed.
 * @typedef {Object} Args

 * @param {Args} args
 */
exports.get_audit_checklist = function (args) {
  return callTool('get_audit_checklist', args)
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
      server_name: 'shadcn',
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
