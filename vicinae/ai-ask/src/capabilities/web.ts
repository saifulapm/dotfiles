import type { Capability } from "../lib/tools";
import { ENDPOINT, TOKEN } from "../lib/pxy";

// Web search and page fetching through pxy's own services — the same
// providers and quota accounting `pxy search` uses.
//
// WHY NOT pxy's hosted search (a function tool named `pxy_web_search` that
// pxy intercepts and answers inside the same stream): it signals a search in
// progress with a chunk whose `choices` is empty, and pi-ai's parser skips
// exactly those chunks, so the search would be a silent multi-second gap in
// the reasoning — the hung-looking pane all over again. Run as a client tool
// it is a line in the transcript instead. Same round trip either way: pxy's
// continuation also replays the conversation.

async function call(path: string, body: unknown, signal: AbortSignal): Promise<any> {
  const response = await fetch(`${ENDPOINT}/${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
  const json: any = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(json?.error?.message || `pxy answered ${response.status}`);
  }
  return json;
}

export const web: Capability = {
  id: "webTools",
  title: "Web",
  async tools() {
    return [
      {
        name: "web_search",
        description:
          "Search the public web. Returns title, url and snippet for each hit. Use it whenever the answer depends on current events, prices, releases, or anything else that may have changed since training.",
        parameters: {
          type: "object",
          properties: { query: { type: "string", description: "The search query." } },
          required: ["query"],
        } as any,
        label: (args) => `web_search "${args.query}"`,
        async run(args, signal) {
          const out = await call("search", { query: args.query, max_results: 5 }, signal);
          const results: any[] = out.results ?? [];
          const text = results.length
            ? results
                .map((r, i) => `[${i + 1}] ${r.title}\n${r.url}\n${r.snippet ?? ""}`)
                .join("\n\n")
            : "No results found.";
          return { text, summary: `${results.length} results via ${out.provider}` };
        },
      },
      {
        name: "fetch_url",
        description:
          "Fetch a web page and return its content as markdown. Use it to read a page a search result points at, or a URL the user gave.",
        parameters: {
          type: "object",
          properties: { url: { type: "string", description: "The absolute http(s) URL." } },
          required: ["url"],
        } as any,
        label: (args) => `fetch_url ${args.url}`,
        async run(args, signal) {
          const out = await call("fetch", { url: args.url }, signal);
          // Pages run long and every character is resent on each later
          // round; a cap keeps one fetch from crowding out the question.
          const content: string = (out.content ?? "").slice(0, 20000);
          return { text: content || "(empty page)", summary: `${content.length} chars via ${out.provider}` };
        },
      },
    ];
  },
};
