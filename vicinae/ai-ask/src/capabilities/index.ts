import type { Capability } from "../lib/tools";
import { mcpServers } from "./servers";
import { web } from "./web";

/** Everything the chat can call. A code capability is a file beside this
 *  one, a line here, and a checkbox preference of the same id in
 *  package.json; an MCP server is an entry in ai-ask-mcp.json (servers.ts). */
export const capabilities: Capability[] = [web, ...mcpServers()];
