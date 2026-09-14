import type { Tool } from "@earendil-works/pi-ai";
import { Toast, getPreferenceValues, showToast } from "@vicinae/api";
import { capabilities } from "../capabilities";

/** A tool the model may call, plus how this extension runs it. `Tool` is
 *  pi-ai's declaration (name, description, JSON-schema parameters); the rest
 *  is ours. `run` gets the stream's abort signal so Stop cancels a search the
 *  same way it cancels the model. */
export type AgentTool = Tool & {
  run(args: Record<string, unknown>, signal: AbortSignal): Promise<ToolOutput>;
  /** One line for the transcript: `web_search "newest kernel"`. */
  label(args: Record<string, unknown>): string;
};

export type ToolOutput = {
  /** What the model is shown. */
  text: string;
  /** What the person is shown, after the label: "5 results". */
  summary: string;
};

/** A source of tools: a file under src/capabilities, or an MCP server. Tools
 *  are resolved lazily and per conversation because an MCP server has to be
 *  spawned and asked before its tools are known, and should not be spawned
 *  for a conversation that never uses it. */
export type Capability = {
  /** Also the name of the checkbox preference that enables it. */
  id: string;
  title: string;
  tools(): Promise<AgentTool[]>;
  /** Anything spawned: an MCP server's process. */
  close?(): Promise<void>;
};

/** One tool call as the transcript shows it, in the order it happened. The
 *  reasoning that led to it rides along so the transcript can stay in
 *  arrival order: think, call, think again, answer. */
export type Step = {
  id: string;
  label: string;
  status: "running" | "done" | "error";
  summary: string;
  ms: number;
  reasoning: string;
};

/** The tools of every capability whose preference is on. One that fails to
 *  come up — an MCP server that is not installed — is reported and left
 *  out, so the message still goes with the tools that did. */
export async function enabledTools(): Promise<AgentTool[]> {
  const prefs = getPreferenceValues<Record<string, unknown>>();
  const lists = await Promise.all(
    capabilities
      .filter((c) => prefs[c.id] !== false)
      .map((c) =>
        c.tools().catch((thrown) => {
          void showToast({
            style: Toast.Style.Failure,
            title: `${c.title}: tools unavailable`,
            message: thrown instanceof Error ? thrown.message : String(thrown),
          });
          return [] as AgentTool[];
        }),
      ),
  );
  return lists.flat();
}

export async function closeTools(): Promise<void> {
  await Promise.all(capabilities.map((c) => c.close?.()));
}
