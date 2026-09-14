# AI in the launcher, part 2: review, and how it grows tools — 2026-09-14

`vicinae/ai-ask` gives the launcher Raycast's Quick AI (type, Tab, answer) and
AI Chat, both through pxy. This note reviews what is in the working tree and
designs how the same extension becomes a platform: tool calling first, then
web search, MCP servers (qmd as the worked example), and image and video
generation. Everything marked **verified** was run on this machine today;
the section at the end lists what was not.

Nothing here is committed. The review findings apply to the tree as it stands;
the design is a plan, and only its riskiest assumptions were prototyped.

## What exists, in one paragraph

Two `view` commands. `ask` is the first fallback, so Tab on any typed phrase
streams an answer into a `Detail`. `chat` is a `List` with one hidden row whose
`List.Item.Detail` is the whole transcript, the search bar as composer, a group
dropdown, and history in LocalStorage. `src/lib/pxy.ts` talks to pxy through
pi-ai's `openai-completions` implementation, imported on its own; a pxy group
name is the model id. Two local patches to vicinae carry it: `ActivateFallback`
(Tab) and `hideListPane` (full-width transcript). `bin/vicinae-rebuild` applies
every `packages/vicinae-*.patch` in glob order.

## 1. Review

Ordered by how much they matter. Each says how it was established.

### 1.0 "ollama" is ollama.com, not a local daemon — verified

Every description of this feature, including the brief for this review, says
the `general` group "starts at local ollama, so the common case is local,
free and private". It does not. `[providers.ollama]` in pxy's config is
`base_url = "https://ollama.com/v1/chat/completions"` with an API key from
`pass`; nothing listens on 11434 on this machine, and the response headers
carry `via: 1.1 google`. `general` is `ollama/nemotron-3-nano:30b` then
`cloudflare/@cf/meta/llama-4-scout-17b-16e-instruct`: two cloud hops. The
`model` preference description in `package.json` and the comments in
`pxy.ts` and `ask.tsx` said "local"; all three now say hosted. Nothing in the
design changes, but the privacy claim was false and is gone.

### 1.1 New Chat mid-stream saves an empty conversation — reproduced

`reset()` in `chat-view.tsx` aborts the stream, nulls `conversationRef` and
commits `[]`. The stream's `finally` then runs anyway: it creates a
`newConversation(group)`, titles it `turnsRef.current[0]?.question ?? trimmed`
(the aborted question, since `turnsRef` is now empty) and saves it with zero
turns. **Reproduced on the desktop**: sent a question, pressed Ctrl+N two
seconds in, and the store gained `('write a very long story about ', 0)`, a
"0 messages" row at the top of Recent. Fix: in `finally`, skip the save when
`turnsRef.current.length === 0`, or when the aborted turn is no longer in
`turnsRef.current`.

That row is still in the history on this machine — it is the artefact of this
test, and the sqlite rewrite to remove it was blocked by the permission
classifier. Delete it from the Recent list (Ctrl+X) or leave it as a reminder.

### 1.2 Ask Again flashes the previous answer back — code-traced

In `ask.tsx`, `attempt++` reruns the effect: cleanup aborts the old controller,
the new effect calls `write()` with a fresh `base`. pi-ai turns the abort into
an `error` event with `reason: "aborted"`, which `ask()` swallows with a plain
`return`, so the OLD loop falls through to `flush()` **after** the loop. `dirty`
is almost always true (tokens landed since the last 50 ms tick), so `flush()`
calls the old closure's `write()` and overwrites the new turn's state with the
old accumulators. The comment above the `catch` says "unmounting aborts the
fetch; that rejection is this component going away" — but there is no
rejection; abort is a quiet return, so the guard never fires. Fix: `if
(controller.signal.aborted) return;` immediately after the `for await`, before
`flush()`. The chat's `patch()` is keyed by turn id so the same fall-through is
harmless there, except for §1.1.

### 1.3 The transcript pane does not follow a follow-up in a resumed chat — reproduced

Known from the last session as "a resumed long transcript opens at the top".
It is worse than that: **verified** today, resuming the 2-turn "name three
linux distros" conversation and asking a third question, the viewport showed
the first turn for the entire 26-second answer; the new question and its
answer streamed out of sight. The mechanism is in `MarkdownView.qml:310-321`
and `markdown-model.cpp:615`: the pane tail-follows only when the new markdown
is a strict prefix-extension of the old AND the view is already at the bottom.
A resume is a model reset (`contentY = 0`, `_autoScroll = false`), and every
later append finds the view not at the bottom, so nothing follows. There is no
scroll API an extension can call (checked TS, wire structs and QML).

The same rule bites our own rendering: `assistantMarkdown()` replaces
`**Thinking…** > reasoning` with `*Thought for 3.2s* answer` at the first
content token. That is not a prefix-extension, so the pane resets to the top
of the transcript on every turn. In a short chat it recovers because the
content still fits; in a long one it does not. Two fixes, both needed:

