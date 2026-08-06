---
name: shopify-app-design
description: Build Shopify App Home UI with Polaris Web Components (s-* elements) and App Bridge. Triggers when building Shopify app pages, working with s-page, s-section, s-stack, s-button or any s-* web components, creating settings/index/details/homepage pages, implementing Shopify design guidelines, or connecting frontend to existing backend routes. Reads existing route loaders/actions to generate pixel-perfect pages matching native Shopify admin. Also triggers on mentions of Polaris, App Bridge, App Home, Shopify app UI, or React Router Shopify apps. Do NOT use @shopify/polaris React — App Home requires Web Components.
user-invocable: false
---

Build production-grade Shopify App Home pages using Polaris Web Components and App Bridge.

> **CRITICAL**: App Home uses Polaris Web Components (`s-*` elements), **NOT** `@shopify/polaris` React components.
>
> - Never `import` from `@shopify/polaris`.
> - Never use `<Card>`, `<Page>`, `<Layout>`, or any PascalCase Polaris React components.
> - All UI is built with `s-page`, `s-section`, `s-stack`, `s-button`, and other `s-*` custom elements.
> - These render as plain HTML custom elements in React Router routes.
> - If you see existing `@shopify/polaris` imports in the codebase, flag them for migration.

## Principles

These five principles guide every design decision:

1. **Match the Shopify admin** — pages must look and behave like native Shopify admin screens. Merchants should not notice a difference between your app and built-in Shopify pages.
2. **Use `s-*` components first** — search Polaris Web Components before writing custom markup. Only use raw HTML when no `s-*` component covers the need.
3. **Use design tokens** — `gap="400"`, `tone="subdued"`, `variant="headingMd"`. Never hardcode spacing, color, or typography values. Tokens ensure consistency with the Shopify admin theme.
4. **Mobile first** — design for mobile viewport, then enhance for desktop using responsive props on `s-grid` and `s-stack`. Test at 320px minimum width.
5. **Merchant-centric** — prioritize clarity, scannability, and task completion. Every screen should help the merchant accomplish a specific goal. Remove anything that does not serve that goal.

## Backend-First Workflow

Always start from the backend. Never generate UI without first understanding the data shape, available actions, and route structure. Follow these five steps for every page.

### Step 1: Inspect Backend

Read the route file. Extract loader return types and action handlers. Identify the data shape that drives the UI.

```tsx
// Read the route file first — understand what data is available
import type { loader } from "./route";

// Extract the return type to know exactly what fields exist
type LoaderData = Awaited<ReturnType<typeof loader>>;

// Use useLoaderData<typeof loader>() to get typed data in the component
// Inspect LoaderData fields to choose the right components:
//   - Array of objects → index page with s-table
//   - Single object with ID → details page
//   - Settings/config object → settings page with form
//   - Metrics/stats → homepage with dashboard layout
```

If no route file exists, ask the user for the data shape or generate a stub loader with `// TODO` placeholders. Do not invent data fields.

### Step 2: Choose Template

Use the decision matrix in "Page Template Selection" below. Match the loader return shape to the right template. When ambiguous, prefer the simpler template.

### Step 3: Generate Page

Wire `s-*` components to real data via React Router hooks: `useLoaderData()`, `useFetcher()`, `useActionData()`. Every dynamic value must come from the loader — no hardcoded placeholder data.

```tsx
import { useLoaderData } from "react-router";
import type { loader } from "./route";

export default function SettingsPage() {
  const { settings } = useLoaderData<typeof loader>();
  return (
    <s-page heading="Settings">
      <form data-save-bar>
        <s-section heading="Notifications">
          <s-stack direction="block" gap="400">
            <s-switch
              label="Email alerts"
              name="emailEnabled"
              checked={settings.emailEnabled}
            />
            <s-switch
              label="SMS alerts"
              name="smsEnabled"
              checked={settings.smsEnabled}
            />
          </s-stack>
        </s-section>
        <s-section heading="Preferences">
          <s-stack direction="block" gap="400">
            <s-select
              label="Language"
              name="language"
              value={settings.language}
            >
              <option value="en">English</option>
              <option value="fr">French</option>
            </s-select>
          </s-stack>
        </s-section>
      </form>
    </s-page>
  );
}
```

For mutations, use `useFetcher()` for non-navigating submissions and `useActionData()` for form validation errors returned from the action handler.

