import { useCallback, useEffect, useRef, useState } from "react";
import { Action, ActionPanel, Icon, Keyboard, List } from "@vicinae/api";
import { GROUPS, ask, model } from "./pxy";
import { type Step, closeTools, enabledTools } from "./tools";
import { type Turn, assistantMarkdown, hasReasoning, newTurn, quote, toMessages } from "./answer";
import {
  type Conversation,
  deleteConversation,
  listConversations,
  newConversation,
  saveConversation,
} from "./store";

// Same reason as the one-shot view: tokens arrive faster than anyone reads and
// every setState is a render pushed across vicinae's React-over-IPC bridge.
const FLUSH_MS = 50;

type Props = {
  /** Turns carried in from the one-shot answer by "Continue in Chat", or from
   *  a conversation being resumed. */
  initialTurns?: Turn[];
  /** Asked immediately on open — the argument the command was launched with. */
  initialQuestion?: string;
  initialModel?: string;
};

export function ChatView({ initialTurns, initialQuestion, initialModel }: Props) {
  const [input, setInput] = useState("");
  const [group, setGroup] = useState(initialModel ?? model());
  const [turns, setTurns] = useState<Turn[]>(initialTurns ?? []);
  const [pending, setPending] = useState(false);
  const [showReasoning, setShowReasoning] = useState(false);
  const [history, setHistory] = useState<Conversation[]>([]);

  // The stream writes turns from inside an async loop that outlives the render
  // it started in, so it cannot read them from state without seeing whatever
  // they were when its closure was made.
  const turnsRef = useRef<Turn[]>(turns);
  const conversationRef = useRef<Conversation | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  const commit = useCallback((next: Turn[]) => {
    turnsRef.current = next;
    setTurns(next);
  }, []);

  const send = useCallback(
    async (question: string, group: string) => {
      const trimmed = question.trim();
      // One request at a time: a second stream would interleave its tokens
      // with the first one's into a different turn and double the cost of a
      // mistyped Enter.
      if (!trimmed || abortRef.current) return;

      const turn = newTurn(trimmed);
      const history = toMessages(turnsRef.current);
      commit([...turnsRef.current, turn]);
      setInput("");
      setPending(true);

      const controller = new AbortController();
      abortRef.current = controller;

      let answer = "";
      let reasoning = "";
      let thoughtMs: number | null = null;
      let cutOff = false;
      let steps: Step[] = [];
      let dirty = false;

      const patch = (fields: Partial<Turn>) =>
        commit(turnsRef.current.map((t) => (t.id === turn.id ? { ...t, ...fields } : t)));
      const flush = () => {
        if (!dirty) return;
        dirty = false;
        patch({ answer, reasoning, thoughtMs, steps });
      };
      const timer = setInterval(flush, FLUSH_MS);
      const startedAt = Date.now();

      try {
        // Tools are the chat's, not the one-shot command's: a round of tool
        // use on the nemotron hop is five to twenty seconds of reasoning
        // before the answer, and Quick AI's whole point is being instant.
        const tools = await enabledTools();
        for await (const event of ask(
          [...history, { role: "user", content: trimmed }],
          group,
          controller.signal,
          tools,
        )) {
          // The default group reasons for several seconds before the first
          // word — see the comment in ask.tsx. Reasoning is a separate channel
          // so that wait is visible rather than looking hung.
          if (event.type === "provider") {
            patch({ provider: event.provider });
            continue;
          }
          if (event.type === "done") {
            cutOff = event.reason === "length";
            continue;
          }
          if (event.type === "step") {
            const known = steps.findIndex((s) => s.id === event.step.id);
            if (known === -1) {
              // The reasoning so far led to this call; it moves onto the
              // step so what the model thinks afterwards starts fresh below.
              steps = [...steps, { ...event.step, reasoning }];
              reasoning = "";
            } else {
              steps = steps.map((s, i) => (i === known ? { ...event.step, reasoning: s.reasoning } : s));
            }
            dirty = true;
            continue;
          }
          if (event.type === "reasoning") {
            reasoning += event.delta;
          } else {
            if (thoughtMs === null && reasoning) thoughtMs = Date.now() - startedAt;
            answer += event.delta;
          }
          dirty = true;
        }
        flush();
        // Stop aborts the stream, which ends this loop quietly — that is the
        // user cutting an answer short, not the model failing to give one.
        if (!answer && !controller.signal.aborted) {
          patch({ error: "The model returned no answer." });
        }
      } catch (thrown) {
        flush();
        // Stop, and closing the view, both abort. Neither is a failure worth
        // writing into the transcript — the partial answer already flushed is
        // the whole story.
        if (!controller.signal.aborted) {
          patch({ error: thrown instanceof Error ? thrown.message : String(thrown) });
        }
      } finally {
        clearInterval(timer);
        patch({ done: true, cutOff });
        abortRef.current = null;
        setPending(false);

        // New Chat (or Resume) mid-stream aborts this and swaps the turns out
        // from under it. Saving then would file an empty conversation titled
        // with the abandoned question — a "0 messages" row in Recent.
        if (!turnsRef.current.some((t) => t.id === turn.id)) return;

        const conversation = conversationRef.current ?? newConversation(group);
        conversationRef.current = conversation;
        await saveConversation({
          ...conversation,
          title: turnsRef.current[0]?.question ?? trimmed,
          model: group,
          updatedAt: Date.now(),
          turns: turnsRef.current,
        });
      }
    },
    [commit],
  );

  // Only when there is nothing to show instead: the history list is the empty
  // state of this view, not a panel competing with a live conversation.
  useEffect(() => {
    if (turns.length === 0 && !pending) void listConversations().then(setHistory);
  }, [turns.length, pending]);

  const started = useRef(false);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    if (initialQuestion?.trim()) void send(initialQuestion, group);
  }, [initialQuestion, group, send]);

  // Closing the view mid-answer should stop paying for it, and an MCP
  // server spawned for this chat has nothing left to do.
  useEffect(
    () => () => {
      abortRef.current?.abort();
      void closeTools();
    },
    [],
  );

  const resume = (conversation: Conversation) => {
    conversationRef.current = conversation;
    setGroup(conversation.model);
    // `done` and `steps` arrived after the first conversations were saved; a
    // stored turn is finished by definition.
    commit(conversation.turns.map((t) => ({ ...t, done: true, steps: t.steps ?? [] })));
  };

  const reset = () => {
    abortRef.current?.abort();
    conversationRef.current = null;
    commit([]);
    setInput("");
  };

  // One row for the whole conversation, and the patch below hides it: the
  // transcript is the content, and a column of question rows beside it only
  // repeated what it already says. The row still exists because selection is
  // what owns the action panel — Enter has to have something to fire.
  const transcript = turns.map((turn) => exchange(turn, showReasoning)).join("\n\n---\n\n");

  // Enter sends whenever something is typed, wherever the selection sits —
  // the search bar is the composer, so it has to behave like one.
  const actions = (turn?: Turn) => (
    <ActionPanel>
      {input.trim() ? (
        <Action title="Send" icon={Icon.ArrowUp} onAction={() => void send(input, group)} />
      ) : null}
      {pending ? (
        <Action
          title="Stop"
          icon={Icon.Stop}
          style="destructive"
          onAction={() => abortRef.current?.abort()}
        />
      ) : null}
      {turn?.answer ? (
        <Action.CopyToClipboard
          title="Copy Answer"
          content={turn.answer}
          shortcut={Keyboard.Shortcut.Common.Copy}
        />
      ) : null}
      {turn?.answer ? (
        <Action.Paste
          title="Paste Answer"
          content={turn.answer}
          shortcut={{ key: "v", modifiers: ["cmd", "shift"] }}
        />
      ) : null}
      {hasReasoning(turns) ? (
        <Action
          title={showReasoning ? "Hide Reasoning" : "Show Reasoning"}
          icon={Icon.Eye}
          shortcut={{ key: "r", modifiers: ["cmd"] }}
          onAction={() => setShowReasoning((on) => !on)}
        />
      ) : null}
      {turns.length > 1 ? (
        // With the per-turn rows gone this is the only way to get at an answer
        // that is not the latest one.
        <Action.CopyToClipboard
          title="Copy Conversation"
          content={transcript}
          shortcut={{ key: "c", modifiers: ["cmd", "shift"] }}
        />
      ) : null}
      {turns.length ? (
        <Action
          title="New Chat"
          icon={Icon.Plus}
          shortcut={{ key: "n", modifiers: ["cmd"] }}
          onAction={reset}
        />
      ) : null}
    </ActionPanel>
  );

  return (
    <List
      {...fullWidthDetail(turns.length > 0)}
      searchText={input}
      onSearchTextChange={setInput}
      // The rows are the conversation, not search results — fuzzy-filtering
      // them against the question being typed would hide the transcript the
      // moment anyone started composing.
      filtering={false}
      isLoading={pending}
      isShowingDetail={turns.length > 0}
      searchBarPlaceholder={turns.length ? "Ask a follow-up…" : "Ask anything"}
      searchBarAccessory={
        <List.Dropdown tooltip="Model" value={group} onChange={setGroup}>
          {GROUPS.map((g) => (
            <List.Dropdown.Item key={g.value} title={g.title} value={g.value} />
          ))}
        </List.Dropdown>
      }
    >
      {turns.length > 0 ? (
        <List.Item
          id="transcript"
          // Never seen: the list pane this sits in is collapsed. It is the
          // carrier for the detail and the action panel, nothing more.
          title="Conversation"
          detail={<List.Item.Detail markdown={transcript} />}
          actions={actions(turns[turns.length - 1])}
        />
      ) : input.trim() ? (
        // Nothing to list yet, but something is typed: the empty view carries
        // the action Enter fires, since there is no row to hang it on.
        <List.EmptyView
          icon={Icon.Stars}
          title={`Ask “${input.trim()}”`}
          description="Press Enter to start the conversation."
          actions={actions()}
        />
      ) : history.length > 0 ? (
        <List.Section title="Recent">
          {history.map((conversation) => (
            <List.Item
              key={conversation.id}
              id={conversation.id}
              title={conversation.title || "Untitled"}
              subtitle={`${conversation.turns.length} message${conversation.turns.length === 1 ? "" : "s"}`}
              icon={Icon.SpeechBubble}
              accessories={[{ text: conversation.model }]}
              actions={
                <ActionPanel>
                  <Action
                    title="Resume"
                    icon={Icon.ArrowRight}
                    onAction={() => resume(conversation)}
                  />
                  <Action
                    title="Delete"
                    icon={Icon.Trash}
                    style="destructive"
                    shortcut={Keyboard.Shortcut.Common.Remove}
                    onAction={() =>
                      void deleteConversation(conversation.id).then(() =>
                        listConversations().then(setHistory),
                      )
                    }
                  />
                </ActionPanel>
              }
            />
          ))}
        </List.Section>
      ) : (
        <List.EmptyView
          icon={Icon.Stars}
          title="Ask anything"
          description="Type a question and press Enter. Follow-ups stay in this conversation."
        />
      )}
    </List>
  );
}

