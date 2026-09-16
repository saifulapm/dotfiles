import { useEffect, useState } from "react";
import {
  Action,
  ActionPanel,
  Detail,
  Icon,
  Keyboard,
  type LaunchProps,
} from "@vicinae/api";
import { ask, model } from "./lib/pxy";
import { type Turn, assistantMarkdown, hasReasoning, newTurn } from "./lib/answer";
import { ChatView } from "./lib/chat-view";

// Tokens land roughly one per 10ms and every setState is a render pushed
// across vicinae's React-over-IPC bridge to the C++ side. Per-token state
// would be ~100 round trips a second for an answer nobody can read that fast,
// so deltas accumulate in plain locals and one update carries whatever
// arrived since the last tick. 50ms is still well past the eye's threshold
// for "streaming"; raise it before doing anything cleverer if it ever janks.
const FLUSH_MS = 50;

export default function Command(
  props: LaunchProps<{ arguments: Arguments.Ask }>,
) {
  // Two ways in. The one this command exists for is the fallback: the entire
  // root search arrives as fallbackText when Tab runs it (the ActivateFallback
  // keybind added by packages/vicinae-tab-fallback.patch). Launched by name
  // instead, the question comes from the argument field.
  const question = (props.arguments?.question || props.fallbackText || "").trim();
  const group = model();
  const [attempt, setAttempt] = useState(0);
  const [showReasoning, setShowReasoning] = useState(false);
  const [turn, setTurn] = useState<Turn>(() => newTurn(question));

  useEffect(() => {
    if (!question) return;

    const controller = new AbortController();
    const base = newTurn(question);
    let answer = "";
    let reasoning = "";
    let thoughtMs: number | null = null;
    let provider: string | null = null;
    let cutOff = false;
    let dirty = false;

    // Always rebuilt from `base` plus the current accumulators, so there is
    // one place a turn is assembled and no partial update can disagree.
    const write = (fields: Partial<Turn> = {}) =>
      setTurn({ ...base, answer, reasoning, thoughtMs, provider, cutOff, ...fields });
    const flush = () => {
      if (!dirty) return;
      dirty = false;
      write();
    };
    const timer = setInterval(flush, FLUSH_MS);
    const startedAt = Date.now();

    write();

    void (async () => {
      try {
        for await (const event of ask(
          [{ role: "user", content: question }],
          group,
          controller.signal,
        )) {
          // VERIFIED against the default `aaa` group (hosted ollama,
          // nemotron-3-nano): it reasons for several seconds before the first
          // word of the answer — a blank pane if only content is read. That is
          // why reasoning is its own channel rather than something to skip.
          if (event.type === "provider") {
            provider = event.provider;
            write();
            continue;
          }
          if (event.type === "done") {
            cutOff = event.reason === "length";
            continue;
          }
          // No tools are passed, so no step ever arrives.
          if (event.type === "step") continue;
          if (event.type === "reasoning") {
            reasoning += event.delta;
          } else {
            if (thoughtMs === null && reasoning) thoughtMs = Date.now() - startedAt;
            answer += event.delta;
          }
          dirty = true;
        }
        // An abort ends the generator quietly, not with a throw. It is
        // either this view going away or "Ask Again" starting a fresh
        // stream — and in the second case a flush here would write this
        // effect's stale accumulators over the new turn's state.
        if (controller.signal.aborted) return;
        // The last tick may have missed the final few deltas. `done` is
        // written with them so the provider line and the cutoff note appear
        // together with the final text rather than a tick later.
        dirty = false;
        write({ done: true });
        // A stream that ends having emitted reasoning but never a content
        // token — or nothing at all — would otherwise leave "Thinking…" on
        // screen for good, which claims something is still happening.
        if (!answer) {
          write({ done: true, error: "The model returned no answer." });
        }
      } catch (thrown) {
        if (controller.signal.aborted) return;
        // Keep whatever streamed before it broke — a truncated answer plus the
        // reason it stopped beats replacing it with the error alone.
        write({ done: true, error: thrown instanceof Error ? thrown.message : String(thrown) });
      } finally {
        clearInterval(timer);
      }
    })();

    return () => {
      controller.abort();
      clearInterval(timer);
    };
  }, [question, group, attempt]);

  return (
    <Detail
      navigationTitle={question ? truncate(question, 64) : "Ask AI"}
      markdown={render(question, group, turn, showReasoning)}
      actions={
        <ActionPanel>
          {turn.answer ? (
            <>
              <Action.CopyToClipboard
                title="Copy Answer"
                content={turn.answer}
                shortcut={Keyboard.Shortcut.Common.Copy}
              />
              <Action.Paste
                title="Paste Answer"
                content={turn.answer}
                shortcut={{ key: "v", modifiers: ["cmd", "shift"] }}
              />
            </>
          ) : null}
          {question ? (
            // The finished turn goes with it, so the follow-up has the context
            // rather than re-asking the model what it just answered.
            <Action.Push
              title="Continue in Chat"
              icon={Icon.SpeechBubble}
              shortcut={{ key: "j", modifiers: ["cmd"] }}
              target={<ChatView initialTurns={[turn]} initialModel={group} />}
            />
          ) : null}
          {hasReasoning([turn]) ? (
            <Action
              title={showReasoning ? "Hide Reasoning" : "Show Reasoning"}
              icon={Icon.Eye}
              shortcut={{ key: "r", modifiers: ["cmd"] }}
              onAction={() => setShowReasoning((on) => !on)}
            />
          ) : null}
          {question ? (
            <Action
              title="Ask Again"
              icon={Icon.ArrowClockwise}
              shortcut={Keyboard.Shortcut.Common.Refresh}
              onAction={() => setAttempt((n) => n + 1)}
            />
          ) : null}
        </ActionPanel>
      }
    />
  );
}

function render(question: string, group: string, turn: Turn, showReasoning: boolean): string {
  if (!question) {
    return [
      "# Ask AI",
      "",
      "Type a question in the root search and press `Tab`, or launch this command and type it in the argument field.",
    ].join("\n");
  }

  // The provider is the point of surfacing this at all: `aaa` is a
  // failover chain, and whether the answer came from ollama.com or a cloud
  // provider several links down the chain is not otherwise visible.
  const head = `\`${turn.provider ? `${group} · ${turn.provider}` : group}\``;

  if (turn.error) {
    return [
      head,
      "",
      "## Could not answer",
      "",
      turn.error,
      "",
      "Check `systemctl --user status pxy` and `curl localhost:4100/healthz`.",
      ...(turn.answer ? ["", "---", "", turn.answer] : []),
    ].join("\n");
  }

  return [head, "", assistantMarkdown(turn, showReasoning)].join("\n");
}

function truncate(text: string, max: number): string {
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}