- **Render append-only.** Leave the quoted reasoning where it is and append
  the answer beneath it; put "Thought for 3.2s" on its own appended line
  rather than swapping it in. Never emit anything (a cursor, a spinner) that
  gets removed later.
- **A third vicinae patch**, `packages/vicinae-list-tail-follow.patch`
  (**landed, stage 1**): a `followTail` prop on `List` (same unknown-prop
  mechanism as `hideListPane`) that makes `MarkdownView` jump to the bottom
  on model reset and stay armed through every append. 52 lines across the
  wire struct, the QML model, `MarkdownView`, `MarkdownText` and
  `ExtensionView`. It also answers the tool-step lines in §2.5, which will
  not be prefix-only. Only `List` carries it: the one-shot `Detail` is a
  single turn and follows on its own. Trade-off accepted: while an answer
  streams, scrolling up to re-read is yanked back on the next append — the
  prop means "stick to the end", and the chat sends it whenever there is a
  transcript.

Related, from the survey: in `List.Item.Detail`, Up/Down move the list
selection, never the detail; only the root `Detail` binds arrow and page keys
to the flickable (`ExtensionView.qml:74-85`, `MarkdownView.qml:21-40`). With
`hideListPane` there is one row, so the chat transcript was wheel-only. The
same patch routes Up/Down to the detail's `scrollUp`/`scrollDown` when the
list pane is hidden (`GenericListView` exposes the loaded detail as
`detailItem`; the `DetailPanel` in `ExtensionView` gets the two functions).

The patch is named `list-…` on purpose: it builds on the full-width patch's
hunks, and `vicinae-rebuild` applies in glob order, so it has to sort after
`full-…`. Regenerating it means checking out the tag, applying the two
before it, committing that as a scratch commit, and `git diff HEAD`.

### 1.4 `stopReason: "length"` is silently a complete answer

pi-ai ends with `done { reason: "length" }` when the model hits `maxTokens`
(16384 nominal, but pi-ai clamps it to the context window minus the estimated
prompt minus 4096 — `api/simple-options.js:10`). Neither view looks at `done`,
so a truncated answer reads as finished. Cheap fix: yield a `{type: "done",
reason}` event from `ask()` and append `*(cut off at the token limit)*` when
it is `length`.

### 1.5 Not using pi-ai's power

- **No system prompt.** `Context.systemPrompt` is a plain string. Today's
  date would have saved the model a web search for "current date" during the
  tool prototype (§3.2); nemotron literally searched for it. Added in stage
  0, with a wording lesson: a bare `Today is Monday, September 14, 2026.` was
  twice "corrected" by hosted nemotron to a date in 2025 (its reasoning said
  "system date is provided as Wednesday, September 24, 2025") — a year past
  its training reads as a typo. `The current date is …. It comes from the
  system clock; trust it over anything you assume.` is obeyed, **verified**
  through Tab on the desktop; the Cloudflare hop got it right either way.
- **Usage is dropped.** pxy injects `stream_options.include_usage`, and the
  `done.message.usage` carries `input/output` counts (verified: 320/248 on
  the first tool round). Worth one accessory per turn once tools make turns
  expensive.
- **`onResponse` also carries `status`**; a 429 from an exhausted chain
  arrives as an error event with pxy's message, which is already surfaced.
  Fine as is.

### 1.6 Smaller things

- `toMessages()` drops a failed turn's assistant half but keeps the user half,
  so history can hold two consecutive user messages. ollama and the cloud
  chains accept it; some strict Anthropic-format upstreams do not. Merge them
  or drop the failed question too.
- `saveConversation` runs on *every* turn in `finally`, including when a
  resumed conversation is being streamed into while `reset()`/`resume()`
  swapped `conversationRef` underneath it. Rare; only the group and
  `updatedAt` are wrong.
- "Continue in Chat" pushed mid-stream carries a partial `turn`; the parent
  keeps streaming but the chat never sees the rest. Disable the action while
  `turn.answer` is empty or the stream is running.
- Password preferences are **cleartext** in `vicinae.db` on Linux
  (`encryptSensitiveData` defaults false, `config.hpp:307-311`; verified the
  db begins with `SQLite format 3`). Not a bug in our code, but it decides
  §2.7.

### 1.7 What was checked and is fine

- Unpatched machine: `hideListPane` is ignored (glaze `error_on_unknown_keys
  = false`, `model-deser.cpp:36`; reconciler forwards `rest`,
  `reconciler.ts:94-111`) and the chat falls back to the split view; without
  the Tab keybind the fallback is still reachable by arrowing. The fallback
  section is populated for **any** non-empty query
  (`root-search-model.cpp:139-147`), so Tab works even when apps match.
- `run_after_53-vicinae-build.sh` sorts before `run_after_53-vicinae-extensions.sh`;
  the launcher is rebuilt, then the extension, then restarted twice. Harmless.
