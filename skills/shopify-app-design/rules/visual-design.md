# Visual Design

## Semantic Tones

Use semantic tones to convey meaning. Available tones: `critical`, `success`, `warning`, `subdued`, `info`.

```html
<!-- s-text with tones -->
<s-text tone="critical">Payment failed</s-text>
<s-text tone="success">Order fulfilled</s-text>
<s-text tone="warning">Low inventory</s-text>
<s-text tone="subdued">Last updated 3 hours ago</s-text>
<s-text tone="info">Shipping rates calculated at checkout</s-text>

<!-- s-badge with tones -->
<s-badge tone="critical">Action required</s-badge>
<s-badge tone="success">Active</s-badge>
<s-badge tone="warning">Pending</s-badge>
<s-badge tone="info">Draft</s-badge>

<!-- s-banner with tones -->
<s-banner tone="critical">
  Your payment method has expired. Update it to continue selling.
</s-banner>
<s-banner tone="success">
  Product successfully published to Online Store.
</s-banner>
<s-banner tone="warning">
  3 products have low inventory. Review stock levels.
</s-banner>
<s-banner tone="info">
  A new shipping carrier integration is available.
</s-banner>
```

---

## Status Colors with Anti-patterns

### Green = Success

```html
<!-- ✅ DO: Green for success states -->
<s-badge tone="success">Active</s-badge>
<s-badge tone="success">Fulfilled</s-badge>
<s-badge tone="success">Paid</s-badge>
```

```html
<!-- ❌ DON'T: Green for enticement or promotion -->
<s-badge tone="success">New feature!</s-badge>
<s-badge tone="success">Recommended</s-badge>
<s-badge tone="success">Try now</s-badge>
```

### Yellow = Paused / Incomplete

```html
<!-- ✅ DO: Yellow for paused or incomplete states -->
<s-badge tone="warning">Pending review</s-badge>
<s-badge tone="warning">Partially fulfilled</s-badge>
<s-badge tone="warning">Setup incomplete</s-badge>
```

### Orange = In Progress / Attention

```html
<!-- ✅ DO: Orange for attention-needed states -->
<s-badge tone="attention">In progress</s-badge>
<s-badge tone="attention">Action needed</s-badge>
```

```html
<!-- ❌ DON'T: Orange for marketing or "coming soon" -->
<s-badge tone="attention">Coming soon</s-badge>
<s-badge tone="attention">Hot deal</s-badge>
```

### Red = Error / Blocked

```html
<!-- ✅ DO: Red for errors and blocked states -->
<s-badge tone="critical">Failed</s-badge>
<s-badge tone="critical">Expired</s-badge>
<s-badge tone="critical">Overdue</s-badge>
```

```html
<!-- ❌ DON'T: Red for enticement or urgency marketing -->
<s-badge tone="critical">Limited time!</s-badge>
<s-badge tone="critical">Don't miss out</s-badge>
<s-badge tone="critical">Sale</s-badge>
```

---

## Background Tokens

Use semantic background tokens, never hardcoded colors.

```html
<!-- ✅ DO: Use background tokens -->
<s-box background="bg-surface">Default surface</s-box>
<s-box background="bg-surface-secondary">Secondary grouping</s-box>
<s-box background="bg-surface-tertiary">Tertiary grouping</s-box>
<s-box background="bg-surface-success">Success context</s-box>
<s-box background="bg-surface-warning">Warning context</s-box>
<s-box background="bg-surface-critical">Critical context</s-box>
```

```html
<!-- ❌ DON'T: Hardcode background colors -->
<div style="background-color: #f1f1f1;">Secondary area</div>
<div style="background-color: #e6f9e6;">Success area</div>
<div style="background: rgb(255, 240, 240);">Error area</div>
```

---

## Border Tokens

```html
<!-- ✅ DO: Use border tokens -->
<s-box border="base">Default border</s-box>
<s-box border="success">Success border</s-box>
<s-box border="warning">Warning border</s-box>
<s-box border="critical">Critical border</s-box>
```

```html
<!-- ❌ DON'T: Hardcode border styles -->
<div style="border: 1px solid #ccc;">Default</div>
<div style="border: 1px solid green;">Success</div>
<div style="border: 2px solid red;">Error</div>
```

---

## Typography Hierarchy

| Variant       | Use For                                |
|---------------|----------------------------------------|
| `heading3xl`  | Page-level metrics, large data points  |
| `heading2xl`  | Page titles, major section headers     |
| `headingXl`   | Card titles, primary section headers   |
| `headingLg`   | Sub-section headers                    |
| `headingMd`   | Card sub-headers, group labels         |
| `headingSm`   | Minor headings, label-like headers     |
| `bodyLg`      | Emphasized body text, lead paragraphs  |
| `bodyMd`      | Default body text                      |
| `bodySm`      | Secondary info, help text              |

