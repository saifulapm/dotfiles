# Layout & Spacing

## Layout Types

### Single-Column Layout

Use for forms, settings, and detail pages.

```html
<!-- ✅ DO: Single-column for forms -->
<s-page heading="Settings">
  <s-section>
    <s-text-field label="Shop name" name="shopName" />
    <s-text-field label="Contact email" name="email" />
    <s-select label="Timezone" name="timezone">
      <option value="est">Eastern</option>
      <option value="pst">Pacific</option>
    </s-select>
  </s-section>
</s-page>
```

### Full-Width Layout

Use `size="large"` for data tables and wide content.

```html
<!-- ✅ DO: Full-width for data tables -->
<s-page heading="Orders" size="large">
  <s-section>
    <s-table>
      <!-- table content -->
    </s-table>
  </s-section>
</s-page>
```

### Two-Column Layout

Use `slot="aside"` for supplementary content alongside primary content.

```html
<!-- ✅ DO: Two-column with aside -->
<s-page heading="Edit product">
  <s-section>
    <s-text-field label="Title" name="title" />
    <s-text-area label="Description" name="description" />
  </s-section>

  <s-section slot="aside">
    <s-select label="Status" name="status">
      <option value="active">Active</option>
      <option value="draft">Draft</option>
    </s-select>
    <s-select label="Sales channels" name="channels">
      <option value="online">Online Store</option>
      <option value="pos">POS</option>
    </s-select>
  </s-section>
</s-page>
```

### Settings Layout

Narrow left column for descriptions, wider right column for controls.

```html
<!-- ✅ DO: Settings layout with description + controls -->
<s-page heading="Settings">
  <s-grid columns="1" md-columns="2" gap="400">
    <s-box gap="200">
      <s-text variant="headingMd">Store details</s-text>
      <s-text tone="subdued">These details are used across your store.</s-text>
    </s-box>
    <s-section>
      <s-text-field label="Shop name" name="shopName" />
      <s-email-field label="Contact email" name="email" />
    </s-section>
  </s-grid>

  <s-grid columns="1" md-columns="2" gap="400">
    <s-box gap="200">
      <s-text variant="headingMd">Address</s-text>
      <s-text tone="subdued">Used for shipping calculations and invoices.</s-text>
    </s-box>
    <s-section>
      <s-text-field label="Address" name="address" />
      <s-text-field label="City" name="city" />
    </s-section>
  </s-grid>
</s-page>
```

---

## 4px Grid Spacing

All spacing uses a 4px base grid with design tokens.

### Token Table

| Token | Value |
|-------|-------|
| `050`  | 2px   |
| `100`  | 4px   |
| `200`  | 8px   |
| `300`  | 12px  |
| `400`  | 16px  |
| `500`  | 20px  |
| `600`  | 24px  |
| `800`  | 32px  |
| `1000` | 40px  |
| `1600` | 64px  |

### Common Spacing Patterns

```html
<!-- ✅ DO: Use tokens for spacing -->

<!-- Form fields: gap="400" (16px) -->
<s-box gap="400">
  <s-text-field label="First name" name="firstName" />
  <s-text-field label="Last name" name="lastName" />
  <s-email-field label="Email" name="email" />
</s-box>

<!-- Between sections: gap="600" (24px) -->
<s-box gap="600">
  <s-section>
    <s-section heading="Basic info">...</s-section>
  </s-section>
  <s-section>
    <s-section heading="Pricing">...</s-section>
  </s-section>
</s-box>

<!-- Button groups: gap="300" (12px) -->
<s-box gap="300" direction="inline">
  <s-button variant="primary">Save</s-button>
  <s-button>Cancel</s-button>
</s-box>

<!-- Tight label + value: gap="200" (8px) -->
<s-box gap="200">
  <s-text variant="bodySm" tone="subdued">Status</s-text>
  <s-badge tone="success">Active</s-badge>
</s-box>
```

```html
<!-- ❌ DON'T: Hardcode spacing values -->
<div style="margin-bottom: 16px;">
  <s-text-field label="Name" name="name" />
</div>
<div style="padding: 24px; gap: 12px;">
  <s-button>Save</s-button>
  <s-button>Cancel</s-button>
</div>
```