- `has_patch` in `vicinae-rebuild` reads `hideListPane` from moc's string
  table, which is in the binary regardless of how the QML is packed. Correct.
- The extension runtime is node 24 with the full mise PATH (read from
  `/proc/<pid>/environ` of `extension-manager.js`), so spawning `qmd` or any
  shim works without special casing.
- `style="destructive"` on the Stop and Delete actions does nothing:
  `ActionModelWire` has no `style` field (`model-deser.cpp:145-154`). Harmless,
  but do not expect a red button.
- The 50 ms flush is the right order of magnitude for another reason found in
  the survey: every markdown update re-parses the whole document and re-runs
  syntax highlighting on every code block (`markdown-model.cpp:617`).

### 1.8 pxy: nothing broken, four observations

No correctness bug was found in pxy while probing it. For the record:

- **Hosted search is silent to chat-completions clients.** The progress
  marker is a chunk with empty `choices` (`router.rs`, the passthrough arm of
  `continue_after_search`), which the OpenAI SDK and pi-ai both skip. Only
  the Responses translator turns it into something visible. A design limit,
  not a bug; §2.3 works around it.
- **`max_uses` is unreachable from an OpenAI-format client.** `plan()` only
  recognises the Anthropic-shaped `web_search_*` tool, so a client that
  declares `pxy_web_search` directly always gets `DEFAULT_MAX_USES`.
- **`/v1/embeddings` answers 404 "model not found"** for any model because no
  provider has an `embeddings_url` (voyage is commented out). A config gap;
  the message could say "no embeddings provider configured".
- **Media endpoints forward an empty body upstream** and pass the upstream
  400 back. Correctly, a 4xx neither cools the provider nor walks the chain
  (`media/mod.rs:343-351`, `failed_attempt`), so it only costs one wasted
  request; `/v1/search` validates `query` locally and images/videos could do
  the same for `prompt`.

## 2. Design: capabilities

### 2.1 Decision: drive the tool loop ourselves on pi-ai

pi-agent-core was the alternative. What it gives: `AgentTool.execute`, TypeBox
argument validation, parallel/sequential batches, before/after hooks, steering
queues, compaction, skills, a proxy, durable sessions. What it costs: chord,
diff, ignore, yaml (~2 MB on top of what we have), a `streamSimple as unknown
as StreamFn` cast (the survey typechecked it; it is safe), and the `Agent`
class **drops `maxTokens`, `temperature`, `toolChoice` and a static `apiKey`**
(`agent.js:287` forwards a fixed list; the key must come through
`getApiKey`). To keep those you drop to `agentLoop`, at which point you are
holding a loop config, an event union that wraps pi-ai's, and a `convertToLlm`
you must supply.

The loop we need is the one in the prototype (§3.2): stream, collect
`toolCall` blocks from `done.message`, run them, push a `toolResult` per call,
stream again. Forty lines. **Neither package has any MCP code** — pi-coding-
agent's README says "No MCP" as a position; the only bridge is a third-party
extension pinned to prerelease tarballs — so adopting pi-agent-core buys
nothing for the feature Saiful actually asked for. Revisit if a third
capability needs the hooks or sequential-batch semantics; `agentLoop`, not
`Agent`, is the entry point then.

Facts that shape the loop (all from the installed 0.85.1, paths under
`node_modules/@earendil-works/pi-ai/dist/`):

- Tools go on `Context.tools`, not options. `Tool.parameters` is TypeBox
  `TSchema` but is **passed through untouched**
  (`api/constrained-sampling.js:111`), so a hand-written JSON Schema works
  with a cast — which is exactly what MCP's `inputSchema` is.
- Wire: standard function calling; tool results are `role: "tool"` with
  `tool_call_id`; empty output becomes the literal `(no tool output)`.
- Partial arguments stream: `toolcall_delta.delta` is the raw JSON fragment
  and `partial.content[i].arguments` is a repaired best-effort object. **But
  ollama sends the whole `arguments` in one chunk** (verified: one
  `toolcall_delta` carrying the complete JSON), so the streaming-args UI only
  matters on cloud hops. Design for it, do not depend on it.
- `done.reason` is `"toolUse"` when calls are pending, `"stop"` otherwise.
- `ToolResultMessage` needs `isError` and `timestamp`; content is text or
  image blocks (images become a following user message on the wire).

### 2.2 Where a capability lives

```
src/capabilities/
  index.ts        the registry: the list of capabilities, nothing else
  web.ts          web_search + fetch_url via pxy /v1/search and /v1/fetch
  mcp.ts          one function: an MCP server → a capability
  servers.ts      reads ~/.config/vicinae/ai-ask-mcp.json (§2.4)
src/lib/agent.ts  the loop: ask() grows into run(); tools in, steps out
```

A capability is a list of tools plus how to run them:

