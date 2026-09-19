import type { AssistantMessage, Context, Model, Usage } from "@earendil-works/pi-ai";
import { streamSimple } from "@earendil-works/pi-ai/api/openai-completions";
import { getPreferenceValues } from "@vicinae/api";
import type { AgentTool, Step } from "./tools";

// pxy, Saiful's local LLM proxy (home/dot_config/pxy/config.toml), spoken to
// through pi-ai's openai-completions implementation.
//
// WHY NOT the `AI` export from @vicinae/api: it is a declared stub —
// src/typescript/api/src/api/ai.ts is marked "we don't support AI yet" and
// AI.ask() throws "not implemented", with no C++ service behind it.
//
// WHY pi-ai rather than a hand-rolled SSE parser: reasoning. pxy's default
// group streams `delta.reasoning` with `delta.content` empty for several
// seconds, which is not in the OpenAI spec and which a naive parser renders as
// a blank, hung-looking pane. pi-ai models it as real `thinking_*` events, so
// that channel is a typed event here instead of something inferred. The API
// implementation is imported on its own — the package's provider collection,
// auth resolution and model catalog are not needed for one fixed local
// endpoint, and skipping them keeps the bundle to ~400KB.
export const ENDPOINT = "http://127.0.0.1:4100/v1";
export const TOKEN = "pxy-local";

// Rounds of "model calls tools, tools answer, model continues" per turn.
// nemotron will search and fetch indefinitely if allowed (six calls and no
// answer, verified). After TOOL_ROUNDS of them comes one last call that has
// to be the answer: no tools in the request, reasoning off, and a message
// saying so. All three are needed. `toolChoice: "none"` is ignored by
// ollama.com's nemotron (verified: still called the tool), and merely
// dropping the tools from the request is not enough either — with four
// tool calls in its context it reasons its way to a fifth, emits it as a
// tool call, and the turn ends with no answer at all (verified 2026-09-14:
// every empty answer in the chat history ended this way). With
// `reasoning_effort: none` it cannot plan the call it is not offered, so it
// answers from what it has.
const TOOL_ROUNDS = 4;
const ANSWER_NOW =
  "The tools are no longer available. Answer the question now from what you have found; if it is not there, say what you found instead.";

/** The conversation so far, oldest first. A follow-up only makes sense to the
 *  model if the earlier turns come with it — pxy keeps no state of its own,
 *  so the whole history is resent on every request. */
export type Message = { role: "user" | "assistant"; content: string };

/** What a caller has to render. `provider` arrives once, before any token,
 *  because pxy names the provider that won the failover race in a response
 *  header rather than in the body. */
export type Event =
  | { type: "provider"; provider: string | null }
  | { type: "reasoning"; delta: string }
  | { type: "content"; delta: string }
  /** A tool call, once when it starts and once when it ends — same id, so
   *  the caller upserts. Reasoning streamed before it belongs to it. */
  | { type: "step"; step: Step }
  /** The stream ended on its own. `length` means the model hit the token
   *  cap mid-sentence, which otherwise reads as a finished answer. */
  | { type: "done"; reason: "stop" | "length" };

export function model(): string {
  return getPreferenceValues<Preferences>().model ?? "chat";
}

/** The dropdown's fallback list, mirroring the `model` preference in
 *  package.json, used until `listModels()` answers or when pxy is down.
 *  Duplicated rather than imported: the manifest is not reachable from the
 *  bundle `vici build` produces. */
export const GROUPS = [
  { value: "chat", title: "Chat (alias: free chain)" },
  { value: "default", title: "Default (alias: coding chain)" },
  { value: "aaa", title: "AAA" },
  { value: "deepseek", title: "Deepseek" },
  { value: "muse", title: "Muse" },
  { value: "glm", title: "GLM" },
  { value: "gpt", title: "GPT" },
  { value: "qwen", title: "Qwen" },
];

/** Every routable name pxy serves that is not a single provider/model: the
 *  aliases and the groups, in the order /v1/models lists them (groups first,
 *  aliases after), so a group renamed in pxy's config shows up here on the
 *  next open with no edit to this extension. Falls back to GROUPS when pxy
 *  does not answer. */
