# Polaris Web Components

## Page Structure

`s-page` is the root component. The `size` prop controls max-width:
- `base` — forms, settings (default if omitted)
- `large` — data tables, wide layouts

Page actions use **slots on `s-page`**, not a separate title bar component.

| Slot | Purpose | Element |
|------|---------|---------|
| `slot="primary-action"` | Single primary action | `<s-button>` |
| `slot="secondary-actions"` | Additional actions | `<s-button>` elements |
| `slot="breadcrumb-actions"` | Back navigation | `<s-link>` |
| `slot="aside"` | Sidebar (two-column) | Any content |

```html
<!-- ✅ Correct: actions as slots on s-page -->
<s-page heading="Products" size="large">
  <s-link slot="breadcrumb-actions" href="/products">Back</s-link>
  <s-button slot="primary-action" variant="primary">Add product</s-button>
  <s-button slot="secondary-actions">Export</s-button>
  <s-button slot="secondary-actions">Import</s-button>

  <s-section heading="All products">
    <!-- content -->
  </s-section>
</s-page>
```

```html
<!-- ❌ Wrong: using a separate title bar component -->
<s-page heading="Products">
  <s-title-bar primaryAction="Add product">
    <button>Export</button>
  </s-title-bar>
</s-page>
```

---

## Sections & Boxes

`s-section` — card-like content group with optional `heading`. Use for logical groupings.
`s-box` — layout/spacing utility ONLY (padding, borders, spacing). No semantic meaning.

```html
<!-- ✅ Correct: s-section for content groups -->
<s-section heading="Pricing">
  <s-text-field label="Price" />
  <s-text-field label="Compare at price" />
</s-section>
```

```html
<!-- ❌ Wrong: s-box for content grouping -->
<s-box padding="400">
  <s-heading>Pricing</s-heading>
  <s-text-field label="Price" />
</s-box>
```

```html
<!-- ✅ Correct: s-box for spacing adjustment inside a section -->
<s-section heading="Details">
  <s-box padding="400">
    <s-text tone="subdued">Extra padded content area</s-text>
  </s-box>
</s-section>
```

---

## Stack

`s-stack` handles vertical and horizontal layout. Always specify `gap` — there is no default.

Props:
- `direction` — `"block"` (vertical) or `"inline"` (horizontal)
- `gap` — spacing value (e.g., `"200"`, `"400"`, `"600"`)
- `alignItems` — cross-axis alignment (`"center"`, `"start"`, `"end"`, `"stretch"`)
- `justifyContent` — main-axis alignment (`"center"`, `"start"`, `"end"`, `"space-between"`)

```html
<!-- ✅ Correct: s-stack for layout -->
<s-stack direction="inline" gap="400" alignItems="center" justifyContent="space-between">
  <s-text>Status</s-text>
  <s-badge>Active</s-badge>
</s-stack>
```

```html
<!-- ❌ Wrong: flex divs instead of s-stack -->
<div style="display: flex; gap: 16px; align-items: center;">
  <span>Status</span>
  <s-badge>Active</s-badge>
</div>
```

---

## Grid

`s-grid` provides responsive column layouts.

Props:
- `columns` — base column count
- `md-columns` — medium breakpoint columns
- `lg-columns` — large breakpoint columns

```html
<!-- ✅ Correct: responsive s-grid -->
<s-grid columns="1" md-columns="2" lg-columns="3">
  <s-section heading="Card 1">...</s-section>
  <s-section heading="Card 2">...</s-section>
  <s-section heading="Card 3">...</s-section>
</s-grid>
```

```html
<!-- ❌ Wrong: hardcoded CSS grid -->
<div style="display: grid; grid-template-columns: repeat(3, 1fr);">
  <div>Card 1</div>
  <div>Card 2</div>
</div>
```

---

## Buttons

Rules:
- **One primary button per page context**
- Labels follow `{verb} + {noun}` pattern: "Add product", "Save settings", "Delete collection"

Variants:
| Variant | Usage |
|---------|-------|
| `variant="primary"` | Main action |
| *(default, no variant)* | Secondary actions |
| `variant="primary" tone="critical"` | Destructive actions |
| `variant="plain"` | Tertiary / low-emphasis |

Props: `loading`, `disabled`