### Step 4: Apply Guidelines

- One primary button per page context. Place it in `s-page`'s `primary-action` slot.
- Correct heading hierarchy: `s-page heading` at the top, `s-section heading` for cards, `s-heading` inside sections.
- Semantic tones: green = success, red = error/critical, yellow = warning, blue = info. Never use color for decoration.
- `data-save-bar` attribute on all `<form>` elements that modify data.
- Responsive layout: use `s-grid` with `columns` responsive object for multi-column, `s-stack` for single-axis flow.
- Loading states: show `s-spinner` or skeleton content while data loads. Never show empty page during fetch.

### Step 5: Validate

If Shopify Dev MCP is available:
1. Run `validate_component_codeblocks` on the generated TSX output.
2. Run `validate_graphql_codeblocks` if the loader contains GraphQL queries.
3. Fix any reported issues before presenting the code to the user.

## Page Template Selection

Match the backend data shape to the correct template:

| Page Purpose | Template | Key Signals |
|---|---|---|
| Dashboard/overview with metrics | [homepage.md](./templates/homepage.md) | Loader returns metrics, stats, actionable items |
| List/table of resources | [index-page.md](./templates/index-page.md) | Loader returns array of objects |
| View/edit single resource | [details-page.md](./templates/details-page.md) | Loader returns single object, has action handler |
| App configuration | [settings-page.md](./templates/settings-page.md) | Loader returns settings object, form-heavy |
| First-time setup | [onboarding.md](./templates/onboarding.md) | User needs guided setup steps |

When combining patterns (e.g., a settings page with a table), use the primary purpose as the base template and incorporate elements from the secondary template. When the loader returns both a settings object and an array, prefer the settings template with an embedded `s-table`.

If the route has no loader (static page), use the homepage template structure with hardcoded content sections.

## Critical Rules

Read the linked rule files for full details. The summaries below are mandatory constraints.

### Components → [components.md](./rules/components.md)

- `s-page` is the root of every page. Use `size="large"` for data tables, omit for forms.
- Page actions use `s-page` slots (`primary-action`, `secondary-actions`, `breadcrumb-actions`) — NOT `s-title-bar`.
- `s-section` for content groups (cards). `s-box` for layout spacing only — never for visual grouping.
- `s-stack` always needs `direction` and `gap`. `s-grid` for multi-column with responsive props.
- One primary button per page context. Labels use `{verb}+{noun}` format (e.g., "Save settings", "Create product").
- Empty states are compositional (`s-box` + `s-heading` + `s-text` + `s-button`). No `s-empty-state` component exists.
- `s-modal` for dialogs. `s-app-window` for immersive editing (launched from body only, never nav).

### Forms → [forms.md](./rules/forms.md)

- All forms use `data-save-bar` attribute. Add `data-discard-confirmation` to prompt before discarding changes.
- Show inline errors after blur, not during typing. Use the `error` prop on input fields.
- Section forms with 5+ inputs into logical `s-section` groups. Never put large forms in modals.
- One entity per page — do not combine multiple resource types in a single form.
- Progressive disclosure — reveal fields conditionally based on user input (e.g., show "Custom URL" field only when "Custom" option is selected).
- Use `useFetcher()` for inline saves that should not trigger page navigation.

### Layout → [layout.md](./rules/layout.md)

- Single-column for forms and simple pages. Full-width (`size="large"`) for data tables and dashboards.
- Two-column layout: place secondary content in `slot="aside"` within `s-page`.
- 4px grid spacing system. Use tokens (`gap="400"` = 16px) not raw pixel values.
- Consistent density — do not mix loose and tight spacing on the same page.
- Stack layout: `s-stack direction="block"` for vertical, `direction="inline"` for horizontal.
- Grid layout: `s-grid columns="{{ xs: 1, sm: 2, lg: 3 }}"` for responsive multi-column.

### Visual Design → [visual-design.md](./rules/visual-design.md)

- Semantic tones only. Green = success (not enticement). Red = error/critical (not enticement). Yellow = warning.
- 4.5:1 contrast minimum (WCAG AA). Never rely on color alone — pair with icons or text.
- Typography hierarchy: `heading3xl` for page hero → `headingMd` for section titles → `bodyMd` for content → `bodySm` for metadata.
- Minimum 13px for body text, 12px for captions. Never go below 12px.
- Use `s-text tone="subdued"` for secondary information, not smaller font sizes.

