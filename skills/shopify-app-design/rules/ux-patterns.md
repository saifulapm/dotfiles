# UX Patterns

## Homepage

The app homepage should surface status updates, key metrics, actionable items, and support access.

Support placement options:
- App nav link
- Footer links
- Floating help button

### Metrics card pattern

```html
<s-page heading="Dashboard">
  <s-grid columns="3">
    <s-section>
      <s-text variant="headingMd">Total orders</s-text>
      <s-text variant="headingXl">1,284</s-text>
      <s-text tone="subdued">+12% from last month</s-text>
    </s-section>
    <s-section>
      <s-text variant="headingMd">Revenue</s-text>
      <s-text variant="headingXl">$24,500</s-text>
      <s-text tone="subdued">+8% from last month</s-text>
    </s-section>
    <s-section>
      <s-text variant="headingMd">Active subscriptions</s-text>
      <s-text variant="headingXl">342</s-text>
      <s-text tone="subdued">+3% from last month</s-text>
    </s-section>
  </s-grid>
</s-page>
```

## Onboarding

- Maximum 5 steps.
- Brief and direct instructions.
- Dismissible (cancel icon if non-essential).
- Show step position ("Step 2 of 4").
- Auto-mark steps as complete when done.
- Offer "Remind me later" option.

```html
<s-page heading="Get started">
  <s-section>
    <s-box padding="400">
      <s-text variant="headingMd">Set up your store (Step 2 of 4)</s-text>
      <s-box padding-block-start="200">
        <s-stack direction="block" gap="200">
          <s-box>
            <s-stack direction="inline" align="center" gap="200">
              <s-icon name="check-circle" tone="success"></s-icon>
              <s-text tone="subdued">Connect your account</s-text>
            </s-stack>
          </s-box>
          <s-box>
            <s-stack direction="inline" align="center" gap="200">
              <s-icon name="circle"></s-icon>
              <s-text>Configure shipping rates</s-text>
            </s-stack>
          </s-box>
          <s-box>
            <s-stack direction="inline" align="center" gap="200">
              <s-icon name="circle"></s-icon>
              <s-text tone="subdued">Add your first product</s-text>
            </s-stack>
          </s-box>
          <s-box>
            <s-stack direction="inline" align="center" gap="200">
              <s-icon name="circle"></s-icon>
              <s-text tone="subdued">Launch your store</s-text>
            </s-stack>
          </s-box>
        </s-stack>
      </s-box>
      <s-box padding-block-start="400">
        <s-stack direction="inline" gap="200">
          <s-button variant="primary">Configure shipping</s-button>
          <s-button variant="plain">Remind me later</s-button>
        </s-stack>
      </s-box>
    </s-box>
  </s-section>
</s-page>
```

## Empty States

Use compositional markup. There is no `s-empty-state` component. Explain the value of what the merchant will see once populated, and provide a clear CTA.

```html
<s-section>
  <s-box padding="800" align="center">
    <s-box max-width="300px">
      <s-text variant="headingMd">No products yet</s-text>
      <s-box padding-block-start="200">
        <s-text tone="subdued">
          Add your first product to start selling and tracking inventory.
        </s-text>
      </s-box>
      <s-box padding-block-start="400">
        <s-button variant="primary">Add product</s-button>
      </s-box>
    </s-box>
  </s-box>
</s-section>
```

## Settings

Group settings into `s-section` blocks in logical order. Keep them scannable. Pair with `data-save-bar` to show a save bar when changes are pending.

```html
<s-page heading="Settings">
  <form data-save-bar>
    <s-section heading="General">
      <s-text-field label="Store name" value="My Store"></s-text-field>
      <s-text-field label="Contact email" type="email" value="hi@store.com"></s-text-field>
    </s-section>
    <s-section heading="Notifications">
      <s-checkbox label="Email me about new orders" checked></s-checkbox>
      <s-checkbox label="Email me about low inventory"></s-checkbox>
    </s-section>
  </form>
</s-page>
```

## Index Page

Combines search, filters, table, pagination, and bulk actions. Title bar actions go in `s-page` slots.

