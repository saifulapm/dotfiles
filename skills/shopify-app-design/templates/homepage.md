# Homepage Template

**When to use:** App's main landing page. Loader returns metrics, stats, and actionable items.

**Data shape:**

```typescript
interface HomepageData {
  metrics: { label: string; value: string; trend?: string }[];
  needsAttention: { title: string; description: string; actionUrl: string }[];
}
```

**Complete route file:**

```tsx
import type { LoaderFunctionArgs } from "react-router";
import { useLoaderData, useNavigation } from "react-router";
import { authenticate } from "../shopify.server";

export const loader = async ({ request }: LoaderFunctionArgs) => {
  const { admin } = await authenticate.admin(request);

  // Fetch metrics and needs-attention items from your data source
  const metrics = [
    { label: "Total orders", value: "1,204", trend: "+12%" },
    { label: "Active products", value: "86", trend: "+3%" },
    { label: "Conversion rate", value: "3.2%", trend: "-0.4%" },
  ];

  const needsAttention = [
    {
      title: "3 products out of stock",
      description: "Restock these items to avoid lost sales.",
      actionUrl: "/app/products?filter=out-of-stock",
    },
    {
      title: "Pending review: new pricing rule",
      description: "A draft pricing rule needs your approval.",
      actionUrl: "/app/pricing/draft-1",
    },
  ];

  return { metrics, needsAttention };
};

export default function Homepage() {
  const { metrics, needsAttention } = useLoaderData<typeof loader>();
  const navigation = useNavigation();
  const isLoading = navigation.state === "loading";

  if (isLoading) {
    return (
      <s-page heading="Dashboard">
        <s-grid columns="1 1 3">
          {[1, 2, 3].map((i) => (
            <s-section key={i}>
              <s-skeleton-text lines="2" />
            </s-section>
          ))}
        </s-grid>
        <s-section heading="Needs attention">
          <s-skeleton-text lines="4" />
        </s-section>
      </s-page>
    );
  }

  return (
    <s-page heading="Dashboard">
      {/* Metrics grid: 1 column on mobile, 3 on desktop */}
      <s-grid columns="1 1 3">
        {metrics.map((metric) => (
          <s-section key={metric.label}>
            <s-text variant="bodySm" tone="subdued">
              {metric.label}
            </s-text>
            <s-text variant="headingLg" as="p">
              {metric.value}
            </s-text>
            {metric.trend && (
              <s-text
                variant="bodySm"
                tone={metric.trend.startsWith("+") ? "success" : "critical"}
              >
                {metric.trend}
              </s-text>
            )}
          </s-section>
        ))}
      </s-grid>

      {/* Needs attention */}
      {needsAttention.length > 0 && (
        <s-section heading="Needs attention">
          {needsAttention.map((item) => (
            <s-box
              key={item.title}
              padding="400"
              border-block-end="base"
            >
              <s-text variant="headingSm" as="h3">
                {item.title}
              </s-text>
              <s-text variant="bodySm" tone="subdued">
                {item.description}
              </s-text>
              <s-link url={item.actionUrl}>Review</s-link>
            </s-box>
          ))}
        </s-section>
      )}

      {/* Support footer */}
      <s-box padding="400">
        <s-text variant="bodySm" tone="subdued">
          Need help?{" "}
          <s-link url="https://help.example.com" external>
            Visit our help center
          </s-link>{" "}
          or{" "}
          <s-link url="mailto:support@example.com" external>
            contact support
          </s-link>
          .
        </s-text>
      </s-box>
    </s-page>
  );
}
```
