import { useEffect, useRef, useState } from "react";
import { mkdir, readFile, readdir, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  Action,
  ActionPanel,
  Icon,
  Keyboard,
  type LaunchProps,
  List,
  Toast,
  environment,
  showToast,
} from "@vicinae/api";
import { ENDPOINT, TOKEN } from "./lib/pxy";

// Generated videos through pxy's /v1/videos/generations. pxy submits the job
// and polls it itself — every 3 s, up to ~5 minutes (media/video.rs) — so
// from here it is one long request that answers with a URL, downloaded to
// the extension's support directory beside a sidecar record, exactly as
// imagine.tsx keeps its images. A List rather than a Grid: there is no
// thumbnail without a decoder, and Grid.Item.Detail does not exist.
const DIR = join(environment.supportPath, "videos");

type Generated = {
  file: string;
  prompt: string;
  provider: string;
  created: number;
};

export default function Command(props: LaunchProps<{ arguments: Arguments.Video }>) {
  const [input, setInput] = useState("");
  const [items, setItems] = useState<Generated[]>([]);
  const [pending, setPending] = useState<string | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const started = useRef(false);

  const refresh = () => void list().then(setItems);

  const generate = async (prompt: string) => {
    const trimmed = prompt.trim();
    if (!trimmed || abortRef.current) return;
    const controller = new AbortController();
    abortRef.current = controller;
    setPending(trimmed);
    setInput("");
    const startedAt = Date.now();
    const toast = await showToast({ style: Toast.Style.Animated, title: "Rendering… 0s", message: trimmed });
    // The elapsed time goes in the title: setting only a toast's message
    // never reaches the server (toast.ts, the message setter does not
    // re-send), and a render is minutes of nothing otherwise.
    const ticker = setInterval(() => {
      toast.title = `Rendering… ${Math.round((Date.now() - startedAt) / 1000)}s`;
    }, 1000);
    try {
      const made = await create(trimmed, controller.signal);
      toast.style = Toast.Style.Success;
      toast.title = `Rendered via ${made.provider} in ${Math.round((Date.now() - startedAt) / 1000)}s`;
      refresh();
    } catch (thrown) {
      if (controller.signal.aborted) return;
      toast.style = Toast.Style.Failure;
      toast.title = "Could not render";
      toast.message = thrown instanceof Error ? thrown.message : String(thrown);
    } finally {
      clearInterval(ticker);
      abortRef.current = null;
      setPending(null);
    }
  };

  useEffect(refresh, []);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    const prompt = props.arguments?.prompt?.trim();
    if (prompt) void generate(prompt);
  }, []);
  // Leaving the view abandons the wait, not the job: pxy keeps polling on
  // its own, and the file simply never lands here.
  useEffect(() => () => abortRef.current?.abort(), []);

  const remove = async (item: Generated) => {
    await Promise.all([unlink(item.file), unlink(sidecar(item.file))]);
    refresh();
  };

  const composer = input.trim() ? (
    <Action title="Render" icon={Icon.Video} onAction={() => void generate(input)} />
  ) : null;

  return (
    <List
      searchText={input}
      onSearchTextChange={setInput}
      filtering={false}
      isLoading={pending !== null}
      searchBarPlaceholder="Describe a video and press Enter (takes minutes)"
      navigationTitle="Video"
    >
      {items.length === 0 ? (
        <List.EmptyView
          icon={Icon.Video}
          title={input.trim() ? `Render “${input.trim()}”` : "Describe a video"}
          description={pending ? `Rendering “${pending}”…` : "Press Enter. Renders take minutes and are kept here until deleted."}
          actions={<ActionPanel>{composer}</ActionPanel>}
        />
      ) : (
        items.map((item) => (
          <List.Item
            key={item.file}
            id={item.file}
            icon={Icon.Video}
            title={item.prompt}
            subtitle={item.provider}
            accessories={[{ text: item.created ? new Date(item.created).toLocaleString() : "" }]}
            actions={
              <ActionPanel>
                {composer}
                <Action.Open title="Play" target={item.file} icon={Icon.Play} />
                <Action.ShowInFinder path={item.file} />
                <Action
                  title="Render Again"
                  icon={Icon.ArrowClockwise}
                  shortcut={Keyboard.Shortcut.Common.Refresh}
                  onAction={() => void generate(item.prompt)}
                />
                <Action.CopyToClipboard
                  title="Copy Prompt"
                  content={item.prompt}
                  shortcut={{ key: "c", modifiers: ["cmd", "shift"] }}
                />
                <Action
                  title="Delete"
                  icon={Icon.Trash}
                  style="destructive"
                  shortcut={Keyboard.Shortcut.Common.Remove}
                  onAction={() => void remove(item)}
                />
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
}

const sidecar = (file: string) => file.replace(/\.mp4$/, ".json");

async function list(): Promise<Generated[]> {
  await mkdir(DIR, { recursive: true });
  const names = (await readdir(DIR)).filter((n) => n.endsWith(".mp4"));
  const items = await Promise.all(
    names.map(async (name): Promise<Generated> => {
      const file = join(DIR, name);
      try {
        const meta = JSON.parse(await readFile(sidecar(file), "utf8"));
        return { file, prompt: meta.prompt, provider: meta.provider, created: meta.created };
      } catch {
        return { file, prompt: name, provider: "", created: 0 };
      }
    }),
  );
  return items.sort((a, b) => b.created - a.created);
}

async function create(prompt: string, signal: AbortSignal): Promise<Generated> {
  const response = await fetch(`${ENDPOINT}/videos/generations`, {
    method: "POST",
    headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ prompt }),
    signal,
  });
  const json: any = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(json?.error?.message || json?.message || `pxy answered ${response.status}`);
  }
  const url = json.data?.[0]?.url;
  if (!url) throw new Error("no video url in the response");
  const bytes = Buffer.from(await (await fetch(url, { signal })).arrayBuffer());
  const created = Date.now();
  const slug = prompt.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
  const file = join(DIR, `${created}-${slug}.mp4`);
  const provider = response.headers.get("x-pxy-provider") ?? "";
  await mkdir(DIR, { recursive: true });
  await writeFile(file, bytes);
  await writeFile(sidecar(file), JSON.stringify({ prompt, provider, created }));
  return { file, prompt, provider, created };
}