```ts
type Capability = {
  id: string;        // preference key, see §2.7
  title: string;
  tools(): Promise<AgentTool[]>;   // async: MCP has to connect first
  close?(): Promise<void>;
};
type AgentTool = Tool & {
  run(args: Record<string, unknown>, signal: AbortSignal): Promise<string>;
  /** One line for the transcript while it runs: `web_search "linux 7.2"` */
  label(args: Record<string, unknown>): string;
};
```

Adding a capability is one file exporting a `Capability`, one line in
`index.ts`, and one preference in `package.json`. The loop, the views and the
store do not change. An MCP server is not even a file: it is an entry in the
config (§2.4), turned into a `Capability` by `mcp.ts`.

Why `tools()` returns a promise: `qmd mcp` lists its tools only after the
stdio handshake, and it should not be spawned until the first message of a
conversation that has it enabled. Why the result is a string, not pi-ai's
content blocks: every source we have returns text (search results, fetched
markdown, MCP text content); image results are §2.6's problem and should not
leak into the chat loop's type until something produces one.

### 2.3 Web search: a client-side tool, not pxy's hosted one

pxy runs Anthropic's `web_search` server tool for upstreams that lack it. On
the plain chat-completions path the opt-in is **verified** (`router.rs:907`):
the client declares an ordinary function tool whose name is literally
`pxy_web_search`; pxy intercepts the model's calls to it, runs
`[[search.providers]]`, strips the calls from the stream, replays the request
with the results, and the answer continues inside the same response. Curl
with that tool on `general` gave `Monday, September 14, 2026 – newest stable
Linux kernel 7.2.4 – https://www.linuxlookup.com/linux_kernel` with two
searches served by brave in the pxy log.

It is not what the chat should use, for one reason that is enough on its own:
pxy signals "a search is happening" with a chunk shaped
`{"choices":[],"pxy_web_search":{id,query}}`, and pi-ai's parser does
`if (!choice) continue;` on every chunk with empty `choices`
(`api/openai-completions.js:381`). The search is invisible to us: the
reasoning stream stops for several seconds and the pane looks hung, the exact
failure the reasoning channel was adopted to prevent. Two smaller reasons:
the tool is dropped whenever the winning hop is an Anthropic-format upstream
(`router.rs:1015`), so search silently depends on which link of the chain
answered; and `max_uses` cannot be set from this path (`plan()` looks for the
Anthropic-shaped tool, so it is always the default 5).

So `web.ts` declares `web_search(query)` and `fetch_url(url)` and calls
`/v1/search` and `/v1/fetch` itself (**verified** end to end through the
prototype loop). Same providers, same quota accounting, and the step is a line
in the transcript. The cost is one extra round trip per search, which pxy's
continuation also pays; it just hides it.

The hosted path remains the right choice for the one-shot `ask` command if
search is ever wanted there: no loop, no second request from us, and Quick AI
is where latency matters most. Not proposed now.

### 2.4 MCP servers, and qmd as the worked example

Our own thin client over `@modelcontextprotocol/sdk` (v1, 1.30.0). The v2
split `@modelcontextprotocol/client` is newer but larger unpacked (6.6 MB vs
4.3 MB) and pulls zod 4; v1's stdio client is two imports. **Verified**: a
scratch node script connected to a stdio server in 121 ms, listed 14 tools,
called one, closed; and esbuild bundled the same script with `--bundle
--platform=node --format=cjs` (the options `vici build` uses,
`commands/build/index.js:95-108`) into a 608 KB file that runs. Only the
client and stdio transport reach the bundle; express and hono are
tree-shaken.

`mcp.ts` maps a server to a `Capability`: connect lazily on first `tools()`,
`listTools()` → one `AgentTool` per entry with `inputSchema` cast as
`parameters`, `run()` → `callTool()` with the text blocks joined, `close()` →
`client.close()`. Tool names are prefixed with the server id
(`qmd__query`) so two servers cannot collide and the transcript says which
one ran. The chat view closes every capability when it unmounts or on New
Chat; a server is a child process of the extension worker and dies with it.

Servers are data, not code, so they do not live in the TypeScript:

```jsonc
// ~/.config/vicinae/ai-ask-mcp.json — chezmoi-managed like overrides.json
{
  "qmd": {
    "command": "qmd", "args": ["mcp"],
    "title": "Local documents",
    "//": "stdio; keeps the ~2 GB of GGUF models loaded between calls"
  }
}
```

Why a file rather than a preference or a TS list: a per-machine list
(collections differ between the Mac mini and the laptop) that changes without
a rebuild, editable in the same place `overrides.json` is, and templatable by
chezmoi. Enabled-ness is still a preference (§2.7) so it shows in vicinae's
own settings.

**qmd** (`@tobilu/qmd`, node ≥ 22): BM25 + vectors + rerank over SQLite FTS5,
index at `~/.cache/qmd/index.sqlite`, three GGUF models it downloads on first
use (~2 GB). It exposes `query`, `get`, `multi_get`, `status` over stdio MCP,
and every CLI verb has `--json`. Two ways to plug it in, and the design allows
both without rework:

