import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { promisify } from "node:util";
import { getPreferenceValues } from "@vicinae/api";

const execFileAsync = promisify(execFile);

export type Kind = "video" | "channel" | "playlist";

/** One row as `youtube search` prints it. Every field but kind/id/url/title
 *  can be absent — a live stream has no duration, a channel has no views. */
export type Result = {
  kind: Kind;
  id: string;
  url: string;
  title: string;
  channel: string | null;
  channelUrl: string | null;
  duration: number | null;
  views: number | null;
  live: boolean;
  subscribers: number | null;
  description: string | null;
  thumbnail: string | null;
};

export type Filter =
  | "relevance"
  | "date"
  | "views"
  | "rating"
  | "live"
  | "playlist"
  | "channel";

export const FILTERS: { value: Filter; title: string }[] = [
  { value: "relevance", title: "Relevance" },
  { value: "date", title: "Upload date" },
  { value: "views", title: "View count" },
  { value: "rating", title: "Rating" },
  { value: "live", title: "Live now" },
  { value: "playlist", title: "Playlists" },
  { value: "channel", title: "Channels" },
];

// bin/youtube, and everything it in turn shells out to (app-run, music, mpv,
// chromium-ytdlp-host), live in the dotfiles bin. The extension runtime is a
// child of vicinae.service, whose PATH comes from the user manager and does
// not carry it — so it is prepended here exactly as every bin/ script does
// for its own children.
const PATH = [
  `${homedir()}/.dotfiles/bin`,
  `${homedir()}/.local/bin`,
  process.env.PATH ?? "",
].join(":");

async function cli(args: string[]): Promise<string> {
  const { stdout } = await execFileAsync("youtube", args, {
    env: { ...process.env, PATH },
    // A search is one yt-dlp request against YouTube; 60 results measured
    // 3.8 s on a good day, and a stalled request must fail rather than hang
    // the view forever.
    timeout: 60_000,
  });
  return stdout;
}

async function cliJson(args: string[]): Promise<Result[]> {
  return JSON.parse(await cli(args)) as Result[];
}

function prefs(): Preferences {
  return getPreferenceValues<Preferences>();
}

export function pageSize(): number {
  return Number(prefs().pageSize ?? "20") || 20;
}

export function search(
  query: string,
  filter: Filter,
  limit: number,
  offset: number,
): Promise<Result[]> {
  return cliJson([
    "search",
    "--limit",
    String(limit),
    "--offset",
    String(offset),
    "--filter",
    filter,
    "--",
    query,
  ]);
}

export function channelVideos(
  url: string,
  limit: number,
  offset: number,
): Promise<Result[]> {
  return cliJson([
    "channel",
    "--limit",
    String(limit),
    "--offset",
    String(offset),
    url,
  ]);
}

/** Returns as soon as mpv's transient unit is started, not when it exits. */
export async function play(url: string, title: string): Promise<void> {
  await execFileAsync("youtube", ["play", url, title], {
    env: { ...process.env, PATH, YOUTUBE_QUALITY: prefs().quality ?? "1080" },
  });
}

export async function playAudio(url: string, title: string): Promise<void> {
  await execFileAsync("youtube", ["audio", url, title], {
    env: { ...process.env, PATH },
  });
}

export async function download(url: string, audio: boolean): Promise<void> {
  await execFileAsync(
    "youtube",
    audio ? ["download", "--audio", url] : ["download", url],
    { env: { ...process.env, PATH } },
  );
}

export function formatDuration(seconds: number | null, live: boolean): string {
  if (live) return "LIVE";
  if (seconds === null || !Number.isFinite(seconds)) return "";
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

export function formatCount(n: number | null): string {
  if (n === null || !Number.isFinite(n)) return "";
  if (n < 1_000) return String(n);
  const units: [number, string][] = [
    [1_000_000_000, "B"],
    [1_000_000, "M"],
    [1_000, "K"],
  ];
  for (const [size, suffix] of units) {
    if (n >= size) {
      const value = n / size;
      // 2.7B, but 12M rather than 12.4M — one significant decimal only while
      // it still says something.
      return `${value >= 10 ? Math.round(value) : value.toFixed(1)}${suffix}`;
    }
  }
  return String(n);
}
