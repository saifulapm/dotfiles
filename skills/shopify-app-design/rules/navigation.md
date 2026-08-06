# Navigation

## s-app-nav

Uses `s-link` children with `rel="home"` for the home item. Maximum 7 items (auto-truncate beyond 7). Use noun labels ("Products" not "Manage Products"). Don't duplicate nav items in the app body.

```html
<s-app-nav>
  <s-link href="/" rel="home">Dashboard</s-link>
  <s-link href="/products">Products</s-link>
  <s-link href="/orders">Orders</s-link>
  <s-link href="/customers">Customers</s-link>
  <s-link href="/settings">Settings</s-link>
</s-app-nav>
```

## Page Actions via s-page Slots

Page-level actions are defined using slots on `s-page`, **not** `s-title-bar`.

```html
<s-page heading="Products" size="large">
  <s-button slot="primary-action" variant="primary">Add product</s-button>
  <s-button slot="secondary-actions">Export</s-button>
  <s-link slot="breadcrumb-actions" href="/products">Products</s-link>
  <!-- page content -->
</s-page>
```

### Wrong

```html
<!-- DON'T use s-title-bar for page actions -->
<s-title-bar title="Products">
  <button variant="primary" slot="primary-action">Add product</button>
</s-title-bar>
```

`s-title-bar` is not the correct API for page actions. Always use `s-page` slots.

## Navigation Icon

- SVG format recommended (not required).
- Gray when inactive, green when active.
- Should resemble the App Store icon.
- Use 4px border radius.

## Page Titles

- Short and descriptive.
- One purpose per page.
- Don't duplicate the `s-page` heading elsewhere on the page.
- Action button labels follow the `{verb}+{noun}` pattern (e.g., "Add product", "Export list").

## Tab Navigation

- Use sparingly for secondary navigation within a page.
- Never allow tabs to wrap to multiple lines.
- Tabs should only change the content below them.
- Tabs must stay positionally stable (don't shift on selection).

## s-app-window

- Launch from the page body only, never from the nav.
- Prompt the merchant to save unsaved changes on exit.
- Use the `command`/`commandFor` pattern to trigger windows.

```html
<s-button commandFor="detail-window">Open details</s-button>
<s-app-window id="detail-window">
  <!-- window content -->
</s-app-window>
```

## App Homepage URL

- Must match the URL configured in the Partner Dashboard.
- Don't duplicate the homepage link in the nav menu (it's already the default entry point).

## Admin UI Extensions

- **Blocks** (<600px width): Compact UI embedded in admin surfaces.
- **Actions** (<1200px width): Triggered operations with more space.
- No promotional content in extensions.
- Blocks can trigger actions.
- Don't duplicate the same functionality between blocks and actions.
