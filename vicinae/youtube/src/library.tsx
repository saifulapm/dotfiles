import { useCallback, useEffect, useState } from "react";
import { Action, ActionPanel, Icon, List } from "@vicinae/api";
import { ResultItem } from "./lib/browse";
import * as store from "./lib/store";

export default function Command() {
  const [starred, setStarred] = useState<store.Saved[]>([]);
  const [history, setHistory] = useState<store.Saved[]>([]);
  const [loading, setLoading] = useState(true);
  const [showingDetail, setShowingDetail] = useState(false);

  const refresh = useCallback(async () => {
    const [saved, played] = await Promise.all([
      store.getList("starred"),
      store.getList("history"),
    ]);
    setStarred(saved);
    setHistory(played);
    setLoading(false);
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const starredIds = new Set(starred.map((i) => i.id));
  const empty = !loading && starred.length === 0 && history.length === 0;

  // No shortcut on either: they would have to share one, and the panel is
  // reached from a row that exists only to hold them.
  const clearAction = (key: store.ListKey, title: string) => (
    <Action
      title={title}
      icon={Icon.Trash}
      style="destructive"
      onAction={async () => {
        await store.clear(key);
        await refresh();
      }}
    />
  );

  return (
    <List
      isLoading={loading}
      isShowingDetail={showingDetail && !empty}
      searchBarPlaceholder="Filter your library"
    >
      {empty ? (
        <List.EmptyView
          icon={Icon.Star}
          title="Nothing saved yet"
          description="Play something from Search on YouTube, or save it with ⌘S."
        />
      ) : null}

      <List.Section title="Watch Later" subtitle={String(starred.length)}>
        {starred.map((result) => (
          <ResultItem
            key={`starred-${result.id}`}
            result={result}
            starred
            showingDetail={showingDetail}
            onToggleDetail={() => setShowingDetail((v) => !v)}
            onStoreChanged={refresh}
            removeFrom="starred"
          />
        ))}
      </List.Section>

      <List.Section title="Recently Played" subtitle={String(history.length)}>
        {history.map((result) => (
          <ResultItem
            key={`history-${result.id}`}
            result={result}
            starred={starredIds.has(result.id)}
            showingDetail={showingDetail}
            onToggleDetail={() => setShowingDetail((v) => !v)}
            onStoreChanged={refresh}
            removeFrom="history"
          />
        ))}
      </List.Section>

      {/* The two clears hang off a hidden row rather than every item's panel:
          wiping the list is not something to offer next to "play this". */}
      {empty ? null : (
        <List.Section title="Manage">
          <List.Item
            title="Clear lists"
            icon={Icon.Trash}
            actions={
              <ActionPanel>
                {clearAction("history", "Clear Recently Played")}
                {clearAction("starred", "Clear Watch Later")}
              </ActionPanel>
            }
          />
        </List.Section>
      )}
    </List>
  );
}