```html
<s-page heading="Products" size="large">
  <s-button slot="primary-action" variant="primary">Add product</s-button>
  <s-button slot="secondary-actions">Export</s-button>

  <s-section>
    <s-stack direction="inline" gap="200">
      <s-search-field label="Search products" placeholder="Search products"></s-search-field>
      <s-select label="Status" name="status">
        <option value="all">All</option>
        <option value="active">Active</option>
        <option value="draft">Draft</option>
      </s-select>
    </s-stack>

    <s-stack direction="block" gap="200">
      <s-box padding="300">
        <s-stack direction="inline" align="center" gap="200">
          <s-link href="/products/1"><s-text>Widget Pro</s-text></s-link>
          <s-text tone="subdued">Active - $29.99</s-text>
        </s-stack>
      </s-box>
      <s-divider></s-divider>
      <s-box padding="300">
        <s-stack direction="inline" align="center" gap="200">
          <s-link href="/products/2"><s-text>Widget Basic</s-text></s-link>
          <s-text tone="subdued">Draft - $9.99</s-text>
        </s-stack>
      </s-box>
    </s-stack>
  </s-section>

  <s-button-group>
    <s-button disabled>Previous</s-button>
    <s-button>Next</s-button>
  </s-button-group>
</s-page>
```

## Detail Page

Form with save bar, breadcrumb navigation via `s-page` slot, and a delete confirmation modal.

```html
<s-page heading="Widget Pro" size="base">
  <s-link slot="breadcrumb-actions" href="/products">Products</s-link>
  <s-button slot="secondary-actions" tone="critical" commandFor="delete-modal">Delete</s-button>

  <form data-save-bar>
    <s-section heading="Product details">
      <s-text-field label="Title" value="Widget Pro"></s-text-field>
      <s-text-field label="Price" type="number" value="29.99" prefix="$"></s-text-field>
      <s-select label="Status">
        <option value="active" selected>Active</option>
        <option value="draft">Draft</option>
      </s-select>
    </s-section>
  </form>

  <s-modal id="delete-modal" heading="Delete Widget Pro?">
    <s-text>This can't be undone. The product and all its data will be permanently removed.</s-text>
    <s-button slot="primary-action" tone="critical" variant="primary">Delete product</s-button>
    <s-button slot="secondary-actions">Cancel</s-button>
  </s-modal>
</s-page>
```

## Marketing Guidelines

- Dismissible promotional content placed at the bottom of the page.
- Once dismissed, **never** show that message again for the same merchant (permanent dismissal).
- Use a dedicated promotional page as an alternative to inline promotions.
- **Feature gating:** Show paid features as visually disabled with subdued text explaining the upgrade path.
- No pressure tactics, no fake reviews, no countdown timers.
- Never repeat identical promotional messages across multiple pages.
- Express brand through custom illustration, not heavy branding or logos in the UI.

```html
<!-- Feature gating example -->
<s-section>
  <s-box padding="400" opacity="50">
    <s-text variant="headingMd">Advanced analytics</s-text>
    <s-text tone="subdued">Upgrade to Pro to unlock detailed conversion reports.</s-text>
    <s-box padding-block-start="300">
      <s-button>Upgrade to Pro</s-button>
    </s-box>
  </s-box>
</s-section>
```

## Content Writing

- Plain language, active voice.
- Button and action labels: `{verb}+{noun}` (e.g., "Add product", "Export list").
- Target a seventh-grade reading level.
- No jargon, no idioms, no culturally specific references.
- Consistent terminology throughout the app.
- Empower merchants: provide enough information for independent decisions.
- Use the app's proper name on first reference, then "we" for subsequent mentions.

## Subscription Apps

- Price visibility is required: always show the price before the merchant commits.
- UI must match the storefront theme (color, font, size, weight) so the subscription widget feels native.

## Composition Patterns Reference

| Pattern | Use For | Key Components |
|---------|---------|----------------|
| Account connection | Connecting third-party accounts | `s-section` with status indicator, connect/disconnect `s-button` |
| Callout card | Highlighting a single action or promotion | `s-section` with illustration, heading, body text, and CTA `s-button` |
| Footer help | Persistent support links at page bottom | `s-box` with `s-link` elements to docs, support, community |
| Index table | Browsable lists of resources | `s-table` or `s-stack direction="block"` with `s-search-field`, `s-select`, `s-button-group` for pagination |
| Interstitial nav | Hub page linking to sub-sections | `s-section` items with `s-link` for each destination |
| Media card | Content with thumbnail or media preview | `s-section` with image slot and descriptive text |
| Metrics card | KPI display on dashboards | `s-section` within `s-grid`, heading + large number + trend text |
| Resource list | Actionable object lists with bulk operations | `s-stack direction="block"` with `s-box` items, bulk action toolbar |
| App card | Representing the app in admin surfaces | `s-section` matching admin card patterns, concise description |
| Setup guide | Onboarding task checklist | `s-section` with `s-ordered-list`, progress indicator, step CTA |
