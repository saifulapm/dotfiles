# Alerts & Feedback

## Alert Types

- **Task alerts:** Merchant-initiated, direct feedback on an action the merchant just took.
- **System alerts:** App-initiated, background status updates about things happening outside the merchant's immediate workflow.

## Banner

Page-level persistent alerts. Use `s-banner` with the appropriate `tone`.

| Tone | Color | Usage | Dismissible |
|------|-------|-------|-------------|
| `info` | Blue | General information, tips | Yes |
| `success` | Green | Delayed or persistent success confirmations | Yes |
| `warning` | Yellow | Upcoming issues, pair with icon | Case-by-case |
| `critical` | Red | Errors requiring action, explain the problem and how to fix it | No (until resolved) |

Dismissed banners must not reappear in the same session.

```html
<!-- Warning banner with action -->
<s-banner tone="warning">
  <s-text>Your trial ends in 3 days.</s-text>
  <s-button slot="secondary-actions" variant="plain">Upgrade now</s-button>
</s-banner>
```

```html
<!-- Critical banner explaining the problem and fix -->
<s-banner tone="critical">
  <s-text>Payment failed. Update your billing information to continue using the app.</s-text>
  <s-button slot="secondary-actions" variant="plain">Update billing</s-button>
</s-banner>
```

### Right

```html
<!-- Immediate success: use toast -->
<script>shopify.toast.show('Product saved')</script>

<!-- Delayed/persistent success: use banner -->
<s-banner tone="success">
  <s-text>Import complete. 42 products added.</s-text>
</s-banner>
```

### Wrong

```html
<!-- DON'T use banner for immediate success feedback -->
<s-banner tone="success">
  <s-text>Settings saved</s-text>
</s-banner>

<!-- DON'T use toast for messages that need a CTA -->
<script>shopify.toast.show('Trial ends in 3 days. Upgrade now.')</script>
```

## Toast

Quick success confirmations only. Shown bottom-center.

- Maximum 3 words (e.g., "Settings saved", "Product added").
- Optional undo action.
- Triggered via `shopify.toast.show()`.

```js
// Simple toast
shopify.toast.show('Settings saved');

// Toast with undo
shopify.toast.show('Product deleted', { action: { content: 'Undo' } });
```

### When to use toast vs banner

- **Toast:** Immediate success after a merchant action, no further action needed.
- **Banner:** Delayed results, persistent status, or when a CTA is required.

## Inline Errors

Use the `error` prop on form fields for field-level validation.

```html
<!-- Right: show error after blur -->
<s-text-field
  label="Email"
  type="email"
  error="Enter a valid email address"
></s-text-field>
```

### Right

```html
<!-- Error appears after the merchant leaves the field (blur) -->
<s-text-field
  label="Store name"
  error="Store name is required"
></s-text-field>
```

### Wrong

```html
<!-- DON'T show errors while the merchant is still typing -->
<!-- DON'T place field errors inside modals for non-modal fields -->
<!-- DON'T use jargon: "Error 422: Unprocessable entity" -->
<!-- DON'T use scary language: "CRITICAL FAILURE" -->
<!-- DON'T use humor: "Oops! Something went wrong :(" -->
```

### Error writing guidelines

- No jargon or technical codes.
- No scary or alarming language.
- No humor or casual tone.
- Always offer a path forward: tell the merchant what to do next.
- Place errors near the source of the problem.
- Never show field-level errors inside modals unless the field is inside that modal.