### Navigation → [navigation.md](./rules/navigation.md)

- `s-app-nav` with `s-link` children. Max 7 top-level items. Use noun labels (e.g., "Orders", "Settings").
- Back navigation via `<s-link slot="breadcrumb-actions">` on `s-page`. Never duplicate the page heading as breadcrumb text.
- Tabs: use sparingly, never allow wrapping, only change content below the tab bar (never the page heading or actions).
- Deep linking: every distinct view must have its own URL. Do not hide content behind client-only state.

### Alerts → [alerts.md](./rules/alerts.md)

- Toast for quick success feedback (max 3 words, appears bottom-center via `shopify.toast.show("Product saved")`).
- `s-banner` for persistent messages that require attention or action. Place at the top of the relevant section.
- Inline errors near the source field. Use `error` prop on form inputs.
- No jargon, no scary language. Write errors as actionable guidance: "Enter a valid email" not "Invalid input error".
- Confirmations: use `s-modal` for destructive actions. State what will happen, not just "Are you sure?".

### UX Patterns → [ux-patterns.md](./rules/ux-patterns.md)

- Homepage: status overview + key metrics + actionable items (tasks, alerts) + support/docs footer.
- Onboarding: max 5 steps, always dismissible, show step position indicator (e.g., "Step 2 of 4").
- Marketing/promotional: dismissible, place at bottom of relevant page, once dismissed never show again for that merchant.
- Empty states: explain what the resource is, why it is empty, and provide a single primary action to create the first item.
- Bulk actions: appear in a sticky bar when items are selected in a table. Destructive bulk actions require confirmation.

## Component Quick Reference

Use these tables for fast lookup. When unsure which component to use, check this table first. For detailed props and usage, see [components.md](./rules/components.md) or use `search_docs_chunks` via MCP.

### Component Selection

Choose the most specific component available. Prefer semantic components (`s-section`, `s-badge`) over generic containers (`s-box`, `s-text`).



| Need | Component |
|---|---|
| Page container | `s-page` |
| Content group/card | `s-section` |
| Layout spacing | `s-box` |
| Vertical/horizontal stack | `s-stack` |
| Multi-column grid | `s-grid` |
| Primary action | `<s-button variant="primary">` |
| Secondary action | `<s-button>` |
| Destructive action | `<s-button variant="primary" tone="critical">` |
| Text input | `s-text-field` |
| Multi-line input | `s-text-area` |
| Dropdown | `s-select` |
| Toggle | `s-switch` |
| Multi-select | `s-checkbox` |
| Choice group | `s-choice-list` |
| Status label | `s-badge` |
| Notification | `s-banner` |
| Quick success | Toast via `shopify.toast.show()` |
| Loading spinner | `s-spinner` |
| Data table | `s-table` |
| Content divider | `s-divider` |
| Dialog | `s-modal` |
| Fullscreen editor | `s-app-window` |
| Link | `s-link` |
| Hover info | `s-tooltip` |
| Menu/dropdown actions | `s-menu` |
| Image | `s-image` / `s-thumbnail` |
| User identity | `s-avatar` |
| Icon | `s-icon` |
| Keyword tag | `s-chip` |
| Navigation | `s-app-nav` |

### Design Tokens

| Token | Scale |
|---|---|
| Spacing | `050`(2px) `100`(4px) `200`(8px) `300`(12px) `400`(16px) `500`(20px) `600`(24px) `800`(32px) `1000`(40px) `1600`(64px) |
| Typography | `heading3xl` `heading2xl` `headingXl` `headingLg` `headingMd` `headingSm` `bodyLg` `bodyMd` `bodySm` |
| Tones | `subdued` `success` `warning` `critical` `info` |
| Backgrounds | `bg-surface` `bg-surface-secondary` `bg-surface-tertiary` `bg-surface-success` `bg-surface-warning` `bg-surface-critical` |

Use spacing tokens on `gap`, `padding`, and `margin` props. Typography variants go on `s-text variant="..."` and `s-heading variant="..."`. Tones apply to `s-text`, `s-badge`, `s-banner`, and `s-button`.

