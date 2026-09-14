import { useEffect, useRef, useState } from "react";
import { mkdir, readFile, readdir, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  Action,
  ActionPanel,
  Clipboard,
  Grid,
  Icon,
  Keyboard,
  type LaunchProps,
  Toast,
  environment,
  showHUD,
  showToast,
} from "@vicinae/api";
import { ENDPOINT, TOKEN } from "./lib/pxy";

// Generated images through pxy's /v1/images/generations, shown in a Grid.
//
// WHY A GRID AND NOT MARKDOWN: the markdown pane clamps every image to 200 px
// tall no matter what (MdImage.qml), so a Detail would show thumbnails; a
// Grid cell renders at its full size. The image loader takes a bare
// absolute path, so each cell is a file under the extension's support
// directory and that directory is the history — nothing is stored anywhere
// else. Grid items carry no accessory (declared in the TS types, dropped by
// the server), so the prompt is the title and the provider the subtitle.
const DIR = join(environment.supportPath, "images");

type Generated = {
  file: string;
  prompt: string;
  provider: string;
  created: number;
};

export default function Command(props: LaunchProps<{ arguments: Arguments.Imagine }>) {
  const [input, setInput] = useState("");
  const [items, setItems] = useState<Generated[]>([]);
  const [pending, setPending] = useState<string | null>(null);
  const started = useRef(false);

  const refresh = () => void list().then(setItems);

  const generate = async (prompt: string) => {
    const trimmed = prompt.trim();
    if (!trimmed || pending) return;
    setPending(trimmed);
    setInput("");
    const toast = await showToast({ style: Toast.Style.Animated, title: "Generating…", message: trimmed });
    try {
      const made = await create(trimmed);
      toast.style = Toast.Style.Success;
      toast.title = `Generated via ${made.provider}`;
      refresh();
    } catch (thrown) {
      toast.style = Toast.Style.Failure;
      toast.title = "Could not generate";
      toast.message = thrown instanceof Error ? thrown.message : String(thrown);
    } finally {
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

  const remove = async (item: Generated) => {
    await Promise.all([unlink(item.file), unlink(sidecar(item.file))]);
    refresh();
  };

  const composer = input.trim() ? (
    <Action title="Generate" icon={Icon.Stars} onAction={() => void generate(input)} />
  ) : null;

  return (
    <Grid
      columns={3}
      aspectRatio="1"
      fit={Grid.Fit.Contain}
      inset={Grid.Inset.Small}
      searchText={input}
      onSearchTextChange={setInput}
      // The cells are history, not search results — filtering them against
      // the prompt being typed would empty the grid while composing.
      filtering={false}
      isLoading={pending !== null}
      searchBarPlaceholder="Describe an image and press Enter"
      navigationTitle="Imagine"
    >
      {items.length === 0 ? (
        <Grid.EmptyView
          icon={Icon.Image}
          title={input.trim() ? `Generate “${input.trim()}”` : "Describe an image"}
          description={pending ? "Generating…" : "Press Enter. Images are kept here until deleted."}
          actions={<ActionPanel>{composer}</ActionPanel>}
        />
      ) : (
        items.map((item) => (
          <Grid.Item
            key={item.file}
            id={item.file}
            content={item.file}
            title={item.prompt}
            subtitle={item.provider}
            actions={
              <ActionPanel>
                {composer}
                <Action.Open title="Open" target={item.file} icon={Icon.Eye} />
                <Action
                  title="Copy Image"
                  icon={Icon.CopyClipboard}
                  shortcut={Keyboard.Shortcut.Common.Copy}
                  onAction={() =>
                    // A file reference (text/uri-list), the only image form
                    // the clipboard API has; pastes into file managers and
                    // most chat apps, not into an image editor's canvas.
                    void Clipboard.copy({ file: item.file }).then(() => showHUD("Copied image"))
                  }
                />
                <Action.ShowInFinder path={item.file} />
                <Action
                  title="Regenerate"
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
    </Grid>
  );
}

const sidecar = (file: string) => file.replace(/\.(jpg|png)$/, ".json");

/** Newest first. The sidecar is the record; an image without one (a hand
 *  copied file) is shown with its filename as the prompt. */
async function list(): Promise<Generated[]> {
  await mkdir(DIR, { recursive: true });
  const names = (await readdir(DIR)).filter((n) => /\.(jpg|png)$/.test(n));
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

async function create(prompt: string): Promise<Generated> {
  const response = await fetch(`${ENDPOINT}/images/generations`, {
    method: "POST",
    headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ prompt }),
  });
  const json: any = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(json?.error?.message || json?.errors?.[0]?.message || `pxy answered ${response.status}`);
  }
  // pxy normalises every provider to OpenAI's shape: base64 from Cloudflare
  // (verified: JPEG, 1024×1024), a URL from the others.
  const first = json.data?.[0] ?? {};
  const bytes = first.b64_json
    ? Buffer.from(first.b64_json, "base64")
    : Buffer.from(await (await fetch(first.url)).arrayBuffer());
  const png = bytes[0] === 0x89 && bytes[1] === 0x50;
  const created = Date.now();
  const slug = prompt.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
  const file = join(DIR, `${created}-${slug}.${png ? "png" : "jpg"}`);
  const provider = response.headers.get("x-pxy-provider") ?? "";
  await mkdir(DIR, { recursive: true });
  await writeFile(file, bytes);
  await writeFile(sidecar(file), JSON.stringify({ prompt, provider, created }));
  return { file, prompt, provider, created };
}
