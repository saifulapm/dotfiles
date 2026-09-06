import { useCallback, useEffect, useRef, useState } from "react";
import {
  Action,
  ActionPanel,
  Icon,
  List,
  Toast,
  type LaunchProps,
  showToast,
} from "@vicinae/api";
import { ResultItem, useStarredIds } from "./lib/browse";
import { FILTERS, pageSize, search, type Filter, type Result } from "./lib/youtube";

export default function Command(
  props: LaunchProps<{ arguments: Arguments.Search }>,
) {
  // Three ways in, one starting query: picked from the root list with an
  // argument typed after it, launched as a fallback command (the whole root
  // search arrives as fallbackText — this is the "type it and hit Enter"
  // path), or opened bare.
  const [query, setQuery] = useState(
    props.arguments?.query || props.fallbackText || "",
  );
  const [filter, setFilter] = useState<Filter>("relevance");
  const [items, setItems] = useState<Result[]>([]);
  const [loading, setLoading] = useState(false);
  // Kept in the view, not only in a toast: a search that fails leaves an
  // empty list behind, and "no results" is a different thing from "yt-dlp
  // could not run" — reading which one it was should not depend on catching
  // a toast before it fades.
  const [error, setError] = useState<string | null>(null);
  const [exhausted, setExhausted] = useState(true);
  const [showingDetail, setShowingDetail] = useState(false);
  const [reload, setReload] = useState(0);
  const starred = useStarredIds(reload);

  // Refs, not state: onLoadMore fires from a closure the List holds, so it
  // would otherwise read whatever these were when that closure was made.
  const nextOffset = useRef(0);
  const busy = useRef(false);
  // Every search supersedes the one before it. Typing fires a request per
  // pause and YouTube answers in whatever order it likes, so a reply is only
  // allowed to land if it is still the newest one asked for.
  const request = useRef(0);

  const load = useCallback(async (q: string, f: Filter, offset: number) => {
    if (!q.trim()) {
      request.current += 1;
      setItems([]);
      setExhausted(true);
      setLoading(false);
      return;
    }
    // Only the next page is skipped while one is in flight — a NEW search has
    // to go through, or the last thing typed while a slow request was running
    // would never be the thing on screen.
    if (offset > 0 && busy.current) return;

    const id = (request.current += 1);
    const size = pageSize();
    busy.current = true;
    setLoading(true);
    try {
      const page = await search(q, f, size, offset);
      if (request.current !== id) return;
      setError(null);
      nextOffset.current = offset + size;
      setExhausted(page.length < size);
      setItems((prev) => {
        if (offset === 0) return page;
        // YouTube re-runs the search for every page and can hand back a row
        // that was already on an earlier one; appending it would show the
        // same video twice.
        const seen = new Set(prev.map((i) => i.id));
        return [...prev, ...page.filter((i) => !seen.has(i.id))];
      });
    } catch (thrown) {
      if (request.current !== id) return;
      const message =
        thrown instanceof Error ? thrown.message : String(thrown);
      setError(message);
      await showToast({
        style: Toast.Style.Failure,
        title: "Search failed",
        message,
      });
    } finally {
      busy.current = false;
      if (request.current === id) setLoading(false);
    }
  }, []);

  useEffect(() => {
    nextOffset.current = 0;
    void load(query, filter, 0);
  }, [query, filter, load]);

  const empty = !loading && items.length === 0;

  return (
    <List
      searchText={query}
      onSearchTextChange={setQuery}
      // Results are ranked by YouTube and fetched for this exact query;
      // re-ranking them locally would only fight that.
      filtering={false}
      throttle
      isLoading={loading}
      isShowingDetail={showingDetail && items.length > 0}
      searchBarPlaceholder="Search YouTube"
      searchBarAccessory={
        <List.Dropdown
          tooltip="Sort and filter"
          value={filter}
          onChange={(value) => setFilter(value as Filter)}
        >
          {FILTERS.map((f) => (
            <List.Dropdown.Item key={f.value} title={f.title} value={f.value} />
          ))}
        </List.Dropdown>
      }
      pagination={{
        hasMore: !exhausted && items.length > 0,
        onLoadMore: () => void load(query, filter, nextOffset.current),
      }}
    >
      {empty ? (
        <List.EmptyView
          icon={error ? Icon.Exclamationmark : Icon.MagnifyingGlass}
          title={
            error ? "Search failed" : query.trim() ? "No results" : "Search YouTube"
          }
          description={
            error
              ? error
              : query.trim()
                ? "YouTube search can also just fail — try again."
                : "Type what you want to watch."
          }
          actions={
            query.trim() ? (
              <ActionPanel>
                <Action
                  title="Try Again"
                  icon={Icon.ArrowClockwise}
                  onAction={() => void load(query, filter, 0)}
                />
              </ActionPanel>
            ) : null
          }
        />
      ) : (
        items.map((result) => (
          <ResultItem
            key={result.id}
            result={result}
            starred={starred.has(result.id)}
            showingDetail={showingDetail}
            onToggleDetail={() => setShowingDetail((v) => !v)}
            onStoreChanged={() => setReload((n) => n + 1)}
          />
        ))
      )}
    </List>
  );
}
