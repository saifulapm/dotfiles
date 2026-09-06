#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const MCP_HUB_URL = "http://localhost:3123/api/servers/info";
const AGENTS_DIR = path.join(__dirname, "..", "agents");

async function main() {
  const serverName = process.argv[2];

  if (!serverName) {
    console.error("Usage: node generate-agent-from-mcp.js <server-name>");
    console.error("Example: node generate-agent-from-mcp.js laravel");
    process.exit(1);
  }

  try {
    // Fetch MCP server info
    console.log(`Fetching info for MCP server: ${serverName}`);
    const serverInfo = await fetchMCPServerInfo(serverName);

    if (!serverInfo || !serverInfo.server) {
      throw new Error(`Could not fetch server info for: ${serverName}`);
    }

    const tools = serverInfo.server.capabilities?.tools || [];

    if (tools.length === 0) {
      throw new Error(`No tools found for server: ${serverName}`);
    }

    console.log(`Found ${tools.length} tools`);

    // Generate agent files
    const agentDir = path.join(AGENTS_DIR, serverName);
    const agentExists = fs.existsSync(agentDir);

    if (!agentExists) {
      console.log(`Creating new agent directory: ${agentDir}`);
      fs.mkdirSync(agentDir, { recursive: true });
    }

    // Generate tools.js
    const toolsJs = generateToolsJs(tools, serverName);
    const toolsPath = path.join(agentDir, "tools.js");
    fs.writeFileSync(toolsPath, toolsJs);
    console.log(`Generated: ${toolsPath}`);

    // Generate index.yaml if it doesn't exist
    const indexPath = path.join(agentDir, "index.yaml");
    if (!fs.existsSync(indexPath)) {
      const indexYaml = generateIndexYaml(serverName, serverInfo.server);
      fs.writeFileSync(indexPath, indexYaml);
      console.log(`Generated: ${indexPath}`);
    } else {
      console.log(`Skipped: ${indexPath} (already exists)`);
    }

    // Update agents.txt if this is a new agent
    if (!agentExists) {
      updateAgentsList(serverName);
    }

    console.log(`\n✅ Agent '${serverName}' ${agentExists ? 'updated' : 'created'} successfully!`);
    console.log(`\n📝 Next step: Run 'argc build' to generate functions.json from tools.js`);
  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

/**
 * Fetch MCP server info from mcphub
 */
async function fetchMCPServerInfo(serverName) {
  const response = await fetch(MCP_HUB_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ server_name: serverName })
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }

  return response.json();
}

/**
 * Generate tools.js content
 */
function generateToolsJs(tools, serverName) {
  const functions = tools.map(tool => {
    const funcName = convertToFunctionName(tool.name);
    const description = tool.description || "";
    const params = extractParams(tool.inputSchema);

    const propertyLines = params.map(p => {
      const propName = formatPropertyName(p.name, p.required, p.defaultValue);
      const propType = p.type;
      const propDesc = p.description ? ` - ${p.description}` : '';
      return ` * @property {${propType}} ${propName}${propDesc}`;
    }).join('\n');

    return `
/**
 * ${description}
 * @typedef {Object} Args
${propertyLines}
 * @param {Args} args
 */
exports.${funcName} = function (args) {
  return callTool('${tool.name}', args)
}`;
  }).join('\n');

  return `${functions}

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
      server_name: '${serverName}',
      tool,
      arguments: args,
      request_options: {}
    })
  });

  if (!res.ok) {
    throw new Error(\`Error calling tool \${tool}: \${res.status} \${res.statusText}\`);
  }
  return res.json();
}
`;
}

/**
 * Format property name with optional brackets and default value
 */
function formatPropertyName(name, required, defaultValue) {
  if (required) {
    return name;
  }

  if (defaultValue !== null && defaultValue !== undefined) {
    // Format the default value appropriately
    let formattedDefault;
    if (Array.isArray(defaultValue)) {
      // For arrays, use JSON format so build-declarations.js can parse it
      formattedDefault = JSON.stringify(defaultValue);
    } else if (typeof defaultValue === 'string') {
      formattedDefault = defaultValue;
    } else {
      formattedDefault = String(defaultValue);
    }
    return `[${name}=${formattedDefault}]`;
  }

  return `[${name}]`;
}