- **MCP (recommended).** `qmd mcp` stays resident, so the embedding and
  reranker models load once per conversation instead of once per call. This
  is the whole reason to prefer MCP over shelling out for this one.
- **CLI.** `qmd query -n 5 --json "<q>"` wrapped as a single `search_docs`
  tool in a `docs.ts`. Simpler schema for a small model — qmd's MCP
  `query` takes a `searches` array with typed entries, which nemotron-3-nano
  may fumble — but pays the model load on every call.

Start with MCP because it is the generic path; fall back to the CLI wrapper
only if nemotron cannot drive qmd's schema.

**Installed and wired later the same day** — collections, timer, install
script and what the corpus turned out to be are in docs/qmd-2026-09-14.md.

### 2.5 The UI while a tool runs

`Turn` gains `steps: Step[]` with `{id, name, label, status: "running" |
"done" | "error", ms, summary}`. Steps are written by the loop into the same
plain locals the deltas use and reach React through the same 50 ms flush, so
nothing new crosses the IPC bridge. In the transcript each step is a
blockquote line above the answer:

```
> ⏳ web_search "newest stable linux kernel"
> ✓ web_search "newest stable linux kernel" — 5 results, 1.2 s
> ✓ qmd__query "wayland compositor" — 3 hits, 0.4 s
```

Because a line changes from ⏳ to ✓, the markdown is not a prefix-extension
and the pane resets (§1.3). That is why the tail-follow patch is staged before
tools, not after. Per-turn `List.Item` accessories are also live during
streaming (`AccessoryWire`, `model-deser.cpp:90-95`) but the row is hidden by
`hideListPane`, so the transcript line is the only place a step can show.

Stop aborts the model stream **and** the running tool: `run(args, signal)`
receives the same signal, `fetch` honours it, and the MCP `callTool` takes it
through `RequestOptions.signal`. Tool errors are a `toolResult` with
`isError: true` and the message as content, so the model can recover;
the step shows ✗ and the error.

The one-shot `ask` command stays tool-free. It is the Tab path; a tool round
trip on the nemotron hop adds five to twenty seconds of reasoning before the
answer, and Quick AI's value is being instant. Assumption to confirm with
Saiful: tools are a chat feature.

### 2.6 Image and video generation: commands, not tools

`/v1/images/generations` **verified**: `{"prompt": …}` returned a base64 JPEG,
1024×1024, in 3.6 s from `cloudflare/@cf/black-forest-labs/flux-1-schnell`,
with `x-pxy-provider` set. Response is OpenAI-shaped `{created, data:
[{b64_json}]}` or `{url}` depending on the provider (`images.rs:normalize_json`).
`/v1/videos/generations` blocks while pxy polls the job, up to ~5 minutes
(`video.rs:19-20`), and returns `{data: [{url, format: "mp4"}]}`.

**`imagine`** — a `view` command with a `prompt` argument, rendered as a
`Grid`. Why Grid and not markdown in a `Detail`: markdown images are clamped
to 200 px tall unconditionally (`MdImage.qml:48`); Grid cells render at full
size. The image loader accepts `file://`, bare absolute paths, `data:` URIs
and `http(s)` (`url.cpp:150-215`), so the JPEG is written to
`environment.supportPath/images/<created>-<slug>.jpg` and the cell's `content`
is that path. The directory is the history: the Grid lists it newest first,
`columns={3}`, with `aspectRatio="1"`. The prompt goes in a sidecar
`<name>.json` (prompt, provider, created) because Grid items can carry no
accessory — `icon`, `accessory` and `detail` are declared in TS and dropped
by `GridItemViewModelWire` (`model-deser.cpp:361-370`) — so `title` is the
prompt and `subtitle` the provider. Progress is `isLoading` on the Grid plus
an Animated toast; the new cell appears when the file lands. Actions: Open
(default viewer), Show in file browser (works, D-Bus FileManager1), Copy
(`Clipboard.copy({file})`, a `text/uri-list` reference — pixels cannot be put
on the clipboard from an extension), Save to ~/Pictures, Regenerate, Copy
prompt.

**`video`** — same shape, `List` not Grid (no thumbnails without ffmpeg, and
no `Grid.Item.Detail` exists). Submit, Animated toast "Rendering…" with the
elapsed time in the *title* (the `message` setter does not re-send,
`toast.ts:104`), download the mp4 to `supportPath/videos/`, then Open with
mpv. The five-minute block is inside one `fetch`, abortable by leaving the
view.

Neither is a chat tool in this plan. A model that can call `generate_image`
is a nice demo, but the result is a file the chat cannot display well
(200 px), and the interesting knobs (size, steps, model) belong on a command
with a form, not in a tool schema a 30B model has to fill in. Cheap to add
later as a capability whose `run()` returns the path.