```html
<!-- ✅ Correct: verb+noun labels, one primary -->
<s-button variant="primary">Save product</s-button>
<s-button>Discard changes</s-button>
<s-button variant="primary" tone="critical">Delete product</s-button>
<s-button variant="plain">Cancel</s-button>
<s-button variant="primary" loading>Saving product</s-button>
```

```html
<!-- ❌ Wrong: vague labels, multiple primaries -->
<s-button variant="primary">Submit</s-button>
<s-button variant="primary">Save</s-button>
```

---

## Text & Typography

- `s-text` — inline text with `variant` and `tone` props
- `s-heading` — headings with `as` prop for semantic HTML (`h1`, `h2`, `h3`, etc.)
- `s-paragraph` — block-level text

```html
<!-- ✅ Correct: Polaris typography components -->
<s-heading as="h2">Order details</s-heading>
<s-paragraph>This order was placed on March 15, 2026.</s-paragraph>
<s-text variant="bodySm" tone="subdued">Last updated 2 hours ago</s-text>
```

```html
<!-- ❌ Wrong: inline styled HTML tags -->
<p style="font-size: 14px; color: gray;">Last updated 2 hours ago</p>
<h2 style="font-weight: bold;">Order details</h2>
```

---

## Overlays

### Modal

`s-modal` — always include `heading`. Footer actions go in `slot="footer"`.

```html
<s-modal heading="Delete product?">
  <s-text>This can't be undone.</s-text>
  <s-button-group slot="footer">
    <s-button>Cancel</s-button>
    <s-button variant="primary" tone="critical">Delete product</s-button>
  </s-button-group>
</s-modal>
```

### App Window

`s-app-window` — for immersive, full-screen tasks. Launch from **page body only** (never from nav). Use `command`/`commandFor` to connect trigger and window.

```html
<!-- ✅ Correct: command/commandFor pattern -->
<s-button command="--show" commandFor="my-editor">Open Editor</s-button>
<s-app-window id="my-editor">
  <!-- immersive content -->
</s-app-window>
```

```html
<!-- ❌ Wrong: launching app-window from nav -->
<s-app-nav>
  <s-link command="--show" commandFor="editor">Editor</s-link>
</s-app-nav>
```

### Popover

`s-popover` — contextual overlays attached to a trigger element.

---

## Empty States

There is **no `s-empty-state` component**. Build empty states compositionally:

```html
<!-- ✅ Correct: compositional empty state -->
<s-section>
  <s-box padding="1000">
    <s-stack direction="block" gap="400" alignItems="center">
      <s-heading>No campaigns yet</s-heading>
      <s-text tone="subdued">Create your first campaign to start reaching customers.</s-text>
      <s-button variant="primary">Create campaign</s-button>
    </s-stack>
  </s-box>
</s-section>
```

```html
<!-- ❌ Wrong: s-empty-state does not exist -->
<s-empty-state heading="No campaigns yet" action="Create campaign" />
```

---

## Complete Component Catalog

### Actions
`s-button`, `s-button-group`, `s-clickable`, `s-clickable-chip`, `s-link`, `s-menu`

### Forms
`s-text-field`, `s-text-area`, `s-select`, `s-checkbox`, `s-choice-list`, `s-switch`, `s-number-field`, `s-money-field`, `s-email-field`, `s-password-field`, `s-url-field`, `s-date-field`, `s-date-picker`, `s-color-field`, `s-color-picker`, `s-search-field`, `s-drop-zone`

### Feedback & Status
`s-badge` (supports `icon` attribute), `s-banner`, `s-spinner`

### Layout & Structure
`s-box`, `s-divider`, `s-grid`, `s-ordered-list`, `s-unordered-list`, `s-query-container`, `s-section`, `s-stack`, `s-table` (supports `paginate`, `hasPreviousPage`, `hasNextPage`, `onPreviousPage`, `onNextPage`)

### Media & Visuals
`s-avatar`, `s-icon`, `s-image`, `s-thumbnail`

### Overlays
`s-modal`, `s-popover`

### Structure
`s-page`

### Typography & Content
`s-chip`, `s-heading`, `s-paragraph`, `s-text`, `s-tooltip`

### App Bridge
- `s-app-nav` — navigation component, uses `s-link` children with `rel="home"`
- `s-app-window` — immersive full-screen overlay
- **Save Bar** — uses `data-save-bar` and `data-discard-confirmation` attributes. Programmatic API: `shopify.saveBar.show()`, `shopify.saveBar.hide()`, `shopify.saveBar.toggle()`