/** Two props of ours, from packages/vicinae-full-width-detail.patch and
 *  packages/vicinae-list-tail-follow.patch: `hideListPane` collapses the item
 *  list so the detail gets the whole card; `followTail` keeps that detail
 *  scrolled to its end — a resumed transcript opens at its last turn instead
 *  of its first, and a follow-up streams into view. @vicinae/api is the stock
 *  published package and does not declare either — and `List.Props` is a type
 *  alias, so it cannot be augmented — hence the spread.
 *
 *  Safe on a machine whose vicinae is not patched yet (mid-apply, or the
 *  packaged build): the extension reconciler forwards the props verbatim and
 *  the server parses with `error_on_unknown_keys = false`, so they are ignored
 *  and the chat falls back to the ordinary split view that opens at the top. */
function fullWidthDetail(enabled: boolean): Record<string, unknown> {
  return { hideListPane: enabled, followTail: enabled };
}

/** One exchange in the transcript. The question is quoted so a multi-line
 *  paste stays visually attached to the "You" label. */
function exchange(turn: Turn, showReasoning: boolean): string {
  const parts = [quote(`**You** — ${turn.question}`), "", assistantMarkdown(turn, showReasoning)];
  if (turn.error) parts.push("", `**${turn.error}**`);
  // Last, and only once the turn is over: the provider is known before the
  // first token, and a line inserted above a streaming answer is not an
  // append — the pane would reset to the top (see assistantMarkdown).
  if (turn.done && turn.provider) parts.push("", `\`${turn.provider}\``);
  return parts.join("\n");
}