**Minimum sizes:** 13px for headings and body text, 12px for captions.

### Semantic HTML with `as` Prop

```html
<!-- ✅ DO: Use `as` prop for semantic HTML -->
<s-text variant="headingXl" as="h1">Products</s-text>
<s-text variant="headingLg" as="h2">Inventory</s-text>
<s-text variant="headingMd" as="h3">Stock levels</s-text>
<s-text variant="bodyMd" as="p">Your inventory is up to date.</s-text>
```

```html
<!-- ❌ DON'T: Visual hierarchy without semantic structure -->
<s-text variant="headingXl">Products</s-text>
<s-text variant="headingLg">Inventory</s-text>
<s-text variant="headingMd">Stock levels</s-text>
```

### Underlines

```html
<!-- ❌ DON'T: Underline non-link text (resembles links) -->
<s-text style="text-decoration: underline;">Important note</s-text>
```

---

## Accessibility

### Color Contrast

Minimum 4.5:1 contrast ratio (WCAG AA).

```html
<!-- ✅ DO: Use semantic tokens that guarantee contrast -->
<s-text>Default text on default surface</s-text>
<s-text tone="subdued">Subdued text for secondary info</s-text>
<s-text tone="critical">Error message with sufficient contrast</s-text>
```

```html
<!-- ❌ DON'T: Low-contrast hardcoded colors -->
<span style="color: #aaa; background: #fff;">Hard to read</span>
<span style="color: #999;">Too light for body text</span>
```

### Never Rely on Color Alone

Always pair color with text or icons.

```html
<!-- ✅ DO: Color + text/icon for status -->
<s-badge tone="critical">
  <s-icon source="alert" />
  Payment failed
</s-badge>

<s-text tone="success">
  <s-icon source="check" /> Order fulfilled
</s-text>
```

```html
<!-- ❌ DON'T: Color as the only indicator -->
<s-box background="bg-surface-critical"></s-box>
<!-- User has no idea what the red box means without text -->

<span style="color: green;">●</span>
<span style="color: red;">●</span>
<!-- Indistinguishable for colorblind users -->
```

### Keyboard Navigation & ARIA

```html
<!-- ✅ DO: ARIA labels on icon-only buttons -->
<s-button icon="delete" accessibilityLabel="Delete product" />
<s-button icon="edit" accessibilityLabel="Edit customer details" />
```

```html
<!-- ❌ DON'T: Icon buttons without labels -->
<s-button icon="delete" />
<s-button icon="edit" />
```

---

## App Icon Requirements

| Requirement        | Specification                              |
|--------------------|--------------------------------------------|
| Size               | 1200 x 1200 px                             |
| Format             | PNG or JPG                                 |
| Corners            | No rounded corners (Shopify applies them)  |
| Icon fill area     | 10/16ths to 12/16ths of the canvas         |
| Margin             | Minimum 1/16th on all sides                |
| Shopify branding   | Not allowed                                |

```text
+------------------------------------------+
|  1/16 margin                             |
|  +------------------------------------+  |
|  |                                    |  |
|  |     Icon fills 10/16 - 12/16      |  |
|  |     of the total canvas           |  |
|  |                                    |  |
|  +------------------------------------+  |
|  1/16 margin                             |
+------------------------------------------+
```

```text
✅ Custom brand icon, clean design, no rounded corners in source file
✅ Centered icon with adequate margin
✅ High-resolution 1200x1200 PNG

❌ Shopify logo or bag icon in your app icon
❌ Pre-rounded corners in the source file
❌ Icon touching the edges with no margin
❌ Low-resolution or non-square image
```

---

## Tokens vs Hardcoded Styles

```html
<!-- ✅ DO: Use design tokens throughout -->
<s-box
  padding="400"
  background="bg-surface-secondary"
  border="base"
  gap="300"
>
  <s-text variant="headingMd" tone="subdued">Order summary</s-text>
  <s-text variant="bodyMd">3 items</s-text>
  <s-badge tone="success">Paid</s-badge>
</s-box>
```

```html
<!-- ❌ DON'T: Inline styles and hardcoded values -->
<div
  style="padding: 16px; background: #f6f6f7; border: 1px solid #ddd; display: flex; flex-direction: column; gap: 12px;"
>
  <span style="font-size: 14px; font-weight: 600; color: #6d7175;">Order summary</span>
  <span style="font-size: 14px;">3 items</span>
  <span style="background: #aee9d1; padding: 2px 8px; border-radius: 4px; color: #1a5c38;">Paid</span>
</div>
```
