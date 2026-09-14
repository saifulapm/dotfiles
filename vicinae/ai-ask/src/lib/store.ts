import { LocalStorage } from "@vicinae/api";
import type { Turn } from "./answer";

export type Conversation = {
  id: string;
  /** First question asked, which is what the history list shows. Kept on the
   *  record rather than derived, so renaming one later stays possible. */
  title: string;
  model: string;
  updatedAt: number;
  turns: Turn[];
};

const KEY = "conversations";

// Far more than anyone scrolls back through, and the list is rewritten whole
// after every answer — an unbounded one would make each turn slower than the
// last.
const CAP = 50;

async function read(): Promise<Conversation[]> {
  const raw = await LocalStorage.getItem<string>(KEY);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as Conversation[]) : [];
  } catch {
    // Storage is inspectable and editable from vicinae's own Local Storage
    // command, so malformed JSON is reachable. No history beats a command
    // that will not open.
    return [];
  }
}

/** Newest first — the one you were just in is the one you want back. */
export async function listConversations(): Promise<Conversation[]> {
  return (await read()).sort((a, b) => b.updatedAt - a.updatedAt);
}

export async function saveConversation(conversation: Conversation): Promise<void> {
  // Reasoning is scratch work: hundreds of tokens per turn that nothing reads
  // back and that the model is not sent again. Dropping it keeps a long
  // history from dwarfing everything else in LocalStorage.
  const turns = conversation.turns.map((turn) => ({
    ...turn,
    reasoning: "",
    steps: turn.steps.map((step) => ({ ...step, reasoning: "" })),
  }));
  const others = (await read()).filter((c) => c.id !== conversation.id);
  const next = [{ ...conversation, turns }, ...others]
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, CAP);
  await LocalStorage.setItem(KEY, JSON.stringify(next));
}

export async function deleteConversation(id: string): Promise<void> {
  const next = (await read()).filter((c) => c.id !== id);
  await LocalStorage.setItem(KEY, JSON.stringify(next));
}

export function newConversation(model: string, turns: Turn[] = []): Conversation {
  return {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    title: turns[0]?.question ?? "",
    model,
    updatedAt: Date.now(),
    turns,
  };
}