### 2.7 Preferences and secrets

- **Enable/disable** per capability is an extension-level `checkbox`
  preference named `cap.<id>` (default on for web, off for each MCP server).
  Vicinae also supports command-level preferences that override the
  extension's (`root-item-manager.cpp:456-465`), which is how `chat` could
  differ from `ask` later. One caveat from the source: a command-level
  preference with no stored value and no default emits null and clobbers the
  extension value, so every command-level preference must carry a `default`.
- **`getPreferenceValues()` is a launch-time snapshot** (`worker.tsx:90`).
  Changing a capability in settings takes effect on the next launch, which is
  fine; do not build a live toggle.
- **Secrets: none in the extension.** pxy is the secret store — brave,
  firecrawl, jina and every model key are `{ pass = "…" }` in its config —
  and the extension holds only `pxy-local`. A `password` preference would be
  the wrong place anyway: cleartext sqlite on Linux (§1.6). An MCP server
  that needs a key gets it through `env` in `ai-ask-mcp.json` with the same
  `{"pass": "AI/foo/main"}` convention pxy uses, resolved by `pass show` at
  spawn time. qmd needs none.
- **Model group** stays the dropdown it is; capabilities do not change it. If
  a tool-using turn should prefer a cloud chain (bigger models drive tools
  better), that is a second dropdown in the chat, not a preference.

## 3. What was prototyped, and what it proved

All scratch files are under the job's tmp directory and can be deleted;
nothing under `~/.dotfiles` changed except this document.

### 3.1 pxy hosted search from a chat-completions client

`curl -N` with a `pxy_web_search` function tool on `general`: two searches
served by brave, the marker chunks at lines 839 and 2275 of the stream, zero
`tool_calls` reaching the client, correct dated answer. Proves §2.3's opt-in
and, with the `if (!choice) continue;` read of pi-ai, why it is invisible.

### 3.2 The tool loop on pi-ai, against the nemotron hop

`tools.mjs`: `streamSimple` with `Context.tools = [web_search]`, run tool,
push `toolResult`, stream again. Round 1: 218 thinking deltas, one
`toolcall_start`, one `toolcall_delta` carrying the complete JSON, `done
toolUse`, usage 320/248. Round 2: answer with a URL, `done stop`. Proves the
loop, that nemotron-3-nano can drive a tool through pxy, and that ollama does
not stream partial arguments.

`replay.mjs`: an assistant message with a `toolCall` block and a `toolResult`
rehydrated from plain JSON (the LocalStorage shape, `NO_USAGE` and all), then
a follow-up asking about the tool's finding with tools disabled. Answer:
"The flag features a single white **hexagon**." Proves stored tool turns keep
their context the way `toContext()` already does for text turns, so §2.5's
`steps` can be persisted as-is.

### 3.3 MCP stdio client, and bundling it

`mcp.mjs`: `@modelcontextprotocol/sdk` client + `StdioClientTransport` against
the reference filesystem server. Connect 121 ms, 14 tools, `callTool` ok,
close. Bundled with esbuild's node/cjs settings to 608 KB and run from the
bundle. Proves the client fits `vici build` and the runtime.

### 3.4 Image generation

One request, one JPEG, 3.6 s, provider header present. Proves the response
shape and that the free Cloudflare model is the first hop.

## 4. Staged plan, smallest valuable first

| stage | what | why first |
|---|---|---|
| 0 | **Done 2026-09-14.** Fix §1.1, §1.2, §1.4; system prompt with the date; append-only rendering; hosted-ollama wording | each is a few lines and two are user-visible bugs |
| 1 | **Done 2026-09-14.** `packages/vicinae-list-tail-follow.patch` + arrow keys to the detail when the list pane is hidden | fixes §1.3 today and is a precondition for step lines |
| 2 | **Done 2026-09-14.** The loop in `ask()` + `capabilities/web.ts` + steps in the transcript + `webTools` preference | the first capability, and it proves the whole shape with no new dependency |
| 3 | **Done 2026-09-14** (client and config; qmd entry present, off). `capabilities/mcp.ts` + `servers.ts` + `ai-ask-mcp.json` | the generic path; the SDK is the only new dependency |
| 4 | **Done 2026-09-14.** `imagine` command | independent of 2 and 3; could go earlier if wanted |
| 5 | **Done 2026-09-14.** `video` command | least used; last |

Stage 0 is in the working tree and built: `Turn` gained `done` and `cutOff`,
`ask()` yields a `done` event, `assistantMarkdown` never rewrites what it
already emitted, the chat's `finally` skips the save when the turn was
swapped out, and the one-shot view returns before its post-loop flush on
abort. Verified on the desktop: New Chat two seconds into an answer adds no
row to the store; a fresh two-turn chat keeps following, with "Thinking…",
the quoted reasoning, "Thought for 1.1s", the answer and then the provider
line in that order; Tab on "what is today's date" answers with today's date.