export async function listModels(): Promise<{ value: string; title: string }[]> {
  try {
    const res = await fetch(`${ENDPOINT}/models`, {
      headers: { Authorization: `Bearer ${TOKEN}` },
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) return GROUPS;
    const body = (await res.json()) as { data?: { id: string; display_name?: string }[] };
    const rows = (body.data ?? [])
      .filter((m) => !m.id.includes("/"))
      .map((m) => ({ value: m.id, title: m.display_name && m.display_name !== m.id ? `${m.id} (${m.display_name})` : m.id }));
    return rows.length ? rows : GROUPS;
  } catch {
    return GROUPS;
  }
}

/** A pxy group described as a pi-ai model. The id is a GROUP name, not a real
 *  model — pxy resolves it through a failover chain — so the catalogue fields
 *  below are nominal. pxy's first hop is ollama.com's hosted API (not a local
 *  daemon — nothing listens on 11434 here), which does not understand the
 *  `developer` role.
 *
 *  `reasoning` decides whether the request carries `reasoning_effort: none`.
 *  pi-ai only sends that field when `supportsReasoningEffort` is on and no
 *  level is asked for, so the flag is what toggles it — and pxy does pass it
 *  through to nemotron (verified: 1.1 s and no thinking, against 8 s and an
 *  empty answer without it). Reasoning stays on for the tool rounds because
 *  the thinking is what the transcript shows while a search runs. */
function groupModel(group: string, reasoning: boolean): Model<"openai-completions"> {
  return {
    id: group,
    name: `pxy ${group}`,
    api: "openai-completions",
    provider: "pxy",
    baseUrl: ENDPOINT,
    reasoning: true,
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 128000,
    maxTokens: 16384,
    thinkingLevelMap: { off: "none" },
    compat: { supportsDeveloperRole: false, supportsReasoningEffort: !reasoning },
  };
}

/** Replayed turns carry no counters: these describe a response pi-ai itself
 *  produced, and ours came back out of LocalStorage. */
const NO_USAGE: Usage = {
  input: 0,
  output: 0,
  cacheRead: 0,
  cacheWrite: 0,
  totalTokens: 0,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};

/** pi-ai's history is richer than ours — an assistant turn is content blocks
 *  plus the provenance of the response it came from. Rehydrating a stored
 *  answer means supplying that shape; only `content` survives a round trip
 *  through storage, so the rest is stated rather than remembered. */
function toContext(messages: Message[], group: string): Context {
  return {
    // The date is the one thing a model reliably lacks and reliably needs:
    // asked for "the newest kernel release" with web search available,
    // nemotron spent a search on "current date" before the real one. The
    // wording is load-bearing: a bare "Today is Monday, September 14, 2026."
    // was twice "corrected" by nemotron to a date in 2025 (verified), because
    // a year past its training reads as a mistake. Saying where the date
    // comes from stops that.
    systemPrompt: `The current date is ${today()}. It comes from the system clock; trust it over anything you assume.`,
    messages: messages.map((message) =>
      message.role === "user"
        ? { role: "user", content: message.content, timestamp: Date.now() }
        : {
          role: "assistant",
          content: [{ type: "text", text: message.content }],
          api: "openai-completions",
          provider: "pxy",
          model: group,
          usage: NO_USAGE,
          stopReason: "stop",
          timestamp: Date.now(),
        }
    ),
  };
}

function today(): string {
  return new Date().toLocaleDateString(undefined, {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

/** One turn: stream the model, and while it asks for tools, run them and
 *  stream again with the results appended. Tool calls and results are kept
 *  in this turn's context only — the transcript's history (`Message`) is the
 *  question and the final answer, so a later follow-up does not resend
 *  every search result. */
export async function* ask(
  messages: Message[],
  group: string,
  signal: AbortSignal,
  tools: AgentTool[] = [],
): AsyncGenerator<Event> {
  // undefined until the response headers land, then the header value or null.
  // Distinguishing the two is what lets the provider be announced exactly once
  // even when pxy did not send the header.
  let provider: string | null | undefined;
  let announced = false;

  const context = toContext(messages, group);
  if (tools.length) {
    context.tools = tools;
    context.systemPrompt +=
      " Use tools only when the answer depends on something you cannot know, and answer as soon as you have enough; do not keep searching to confirm.";
  }

  for (let round = 0; round <= TOOL_ROUNDS; round++) {
    const last = round === TOOL_ROUNDS;
    if (last && context.tools) {
      delete context.tools;
      context.messages.push({ role: "user", content: ANSWER_NOW, timestamp: Date.now() });
    }
    const stream = streamSimple(groupModel(group, !last), context, {
      apiKey: TOKEN,
      signal,
      onResponse: (response) => {
        provider = response.headers["x-pxy-provider"] ?? null;
      },
    });

    let done: AssistantMessage | null = null;
    for await (const event of stream) {
      if (!announced && provider !== undefined) {
        announced = true;
        yield { type: "provider", provider };
      }

      // Only the two content channels matter here. Blocks may interleave
      // and carry a contentIndex, but both channels are accumulated into
      // one string apiece by every caller, so the index is nothing this has
      // to preserve. Tool calls are read whole off the finished message
      // rather than assembled from deltas: nothing runs before the model
      // has finished asking.
      switch (event.type) {
        case "thinking_delta":
          yield { type: "reasoning", delta: event.delta };
          break;
        case "text_delta":
          yield { type: "content", delta: event.delta };
          break;
        case "done":
          // On the last call a tool call is not honoured: whatever text came
          // with it is the answer, and none is "no answer", reported as such.
          if (event.reason !== "toolUse" || last) {
            yield { type: "done", reason: event.reason === "length" ? "length" : "stop" };
            return;
          }
          done = event.message;
          break;
        case "error":
          // pi-ai does not throw once a stream exists: a failure, an abort
          // and a refused connection all arrive here. An abort is the caller
          // closing the view or pressing Stop, so it ends the generator
          // quietly and leaves whatever already streamed in place.
          if (event.reason === "aborted") return;
          throw new Error(readable(event.error?.errorMessage));
      }
    }
    if (!done) return;

    // The model's request goes into the context as-is, then one result per
    // call — the shape the wire needs. Sequential: nothing here is slow
    // enough to be worth interleaving, and the transcript reads in order.
    context.messages.push(done);
    for (const block of done.content) {
      if (block.type !== "toolCall") continue;
      const tool = tools.find((t) => t.name === block.name);
      const step: Step = {
        id: block.id,
        label: tool ? tool.label(block.arguments) : block.name,
        status: "running",
        summary: "",
        ms: 0,
        reasoning: "",
      };
      yield { type: "step", step: { ...step } };
      const startedAt = Date.now();
      let text: string;
      let isError = false;
      try {
        if (!tool) throw new Error(`no such tool: ${block.name}`);
        const out = await tool.run(block.arguments, signal);
        text = out.text;
        step.summary = out.summary;
      } catch (thrown) {
        if (signal.aborted) return;
        // The model is told, so it can try something else; the person sees
        // the same message on the step line.
        isError = true;
        text = `Error: ${thrown instanceof Error ? thrown.message : String(thrown)}`;
        step.summary = text;
      }
      step.status = isError ? "error" : "done";
      step.ms = Date.now() - startedAt;
      yield { type: "step", step: { ...step } };
      context.messages.push({
        role: "toolResult",
        toolCallId: block.id,
        toolName: block.name,
        content: [{ type: "text", text }],
        isError,
        timestamp: Date.now(),
      });
    }
  }
}

/** The openai client collapses every transport failure into "Connection
 *  error.", which tells nobody anything. Everything else pxy says — an
 *  exhausted failover chain names the providers it tried — is already the most
 *  useful thing available, so it passes through untouched. */
function readable(message: string | undefined): string {
  const text = message?.trim() || "The request failed.";
  if (/^connection error/i.test(text)) {
    return "pxy is not running on 127.0.0.1:4100.";
  }
  return text;
}