---

## Scale System

The scale system works middle-out from `small-300` to `large-300`, with `base` as the default.

| Scale Token   | Shorthand   |
|---------------|-------------|
| `small-300`   |             |
| `small-200`   |             |
| `small-100`   | `small`     |
| `base`        | (default)   |
| `large-100`   | `large`     |
| `large-200`   |             |
| `large-300`   |             |

`small` is shorthand for `small-100`. `large` is shorthand for `large-100`.

---

## Responsive Design

Mobile-first approach. Use `s-grid` with responsive column props.

```html
<!-- ✅ DO: Responsive grid with breakpoint columns -->
<s-grid columns="1" md-columns="2" lg-columns="3" gap="400">
  <s-section>
    <s-text variant="headingMd">Total orders</s-text>
    <s-text variant="heading2xl">1,234</s-text>
  </s-section>
  <s-section>
    <s-text variant="headingMd">Revenue</s-text>
    <s-text variant="heading2xl">$45,678</s-text>
  </s-section>
  <s-section>
    <s-text variant="headingMd">Conversion</s-text>
    <s-text variant="heading2xl">3.2%</s-text>
  </s-section>
</s-grid>
```

```html
<!-- ❌ DON'T: Fixed columns that break on mobile -->
<s-grid columns="3" gap="400">
  <s-section>Total orders</s-section>
  <s-section>Revenue</s-section>
  <s-section>Conversion</s-section>
</s-grid>
```

### Container Queries

Use `s-query-container` for component-level responsiveness.

```html
<!-- ✅ DO: Container queries for component-level layout -->
<s-query-container>
  <s-box direction="inline" gap="400"
    query="(min-width: 400px)"
    query-direction="block"
  >
    <s-thumbnail source="product.jpg" />
    <s-box gap="200">
      <s-text variant="headingMd">Product title</s-text>
      <s-text tone="subdued">$29.99</s-text>
    </s-box>
  </s-box>
</s-query-container>
```

---

## Density

Keep density consistent within a page. Low density for forms, high density for data tables.

```html
<!-- ✅ DO: Consistent low density for a form page -->
<s-page heading="Product details">
  <s-section padding="600">
    <s-box gap="400">
      <s-text-field label="Title" name="title" />
      <s-text-area label="Description" name="description" />
      <s-money-field label="Price" name="price" />
    </s-box>
  </s-section>
</s-page>
```

```html
<!-- ✅ DO: Consistent high density for a data table -->
<s-page heading="Orders" size="large">
  <s-section padding="0">
    <s-data-table condensed>
      <!-- Dense rows with compact spacing -->
    </s-data-table>
  </s-section>
</s-page>
```

```html
<!-- ❌ DON'T: Mix density on the same page -->
<s-page heading="Dashboard">
  <s-section padding="800">
    <s-text-field label="Search" name="search" />
  </s-section>
  <s-section padding="0">
    <s-data-table condensed>...</s-data-table>
  </s-section>
  <s-section padding="1000">
    <s-text>Some loose text here</s-text>
  </s-section>
</s-page>
```

---

## Content Containers

Text lives in containers. Use `s-section` for semantic grouping. One primary action per card. Tables use secondary-style actions.

```html
<!-- ✅ DO: Text in containers with semantic grouping -->
<s-section>
  <s-section heading="Customer">
    <s-box gap="200">
      <s-text>Jane Doe</s-text>
      <s-text tone="subdued">jane@example.com</s-text>
    </s-box>
  </s-section>
  <s-section heading="Shipping address">
    <s-box gap="200">
      <s-text>123 Main St</s-text>
      <s-text>New York, NY 10001</s-text>
    </s-box>
  </s-section>
</s-section>
```

```html
<!-- ❌ DON'T: Bare text outside containers -->
<s-page heading="Customer">
  <s-text>Jane Doe</s-text>
  <s-text>jane@example.com</s-text>
  <s-text>123 Main St</s-text>
</s-page>
```
