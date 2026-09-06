import { useEffect, useState } from "react";
import {
  Action,
  ActionPanel,
  Icon,
  Keyboard,
  List,
  Toast,
  closeMainWindow,
  showToast,
} from "@vicinae/api";
import * as store from "./store";
import {
  channelVideos,
  download,
  formatCount,
  formatDuration,
  pageSize,
  play,
  playAudio,
  type Result,
} from "./youtube";

const SHORTCUT = {
  audio: { key: "return", modifiers: ["cmd"] },
  star: { key: "s", modifiers: ["cmd"] },
  channel: { key: "k", modifiers: ["cmd"] },
  detail: { key: "y", modifiers: ["cmd"] },
  download: { key: "d", modifiers: ["cmd"] },
  downloadAudio: { key: "d", modifiers: ["cmd", "shift"] },
  remove: { key: "x", modifiers: ["cmd"] },
} satisfies Record<string, Keyboard.Shortcut>;

async function withToast(failure: string, action: () => Promise<void>) {
  try {
    await action();
  } catch (error) {
    await showToast({
      style: Toast.Style.Failure,
      title: failure,
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

function subtitleOf(result: Result): string {
  if (result.kind === "channel") {
    const subs = formatCount(result.subscribers);
    return subs ? `${subs} subscribers` : "Channel";
  }
  return result.channel ?? "";
}

function accessoriesOf(result: Result): List.Item.Accessory[] {
  if (result.kind === "channel") return [];
  if (result.kind === "playlist") return [{ tag: "Playlist" }];

  const accessories: List.Item.Accessory[] = [];
  const views = formatCount(result.views);
  if (views) accessories.push({ text: `${views} views` });
  const duration = formatDuration(result.duration, result.live);
  if (duration) accessories.push({ tag: duration });
  return accessories;
}

function detailOf(result: Result) {
  return (
    <List.Item.Detail
      // The thumbnail is the point of the pane; a fenced image is the only
      // way to get one at a readable size, since an item icon is a 20px
      // square no matter what it points at.
      markdown={[
        result.thumbnail ? `![](${result.thumbnail})` : "",
        `## ${result.title}`,
        result.description ?? "",
      ]
        .filter(Boolean)
        .join("\n\n")}
      metadata={
        <List.Item.Detail.Metadata>
          {result.channel ? (
            <List.Item.Detail.Metadata.Label
              title="Channel"
              text={result.channel}
            />
          ) : null}
          {result.kind === "video" ? (
            <List.Item.Detail.Metadata.Label
              title="Duration"
              text={formatDuration(result.duration, result.live) || "unknown"}
            />
          ) : null}
          {result.views !== null ? (
            <List.Item.Detail.Metadata.Label
              title="Views"
              text={result.views.toLocaleString()}
            />
          ) : null}
          {result.subscribers !== null ? (
            <List.Item.Detail.Metadata.Label
              title="Subscribers"
              text={result.subscribers.toLocaleString()}
            />
          ) : null}
          <List.Item.Detail.Metadata.Separator />
          <List.Item.Detail.Metadata.Link
            title="Link"
            target={result.url}
            text={result.url}
          />
        </List.Item.Detail.Metadata>
      }
    />
  );
}

export type ItemProps = {
  result: Result;
  starred: boolean;
  showingDetail: boolean;
  onToggleDetail: () => void;
  /** Called after anything that changes a stored list, so the view reloads. */
  onStoreChanged?: () => void;
  /** Set in the library, where an entry can also be taken back out. */
  removeFrom?: store.ListKey;
};

export function ResultItem({
  result,
  starred,
  showingDetail,
  onToggleDetail,
  onStoreChanged,
  removeFrom,
}: ItemProps) {
  const playable = result.kind !== "channel";

  // mpv resolves a playlist URL into a queue on its own, so "play" means the
  // same thing for a video and for a playlist and needs no special case.
  const start = (audio: boolean) =>
    withToast("Could not start mpv", async () => {
      await store.recordPlay(result);
      onStoreChanged?.();
      // Both start a transient unit and return as soon as systemd has it, so
      // the window can close on a resolved promise rather than optimistically.
      if (audio) await playAudio(result.url, result.title);
      else await play(result.url, result.title);
      await closeMainWindow();
    });

  const star = () =>
    withToast("Could not save it", async () => {
      const saved = await store.toggleStar(result);
      onStoreChanged?.();
      await showToast({
        style: Toast.Style.Success,
        title: saved ? "Saved for later" : "Removed from Watch Later",
        message: result.title,
      });
    });

  const startDownload = (audio: boolean) =>
    withToast("Could not start the download", async () => {
      await download(result.url, audio);
      await showToast({
        style: Toast.Style.Success,
        title: audio ? "Downloading audio" : "Downloading video",
        message: result.title,
      });
    });

  return (
    <List.Item
      id={result.id}
      title={result.title}
      subtitle={showingDetail ? undefined : subtitleOf(result)}
      icon={result.thumbnail ?? Icon.Video}
      accessories={showingDetail ? undefined : accessoriesOf(result)}
      detail={detailOf(result)}
      keywords={result.channel ? [result.channel] : undefined}
      actions={
        <ActionPanel>
          <ActionPanel.Section>
            {playable ? (
              <Action
                title={result.kind === "playlist" ? "Play Playlist in Mpv" : "Play in Mpv"}
                icon={Icon.PlayFilled}
                onAction={() => start(false)}
              />
            ) : null}
            {playable ? (
              <Action
                title="Play Audio Only"
                icon={Icon.Music}
                shortcut={SHORTCUT.audio}
                onAction={() => start(true)}
              />
            ) : null}
            {result.kind === "channel" ? (
              <Action.Push
                title="Browse Channel"
                icon={Icon.Person}
                target={<ChannelVideos url={result.url} name={result.title} />}
              />
            ) : null}
          </ActionPanel.Section>

          <ActionPanel.Section>
            {result.channelUrl && result.kind !== "channel" ? (
              <Action.Push
                title="Browse Channel"
                icon={Icon.Person}
                shortcut={SHORTCUT.channel}
                target={
                  <ChannelVideos
                    url={result.channelUrl}
                    name={result.channel ?? "Channel"}
                  />
                }
              />
            ) : null}
            <Action
              title={starred ? "Remove from Watch Later" : "Save to Watch Later"}
              icon={starred ? Icon.StarDisabled : Icon.Star}
              shortcut={SHORTCUT.star}
              onAction={star}
            />
            <Action
              title={showingDetail ? "Hide Details" : "Show Details"}
              icon={Icon.Eye}
              shortcut={SHORTCUT.detail}
              onAction={onToggleDetail}
            />
          </ActionPanel.Section>

          <ActionPanel.Section>
            <Action.OpenInBrowser
              title="Open in Browser"
              url={result.url}
              shortcut={Keyboard.Shortcut.Common.Open}
            />
            <Action.CopyToClipboard
              title="Copy Link"
              content={result.url}
              shortcut={Keyboard.Shortcut.Common.Copy}
            />
            {playable ? (
              <Action
                title="Download Video"
                icon={Icon.Download}
                shortcut={SHORTCUT.download}
                onAction={() => startDownload(false)}
              />
            ) : null}
            {playable ? (
              <Action
                title="Download Audio"
                icon={Icon.Download}
                shortcut={SHORTCUT.downloadAudio}
                onAction={() => startDownload(true)}
              />
            ) : null}
          </ActionPanel.Section>

          {removeFrom ? (
            <ActionPanel.Section>
              <Action
                title="Remove from List"
                icon={Icon.Trash}
                style="destructive"
                shortcut={SHORTCUT.remove}
                onAction={() =>
                  withToast("Could not remove it", async () => {
                    await store.remove(removeFrom, result.id);
                    onStoreChanged?.();
                  })
                }
              />
            </ActionPanel.Section>
          ) : null}
        </ActionPanel>
      }
    />
  );
}

/** Reads Watch Later once and answers "is this one saved" for a whole list. */
export function useStarredIds(reloadKey: number): Set<string> {
  const [ids, setIds] = useState<Set<string>>(new Set());
  useEffect(() => {
    let live = true;
    store
      .getList("starred")
      .then((items) => {
        if (live) setIds(new Set(items.map((i) => i.id)));
      })
      .catch(() => undefined);
    return () => {
      live = false;
    };
  }, [reloadKey]);
  return ids;
}

export function ChannelVideos({ url, name }: { url: string; name: string }) {
  const [items, setItems] = useState<Result[]>([]);
  const [loading, setLoading] = useState(true);
  const [limit, setLimit] = useState(pageSize());
  const [showingDetail, setShowingDetail] = useState(false);
  const [reload, setReload] = useState(0);
  const starred = useStarredIds(reload);

  useEffect(() => {
    let live = true;
    setLoading(true);
    channelVideos(url, limit, 0)
      .then((next) => {
        if (live) setItems(next);
      })
      .catch(async (error) => {
        if (!live) return;
        await showToast({
          style: Toast.Style.Failure,
          title: "Could not load the channel",
          message: error instanceof Error ? error.message : String(error),
        });
      })
      .finally(() => {
        if (live) setLoading(false);
      });
    return () => {
      live = false;
    };
  }, [url, limit]);

  return (
    <List
      isLoading={loading}
      navigationTitle={name}
      searchBarPlaceholder={`Filter ${name}'s videos`}
      isShowingDetail={showingDetail}
      pagination={{
        // Growing the window rather than appending a page: the channel tab is
        // a stable reverse-chronological list, so a refetch returns the same
        // rows in the same order and nothing the user is looking at moves.
        hasMore: !loading && items.length >= limit,
        onLoadMore: () => setLimit((n) => n + pageSize()),
      }}
    >
      {items.map((result) => (
        <ResultItem
          key={result.id}
          result={result}
          starred={starred.has(result.id)}
          showingDetail={showingDetail}
          onToggleDetail={() => setShowingDetail((v) => !v)}
          onStoreChanged={() => setReload((n) => n + 1)}
        />
      ))}
    </List>
  );
}
