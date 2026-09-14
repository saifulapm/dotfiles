import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import type { AgentTool, Capability } from "../lib/tools";

// An MCP server as a capability: spawned over stdio the first time a
// conversation with it enabled sends a message, asked for its tools, and
// asked to run them. pi has no MCP of its own — the pi-coding-agent README
// says "No MCP" as a position — so this is the whole client, on the official
// SDK's stdio transport (v1; the v2 split package is larger and pulls zod 4).
//
// stdio and not HTTP because the server is a child of this worker: it lives
// as long as the chat does and dies with it, and nothing has to be daemonised
// or port-managed. For qmd that also means its ~2 GB of GGUF models load once
// per conversation instead of once per call.

export type ServerConfig = {
  command: string;
  args?: string[];
  env?: Record<string, string>;
  title?: string;
  enabled?: boolean;
  /** Appended to every tool description: what the server does not say
   *  about itself but the model needs — qmd's collection names, say. */
  description?: string;
};

// qmd's reranked query took over a minute on this CPU while the embedding
// service was running, and the SDK's default request timeout is 60 s. A
// tool call is abortable by Stop anyway, so the timeout only has to catch a
// server that hung.
const CALL_TIMEOUT_MS = 5 * 60 * 1000;

export function mcpServer(id: string, config: ServerConfig): Capability & { close(): Promise<void> } {
  let client: Client | null = null;

  const connect = async () => {
    if (client) return client;
    const next = new Client({ name: "vicinae-ai-ask", version: "0" });
    await next.connect(
      new StdioClientTransport({
        command: config.command,
        args: config.args ?? [],
        env: { ...(process.env as Record<string, string>), ...config.env },
        // Its stderr would otherwise be the launcher's journal, tagged as
        // vicinae's own noise.
        stderr: "ignore",
      }),
    );
    client = next;
    return next;
  };

  return {
    id,
    title: config.title ?? id,
    async tools() {
      const c = await connect();
      const { tools } = await c.listTools();
      return tools.map(
        (tool): AgentTool => ({
          // Prefixed so two servers cannot collide, and so the step line
          // says which one ran.
          name: `${id}__${tool.name}`,
          description: [tool.description ?? tool.name, config.description].filter(Boolean).join("\n\n"),
          parameters: tool.inputSchema as any,
          label: (args) => `${id}: ${tool.name} ${JSON.stringify(args)}`,
          async run(args, signal) {
            const result = await c.callTool(
              { name: tool.name, arguments: coerce(args, tool.inputSchema) },
              undefined,
              { signal, timeout: CALL_TIMEOUT_MS },
            );
            // Text, or an embedded resource — qmd's `get` answers with the
            // document as a resource block, uri + mimeType + text — and a
            // placeholder for anything else (an image, say).
            const blocks = (result.content ?? []) as Array<{
              type: string;
              text?: string;
              resource?: { text?: string };
            }>;
            const text = blocks
              .map((b) =>
                b.type === "text" ? b.text ?? "" : b.type === "resource" ? b.resource?.text ?? "" : `(${b.type} content)`,
              )
              .join("\n");
            if (result.isError) throw new Error(text || "tool reported an error");
            return { text: text || "(no output)", summary: `${text.length} chars` };
          },
        }),
      );
    },
    async close() {
      const c = client;
      client = null;
      await c?.close();
    },
  };
}

/** Small models sometimes send an array or object argument as its JSON
 *  text (`"collections": "[\"mem\"]"`, verified with nemotron), which the
 *  server rejects. Where the schema says array or object and the value is a
 *  string that parses, unwrap it; anything else passes through untouched. */
function coerce(args: Record<string, unknown>, schema: any): Record<string, unknown> {
  const out = { ...args };
  for (const [key, value] of Object.entries(out)) {
    const type = schema?.properties?.[key]?.type;
    if ((type === "array" || type === "object") && typeof value === "string") {
      try {
        out[key] = JSON.parse(value);
      } catch {
        // Not JSON: leave it and let the server say so.
      }
    }
  }
  return out;
}