Common spacing patterns:
- `gap="400"` (16px) — standard spacing between form fields and content blocks
- `gap="200"` (8px) — tight spacing within related groups (e.g., label + helper text)
- `gap="600"` (24px) — spacing between sections
- `padding="400"` (16px) — standard inner padding for custom containers

Common typography patterns:
- `s-page heading` — page title (rendered as `heading2xl` automatically)
- `s-section heading` — card/section title (rendered as `headingMd` automatically)
- `<s-heading variant="headingSm">` — sub-section titles within a card
- `<s-text variant="bodyMd">` — standard body text
- `<s-text variant="bodySm" tone="subdued">` — metadata, timestamps, helper text

## MCP Integration

If Shopify Dev MCP (`@shopify/dev-mcp`) is available, use these tools to validate and research:

| Tool | When to Use |
|---|---|
| `learn_shopify_api` | Call first before any Shopify API or GraphQL work |
| `validate_component_codeblocks` | After generating any Polaris Web Component code |
| `validate_graphql_codeblocks` | After writing GraphQL queries in loaders/actions |
| `fetch_full_docs` | When you need complete documentation for a specific component |
| `search_docs_chunks` | When searching for component props, patterns, or examples |

Always validate before presenting generated code to the user. If MCP is not available, manually review the generated code against the rules in this file.

Workflow with MCP:
1. Before writing any API code: call `learn_shopify_api` to get current API patterns.
2. After generating the page component: call `validate_component_codeblocks`.
3. After writing GraphQL in loaders/actions: call `validate_graphql_codeblocks`.
4. When unsure about a component: call `search_docs_chunks` with the component name.

See [mcp.md](./mcp.md) for setup instructions.

## SSR / React Hydration

Web Components in SSR require care to avoid hydration mismatches. The server renders HTML attributes, but inline JS handlers do not serialize — causing a mismatch when React hydrates on the client.

**Wrong — inline handler causes mismatch:**
```tsx
// BAD: hydration error — onClick does not exist in server-rendered HTML
<s-button onClick={() => doThing()}>Click</s-button>
```

**Correct — use `data-*` attributes + `useEffect`:**
```tsx
import { useEffect, useRef } from "react";

// GOOD: no hydration mismatch
export default function Page() {
  const btnRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const btn = btnRef.current;
    const handler = () => doThing();
    btn?.addEventListener("click", handler);
    return () => btn?.removeEventListener("click", handler);
  }, []);

  return <s-button ref={btnRef} data-action="do-thing">Click</s-button>;
}
```

Rules:
- Never attach inline event handlers (`onClick`, `onChange`, `onSubmit`) to `s-*` elements.
- Use `ref` or `data-*` attribute selectors to bind events in `useEffect`.
- For forms, rely on native `<form>` submission with `data-save-bar` — App Bridge handles the save bar UI automatically.
- Boolean attributes (`checked`, `disabled`) must match between server and client render.
- Avoid conditional rendering that differs between server and client (e.g., `window`-dependent checks). Use `useEffect` for client-only logic.
- When using `useFetcher()`, the form submission is handled by React Router — no manual event binding needed.

## References

### Rules (design constraints and requirements)

- [components.md](./rules/components.md) — component usage rules, slot patterns, prop constraints
- [forms.md](./rules/forms.md) — form structure, validation, save bar behavior
- [layout.md](./rules/layout.md) — page sizing, grid/stack patterns, spacing system
- [visual-design.md](./rules/visual-design.md) — color, typography, contrast, tone usage
- [navigation.md](./rules/navigation.md) — app nav, breadcrumbs, tabs, deep linking
- [alerts.md](./rules/alerts.md) — toast, banner, inline error, confirmation patterns
- [ux-patterns.md](./rules/ux-patterns.md) — homepage, onboarding, empty state, bulk action patterns

### Templates (starter code for each page type)

- [homepage.md](./templates/homepage.md) — dashboard with metrics, status, and actionable items
- [index-page.md](./templates/index-page.md) — resource list with table, filters, and bulk actions
- [details-page.md](./templates/details-page.md) — single resource view/edit with form and aside
- [settings-page.md](./templates/settings-page.md) — app configuration with sectioned form
- [onboarding.md](./templates/onboarding.md) — guided setup flow with step indicators

### MCP (tooling integration)

- [mcp.md](./mcp.md) — Shopify Dev MCP setup and tool reference
