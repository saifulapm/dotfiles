import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Capability } from "../lib/tools";
import { type ServerConfig, mcpServer } from "./mcp";

// MCP servers are data, not code: which ones exist, and with which
// collections or paths, differs per machine and should not need a rebuild.
// So they live in a chezmoi-managed file beside overrides.json —
// home/dot_config/vicinae/ai-ask-mcp.json — and not in package.json, whose
// preferences are static and shared by every machine. `enabled: false` in the
// file is the off switch, where the code capabilities have a checkbox.
const FILE = join(homedir(), ".config", "vicinae", "ai-ask-mcp.json");

export function mcpServers(): Capability[] {
  let parsed: Record<string, ServerConfig>;
  try {
    parsed = JSON.parse(readFileSync(FILE, "utf8"));
  } catch {
    // No file, or a broken one: no servers. A machine mid-apply still gets
    // the chat.
    return [];
  }
  return Object.entries(parsed)
    // "//" keys are comments, the convention overrides.json uses.
    .filter(([id, config]) => !id.startsWith("//") && config.enabled !== false)
    .map(([id, config]) => mcpServer(id, config));
}