/**
 * Generate index.yaml content
 */
function generateIndexYaml(serverName, serverInfo) {
  const displayName = serverInfo.displayName || capitalize(serverName);
  const description = serverInfo.description || `An AI agent for ${serverName}`;

  return `name: ${displayName}
description: ${description}
version: 0.1.0

instructions: |
  You are a ${serverName} agent with powerful tools designed for this application.

  ## Core Capabilities

  You have access to the following tools:
  {{__tools__}}

  Use these tools effectively to help users with ${serverName}-related tasks.

conversation_starters:
  - "What can you help me with?"
  - "Show me what tools are available"
`;
}

/**
 * Convert tool name to valid JavaScript function name
 */
function convertToFunctionName(toolName) {
  return toolName.replace(/-/g, '_');
}


/**
 * Extract parameters for JSDoc
 */
function extractParams(inputSchema) {
  if (!inputSchema || !inputSchema.properties) {
    return [];
  }

  const params = [];
  const required = inputSchema.required || [];
  const processedArrays = new Set();

  for (const [key, value] of Object.entries(inputSchema.properties)) {
    const param = {
      name: key,
      type: getJSDocType(value),
      description: value.description || "",
      required: required.includes(key),
      defaultValue: value.default
    };

    params.push(param);

    // Handle nested object array properties
    if (value.type === "array" && value.items && value.items.type === "object" && value.items.properties) {
      processedArrays.add(key);
      for (const [nestedKey, nestedValue] of Object.entries(value.items.properties)) {
        const nestedRequired = value.items.required || [];
        params.push({
          name: `${key}[].${nestedKey}`,
          type: getJSDocType(nestedValue),
          description: nestedValue.description || "",
          required: nestedRequired.includes(nestedKey),
          defaultValue: nestedValue.default,
          isNested: true
        });
      }
    }
  }

  return params;
}

/**
 * Get JSDoc type string from schema property
 */
function getJSDocType(prop) {
  // Handle array of enums
  if (prop.type === "array" && prop.items && prop.items.enum) {
    return `(${prop.items.enum.map(v => `'${v}'`).join('|')})[]`;
  }

  // Handle enums (non-array)
  if (prop.enum && Array.isArray(prop.enum)) {
    return prop.enum.map(v => `'${v}'`).join('|');
  }

  // Handle arrays
  if (prop.type === "array") {
    if (prop.items && prop.items.type === "object") {
      return "Object[]";
    }
    if (prop.items && prop.items.type) {
      const itemType = prop.items.type.charAt(0).toUpperCase() + prop.items.type.slice(1);
      return `${itemType}[]`;
    }
    return "array";
  }

  // Handle integer
  if (prop.type === "integer" || prop.type === "number") {
    return "Integer";
  }

  // Capitalize first letter for basic types
  if (prop.type) {
    return prop.type.charAt(0).toLowerCase() + prop.type.slice(1);
  }

  return "any";
}

/**
 * Capitalize first letter
 */
function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

/**
 * Update agents.txt to include the new agent
 */
function updateAgentsList(serverName) {
  const agentsTxtPath = path.join(__dirname, "..", "agents.txt");

  if (!fs.existsSync(agentsTxtPath)) {
    console.log(`Creating agents.txt with agent: ${serverName}`);
    fs.writeFileSync(agentsTxtPath, `${serverName}\n`);
    return;
  }

  const content = fs.readFileSync(agentsTxtPath, "utf8");
  const lines = content.split("\n").map(l => l.trim()).filter(l => l);

  if (lines.includes(serverName)) {
    console.log(`Agent '${serverName}' already in agents.txt`);
    return;
  }

  // Add before 'demo' if it exists, otherwise add at the end
  const demoIndex = lines.indexOf('demo');
  if (demoIndex !== -1) {
    lines.splice(demoIndex, 0, serverName);
  } else {
    lines.push(serverName);
  }

  fs.writeFileSync(agentsTxtPath, lines.join("\n") + "\n");
  console.log(`Added '${serverName}' to agents.txt`);
}

main();
