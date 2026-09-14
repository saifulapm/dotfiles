import type { Message } from "./pxy";
import type { Step } from "./tools";

/** One exchange: what was asked, and everything that came back for it. Both
 *  commands stream into this same shape — the one-shot view just never has
 *  more than one of them. */
export type Turn = {
  id: string;
  question: string;
  answer: string;
  reasoning: string;
  /** Which provider in the group's chain served this turn. Per turn, not per
   *  conversation: a failover can move mid-chat and the answer that came from
   *  a cloud model should say so. */
  provider: string | null;
  /** Milliseconds of reasoning before the first content token, once there has
   *  been one. Null while still thinking, and for models that don't reason. */
  thoughtMs: number | null;
  error: string | null;
  /** Tool calls in the order they happened, each carrying the reasoning
   *  that led to it. `reasoning` below is what came after the last one. */
  steps: Step[];
  /** The stream has ended, one way or another. Rendering waits for this
   *  before adding anything below the answer (see assistantMarkdown). */
  done: boolean;
  /** Ended on the token cap rather than a full stop. */
  cutOff: boolean;
};

export function newTurn(question: string): Turn {
  return {
    // Date.now() alone collides when a turn is retried inside the same
    // millisecond, and the id is what React keys rows by.
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    question,
    answer: "",
    reasoning: "",
    provider: null,
    thoughtMs: null,
    error: null,
    steps: [],
    done: false,
    cutOff: false,
  };
}

/** The turns so far as pxy wants them. Turns that failed are dropped rather
 *  than sent as an empty assistant message, which some models treat as a hint
 *  to keep being empty. */
export function toMessages(turns: Turn[]): Message[] {
  return turns.flatMap((turn) =>
    turn.answer
      ? [
          { role: "user" as const, content: turn.question },
          { role: "assistant" as const, content: turn.answer },
        ]
      : [{ role: "user" as const, content: turn.question }],
  );
}

/** The assistant's half of a turn.
 *
 *  APPEND-ONLY while the turn is live. The detail pane tail-follows a stream
 *  only when each new markdown is the previous one plus more text
 *  (MarkdownView.qml checks `startsWith`); anything else is a model reset
 *  that jumps to the top and stops following — which is what happened when
 *  this used to swap "Thinking…" for "Thought for 3.2s" at the first word.
 *  So the reasoning stays where it streamed and the answer goes beneath it,
 *  and nothing is added above or between until the stream has ended.
 *
 *  Once the turn is done the reasoning folds away: the answer is what was
 *  asked for, and the thinking above it — often longer than the answer — is
 *  scratch work that only matters when the answer is wrong. `showReasoning`
 *  unfolds it (an action in both views); vicinae's markdown is cmark-gfm
 *  with no collapsible block, so folding is a re-render, not a widget. The
 *  "Thinking…" heading is a live indicator only: on a finished turn it would
 *  claim something is still happening. A stored turn comes back with its
 *  reasoning stripped (store.ts) and has nothing to unfold.
 *
 *  The one exception to append-only is a step line changing from running to
 *  finished. That is a reset, and packages/vicinae-list-tail-follow.patch is
 *  what keeps the pane at the bottom through it. */
export function assistantMarkdown(turn: Turn, showReasoning = false): string {
  const parts: string[] = [];
  const reasoningShown = !turn.done || showReasoning;
  if (!turn.done) parts.push("**Thinking…**");
  for (const step of turn.steps) {
    // All of the reasoning, not a tail: the newest thought is on screen and
    // the earlier ones are still there to scroll back to.
    if (step.reasoning && reasoningShown) parts.push(quote(step.reasoning));
    parts.push(quote(stepLine(step)));
  }
  if (turn.reasoning && reasoningShown) parts.push(quote(turn.reasoning));
  if (turn.thoughtMs !== null && turn.answer) {
    parts.push(`*Thought for ${(turn.thoughtMs / 1000).toFixed(1)}s*`);
  }
  if (turn.answer) parts.push(turn.answer);
  if (turn.cutOff) parts.push("*Cut off at the token limit.*");
  return parts.join("\n\n");
}

/** Whether there is any reasoning to unfold — false for stored turns. */
export function hasReasoning(turns: Turn[]): boolean {
  return turns.some((t) => t.reasoning || t.steps.some((s) => s.reasoning));
}

function stepLine(step: Step): string {
  const mark = step.status === "running" ? "⏳" : step.status === "done" ? "✓" : "✗";
  const tail = step.status === "running" ? "" : ` — ${step.summary}, ${(step.ms / 1000).toFixed(1)}s`;
  return `${mark} \`${step.label}\`${tail}`;
}

/** Blockquote is the only "dim" markdown has, and it is per-line — a raw
 *  multi-line paste would end the quote at the first blank line. */
export function quote(text: string): string {
  return text
    .split("\n")
    .map((line) => `> ${line}`)
    .join("\n");
}
