# Index Page Template

**When to use:** List/table of resources. Loader returns an array of objects with pagination.

**Data shape:**

```typescript
interface IndexData {
  items: Array<{
    id: string;
    title: string;
    status: string;
    updatedAt: string;
  }>;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
}
```

**Complete route file:**

```tsx
import type { LoaderFunctionArgs } from "react-router";
import { useLoaderData, useSearchParams } from "react-router";
import { authenticate } from "../shopify.server";
import { useState, useCallback } from "react";

export const loader = async ({ request }: LoaderFunctionArgs) => {
  const { admin } = await authenticate.admin(request);
  const url = new URL(request.url);
  const cursor = url.searchParams.get("cursor") || undefined;
  const direction = url.searchParams.get("direction") || "next";
  const query = url.searchParams.get("q") || "";
  const statusFilter = url.searchParams.get("status") || "all";

  // Replace with your actual data fetching logic
  const items = [
    { id: "1", title: "Summer campaign", status: "active", updatedAt: "2026-03-15" },
    { id: "2", title: "Flash sale banner", status: "draft", updatedAt: "2026-03-14" },
    { id: "3", title: "Holiday promo", status: "archived", updatedAt: "2026-03-10" },
  ];

  return {
    items,
    hasNextPage: true,
    hasPreviousPage: !!cursor && direction !== "next",
  };
};

export default function IndexPage() {
  const { items, hasNextPage, hasPreviousPage } = useLoaderData<typeof loader>();
  const [searchParams, setSearchParams] = useSearchParams();
  const [queryValue, setQueryValue] = useState(searchParams.get("q") || "");
  const [statusFilter, setStatusFilter] = useState(searchParams.get("status") || "all");

  const handleSearch = useCallback(
    (value: string) => {
      setQueryValue(value);
      const params = new URLSearchParams(searchParams);
      if (value) {
        params.set("q", value);
      } else {
        params.delete("q");
      }
      setSearchParams(params);
    },
    [searchParams, setSearchParams],
  );

  const handleStatusChange = useCallback(
    (value: string) => {
      setStatusFilter(value);
      const params = new URLSearchParams(searchParams);
      if (value !== "all") {
        params.set("status", value);
      } else {
        params.delete("status");
      }
      setSearchParams(params);
    },
    [searchParams, setSearchParams],
  );

  const statusToneMap: Record<string, string> = {
    active: "success",
    draft: "info",
    archived: "default",
  };

  // Compositional empty state when no items
  if (items.length === 0) {
    return (
      <s-page heading="Campaigns" size="large">
        <s-button slot="primary-action" variant="primary" url="/app/campaigns/new">
          Create campaign
        </s-button>
        <s-section>
          <s-box padding="1600" align="center">
            <s-text variant="headingMd" as="p">
              No campaigns yet
            </s-text>
            <s-text variant="bodySm" tone="subdued" as="p">
              Create your first campaign to get started.
            </s-text>
            <s-box padding-block-start="400">
              <s-button variant="primary" url="/app/campaigns/new">
                Create campaign
              </s-button>
            </s-box>
          </s-box>
        </s-section>
      </s-page>
    );
  }

  return (
    <s-page heading="Campaigns" size="large">
      <s-button slot="primary-action" variant="primary" url="/app/campaigns/new">
        Create campaign
      </s-button>

      <s-section>
        {/* Search and filters */}
        <s-box padding-block-end="400">
          <s-grid columns="2 2 3">
            <s-search-field
              aria-label="Search campaigns"
              value={queryValue}
              placeholder="Search campaigns"
              onInput={(e: any) => handleSearch(e.target.value)}
            />
            <s-select
              label="Status"
              value={statusFilter}
              onChange={(e: any) => handleStatusChange(e.target.value)}
            >
              <option value="all">All</option>
              <option value="active">Active</option>
              <option value="draft">Draft</option>
              <option value="archived">Archived</option>
            </s-select>
          </s-grid>
        </s-box>

        {/* Resource table */}
        <s-table>
          <thead>
            <tr>
              <th>Title</th>
              <th>Status</th>
              <th>Last updated</th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id}>
                <td>
                  <s-link url={`/app/campaigns/${item.id}`}>
                    {item.title}
                  </s-link>
                </td>
                <td>
                  <s-badge tone={statusToneMap[item.status] || "default"}>
                    {item.status}
                  </s-badge>
                </td>
                <td>
                  <s-text variant="bodySm" tone="subdued">
                    {item.updatedAt}
                  </s-text>
                </td>
              </tr>
            ))}
          </tbody>
        </s-table>

        {/* Pagination */}
        <s-box padding="400" align="center">
          <s-button
            disabled={!hasPreviousPage}
            onClick={() => {
              const params = new URLSearchParams(searchParams);
              params.set("direction", "previous");
              setSearchParams(params);
            }}
          >
            Previous
          </s-button>
          <s-button
            disabled={!hasNextPage}
            onClick={() => {
              const params = new URLSearchParams(searchParams);
              params.set("direction", "next");
              setSearchParams(params);
            }}
          >
            Next
          </s-button>
        </s-box>
      </s-section>
    </s-page>
  );
}
```