Stage 1 is built and installed (`vicinae-rebuild --check`: "patch applied:
yes", three markers). Verified on the desktop: resuming the 3-turn distros
conversation opened at its last turn; a follow-up streamed into view with
its answer and provider line at the bottom; Up twice scrolled the transcript
to the earlier table. The chat sends `followTail` next to `hideListPane`.

Stage 2 is built and verified. What differs from §2.2 as drafted, and why:

- The loop lives in `ask()` in `pxy.ts` rather than a separate `agent.ts`:
  it is thirty lines that need `toContext` and the stream anyway. Types and
  the preference gate are in `src/lib/tools.ts`; the registry is
  `src/capabilities/index.ts`; the preference id is the capability id
  (`webTools`), a checkbox, default on.
- `run()` returns `{text, summary}`: the model gets `text`, the step line
  gets `summary` ("5 results via brave"). Tool errors go back to the model
  as a `toolResult` with `isError` and show on the line as ✗.
- **Tool calls are not replayed in later turns.** `Message` stays
  question/answer, so a follow-up does not resend every search result. §3.2
  proved replay works if ever wanted; it is not wanted by default.
- **A round cap with a forced answer.** Unbounded, nemotron did six searches
  and fetches and never answered (verified: `answer: ""`). `TOOL_ROUNDS = 4`,
  then one last call that has to be the answer. `toolChoice: "none"` was the
  polite way and is ignored by ollama.com's nemotron (verified:
  `tool_choice: "none"` on the wire, `done.reason` still `toolUse`). Dropping
  the tool declarations from that last request was the first fix and **was
  not enough** (found 2026-09-14 evening, after four "The model returned no
  answer." turns): with four tool calls in its context nemotron reasons its
  way to a fifth and emits it as a tool call anyway, the loop ran it and
  ended with no answer and no `done`. The last call now also sends
  `reasoning_effort: none` (pxy passes it through; pi-ai sends it when
  `supportsReasoningEffort` is on and `thinkingLevelMap.off` is a string, so
  `groupModel(group, reasoning)` toggles it per call) and a user message
  saying the tools are gone — without the thinking it cannot plan the call
  it is not offered, and it answers in one go. A system-prompt line ("answer
  as soon as you have enough; do not keep searching to confirm") brought the
  same question down to one search.
- Steps carry the reasoning that preceded them, so the transcript reads in
  arrival order while live: think, `✓ web_search "…" — 5 results via brave,
  1.3s`, think, "Thought for 6.4s", answer, provider. The step line's ⏳ → ✓
  rewrite is the one non-append; the stage 1 patch keeps the pane at the
  bottom through it. **Once the turn is done the reasoning folds** (also
  2026-09-14 evening): the "Thinking…" heading was a live indicator that
  stayed on finished turns, and the thinking is usually longer than the
  answer. A finished turn shows steps, "Thought for…", answer, provider;
  "Show Reasoning" (Ctrl+R, both views) unfolds it. cmark-gfm has no
  collapsible block, so the fold is a re-render, which is fine once the
  stream has ended. Stored turns have their reasoning stripped and nothing
  to unfold.

Verified on the desktop: "what is the newest stable linux kernel release
right now?" produced one `web_search` step and a one-line answer with the
kernel.org URL; the stored turn has the step and the answer.

Stage 3 is built and verified against the reference filesystem MCP server
(registered temporarily in the config, then removed). `@modelcontextprotocol/sdk`
1.30.0 is pinned exactly; the chat bundle grew from 185 KB to 471 KB. What
differs from §2.4 as drafted:

- **Tool names are `<id>__<tool>`** and the step line reads
  `files: list_directory {"path":…}` — the server id first, so a transcript
  says which server ran.
- **Enable/disable is `enabled` in the JSON**, not a preference: manifest
  preferences are static and shared by every machine, and the servers are
  not. Code capabilities keep their checkbox.
- **A server that cannot start is a toast, not a failed message**:
  `enabledTools()` catches per capability and sends the message with the
  tools that did come up. So the `qmd` entry can ship now, `enabled: false`,
  and flipping it before qmd is installed costs a toast per message rather
  than a broken chat.
- **No `{pass: …}` env resolution.** qmd needs no key; nothing else is
  configured. It is five lines when a server needs one.
- **Lifetime follows the view stack, not the window.** `pop_to_root_on_close`
  is false in the overrides, so Escape suspends the chat rather than
  unmounting it; the server stays warm and Alt+Space returns to the same
  conversation. When the stack is popped (Mod+Space, `bin/vicinae-launch`),
  vicinae calls the renderer's unmount and gives five seconds of grace
  (`WORKER_GRACE_PERIOD_MS`, `extension-manager/src/index.ts:16`); the chat's
  cleanup closes every capability and the child exits. **Verified**: the
  server's pid was alive after Escape and gone seven seconds after
  `vicinae://open?popToRoot=true`. Restarting vicinae also ends it, since the
  child belongs to the extension-manager process.

Three more things qmd taught the client the same evening: an optional
per-server `description` appended to every tool description (what the
server does not say about itself but the model needs — collection names,
"do not rerank"); a five-minute call timeout instead of the SDK's 60 s;
`resource` content blocks read as text (qmd's `get` answers with one); and
array/object arguments that arrive as JSON strings are parsed before the
call, because nemotron sends `"collections": "[\"mem\"]"` now and then.

The new file `home/dot_config/vicinae/ai-ask-mcp.json` is chezmoi-managed
like `overrides.json`; the symlink into `~/.config/vicinae/` was made by hand
here, exactly as `chezmoi apply` will make it elsewhere.

Stage 4 is built and verified: `src/imagine.tsx`, a third command
(`@saiful/ai-ask:imagine`, argument `prompt`). As designed in §2.6, with two
small choices made on the way: the file extension is sniffed from the bytes
(PNG magic, else jpg) because pxy's providers differ, and the record is a
sidecar `<name>.json` beside each image rather than any store — the
directory under `supportPath/images` is the history, and a stray file
without a sidecar still shows with its filename as the title. Enter in the
empty grid and in a populated one both generate; Copy Image puts a file
reference on the clipboard. **Verified**: "a small red teapot on a wooden
table" produced a 444 KB JPEG via Cloudflare flux in the grid within twelve
seconds, titled with the prompt and subtitled with the provider.

Stage 5 is built and verified: `src/video.tsx`, `@saiful/ai-ask:video`. As
designed: a List over `supportPath/videos` with sidecars, one blocking
request while pxy polls the job, the elapsed seconds ticking in the toast's
*title* (the message setter never re-sends), the mp4 downloaded beside its
record, Play through `Action.Open`. Leaving the view aborts the wait, not the
job — pxy keeps polling and the file just never lands. **Verified**: "a
paper boat drifting down a rain gutter" rendered via `agnes/agnes-video-v2.0`
in about 100 s, a 2 MB ISO Media mp4 in the list with Play as the default
action; the toast read "Rendering… 29s / 60s / 90s" on the way.

Every stage of the plan is now in the working tree. What is left is what §5
says not to build, plus qmd itself once installed.

Each stage is a rebuild (`npm ci && ./node_modules/.bin/vici build`, then
`systemctl --user restart vicinae`) and a check on the real desktop; stage 1
is a `vicinae-rebuild` (several minutes) and the `--check` line must read
"patch applied: yes" with a third marker added to `has_patch`.

## 5. Not building

- **pi-agent-core.** §2.1. Reconsider only when hooks or batch semantics are
  actually needed.
- **pxy's hosted search in the chat.** §2.3; invisible to pi-ai.
- **Image generation as a chat tool.** §2.6.
- **MCP over HTTP, OAuth, resources, prompts.** qmd's HTTP mode exists, but
  stdio is what a launcher-spawned child wants; nothing here needs the rest
  of the protocol.
- **Password preferences for API keys.** Cleartext on Linux; pxy holds keys.
- **Tools in the one-shot `ask`.** Latency; assumption flagged in §2.5.
- **Switching history from LocalStorage to `Cache`.** The survey found a real
  `Cache` (node fs under `supportPath/.cache`, sync, LRU) that would avoid an
  IPC round trip per read. Not worth a migration for 50 conversations.
- **Embeddings, transcription, speech, rerank.** pxy routes them
  (`/v1/embeddings` answers 404 only because no group named `auto` has an
  embedding model, not because the route is missing) but nothing in the
  launcher wants them yet.

## 6. Verified, and not

**Verified on this machine today:** the pxy search opt-in and its marker
chunk; the pi-ai tool loop, partial-argument behaviour on ollama, usage in
`done`; stored tool turns replaying; MCP stdio connect/list/call and the
esbuild bundle; image generation shape and latency; the empty-conversation
bug and its fix; the resumed-transcript no-follow bug; the append-only
rendering following a fresh multi-turn chat; the dated system prompt through
Tab; the tail-follow patch on a resumed chat and its arrow keys; the tool
loop in the chat with a real search, the round cap, and that hosted nemotron
ignores `tool_choice: "none"`; an MCP server called from the chat through
the bundled SDK, and its exit when the view stack pops; the imagine grid
end to end; one video render end to end; that
`ollama` is ollama.com; the runtime's PATH; every vicinae
claim above by file and line in `~/.local/src/vicinae` at v0.28.1 with both
patches applied.

**Not verified:** the Ask Again flash (§1.2, code-traced only, no UI
reproduction) (not
installed, MCP tool schema taken from its README); cloud hops streaming
partial tool arguments (only ollama was exercised); `Clipboard.copy({file})`
landing as a usable paste in another app.
