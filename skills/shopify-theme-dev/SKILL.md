---
name: shopify-theme-dev
description: Build premium Shopify theme components (sections, blocks, snippets) following modern patterns. Triggers when creating/editing Liquid files, working with theme sections/blocks/snippets, or building Shopify theme features like product pages, collection grids, headers, carts, slideshows, hero banners, or any storefront component.
---

# Shopify Theme Development

Build premium, multi-purpose Shopify theme components for the Nova theme architecture.

## Architecture

| Layer | Stack |
|---|---|
| CSS | TailwindCSS v4 only. Utility classes in Liquid markup. Compiled via Vite to `assets/theme.css`. **Never use `{% stylesheet %}`** |
| JS | All Vite-bundled TypeScript. `vendor.min.js` + `theme.js` via importmap. **Never use `{% javascript %}`** |
| Design | shadcn-inspired: CSS variables in `tailwind.css`, TailwindCSS utilities, Motion.js animations |
| Components | TypeScript in `src/components/`, Web Components for interactivity |
| Liquid | Markup only (HTML + Liquid + TailwindCSS classes) + `{% schema %}` + `{% doc %}` |

```
blocks/        # Reusable theme blocks
sections/      # Full-width page sections
snippets/      # Reusable Liquid fragments ({% render %})
src/components/ # TypeScript modules & Web Components
```

### Import Pattern

```html
<!-- layout/theme.liquid -->
<script type="importmap">
  { "imports": { "vendor": "{{ 'vendor.min.js' | asset_url }}" } }
</script>
```

```typescript
// src/components/example.ts
import { animate, stagger } from 'vendor'
```

## Core Rules

### Never Do
- Never use `{% stylesheet %}` or `{% javascript %}` tags in any Liquid file
- Never hardcode URLs - use `routes` object (`{{ routes.cart_url }}`, not `/cart`)
- Never hardcode text - use translation keys (`{{ 'key' | t }}`)
- Never truncate `product.title` or `collection.title`
- Never use `| default:` with boolean parameters (Liquid treats `false` as blank). Use string values instead: `'lazy'`/`'eager'`
- Never store raw TailwindCSS classes in schema setting values. Store semantic tokens (`"small"`, `"medium"`) and map to classes in Liquid

### Always Do
- Always add `{{ block.shopify_attributes }}` on block root elements (when using `"tag": null`)
- Always add `{{ section.shopify_attributes }}` on section root elements
- Always use `{% doc %}` with `@param` and `@example` on blocks (static render) and snippets
- Always use `alt` on images: `alt: image.alt`
- Always include `{ "type": "@theme" }` and `{ "type": "@app" }` in section block arrays
- Always use translation keys (`t:` prefix) for schema labels
- Always use sentence case and American English (color, center, gray)
- Always update locale files when creating new components

## Block Pattern

Blocks live in `/blocks/`. They are reusable across sections.

```liquid
{% doc %}
  Renders a heading with configurable level and size.

  @param {string} [tag] - Override heading tag (from static render)

  @example
  {% content_for 'block', type: 'heading', id: 'heading' %}
{% enddoc %}

{%- liquid
  assign heading_tag = tag | default: block.settings.heading_level
  case block.settings.size
    when 'small'
      assign size_class = 'text-2xl md:text-3xl'
    when 'medium'
      assign size_class = 'text-3xl md:text-5xl'
    when 'large'
      assign size_class = 'text-4xl md:text-6xl'
  endcase
-%}

<{{ heading_tag }}
  class="font-heading tracking-tight {{ size_class }}"
  {{ block.shopify_attributes }}
>
  {{ block.settings.text }}
</{{ heading_tag }}>

{% schema %}
{
  "name": "t:blocks.heading.name",
  "tag": null,
  "settings": [
    {
      "type": "text",
      "id": "text",
      "label": "t:labels.heading",
      "default": "Heading"
    },
    {
      "type": "select",
      "id": "heading_level",
      "label": "t:labels.heading_level",
      "options": [
        { "value": "h1", "label": "H1" },
        { "value": "h2", "label": "H2" },
        { "value": "h3", "label": "H3" }
      ],
      "default": "h2"
    },
    {
      "type": "select",
      "id": "size",
      "label": "t:labels.size",
      "options": [
        { "value": "small", "label": "t:options.small" },
        { "value": "medium", "label": "t:options.medium" },
        { "value": "large", "label": "t:options.large" }
      ],
      "default": "medium"
    }
  ],
  "presets": [{ "name": "t:blocks.heading.name" }]
}
{% endschema %}
```

### Block Rules

| Rule | Detail |
|---|---|
| `"tag": null` | Custom wrapper control. Must add `{{ block.shopify_attributes }}` manually on root element |
| Omit `"tag"` | Default `<div>` wrapper. Shopify adds `shopify_attributes` automatically |
| Presets | Required for blocks to appear in editor block picker |
| Private blocks | Prefix with `_` (e.g., `_slide.liquid`). Auto-excluded from `@theme` picker. Sections must reference explicitly: `{ "type": "_slide" }` |
| Nesting | Add `"blocks": [{ "type": "@theme" }]` to accept child blocks. Max 8 levels deep |
| Categories | Use `"category"` in presets to group related presets in block picker |
| Recommended | List specific types alongside `@theme` to highlight in picker: `[{ "type": "@theme" }, { "type": "heading" }]` |

### Static vs Dynamic Blocks

```liquid
{% content_for 'blocks' %}
```
Dynamic blocks: merchant adds/removes/reorders in editor. Rendered where this tag appears.

```liquid
{% content_for 'block', type: 'controls', id: 'slideshow-controls' %}
```
Static blocks: fixed position, can't be deleted/reordered by merchant. Rendered exactly where placed. Independent from dynamic blocks. Can pass data: `{% content_for 'block', type: 'slide', id: 'slide-1', color: '#111' %}`

### Conditional Settings

Use `visible_if` to show/hide settings based on other settings:
```json
{
  "type": "range",
  "id": "border_radius",
  "label": "t:labels.border_radius",
  "visible_if": "{{ block.settings.show_border }}",
  "min": 0,
  "max": 20,
  "default": 4,
  "unit": "px"
}
```

## Section Pattern

Sections live in `/sections/`. They are full-width page components.

```liquid
<section class="py-12 md:py-20 bg-background text-foreground" {{ section.shopify_attributes }}>
  <div class="mx-auto max-w-screen-xl px-4 md:px-6">
    {% content_for 'blocks' %}
  </div>
</section>

{% schema %}
{
  "name": "t:sections.featured_collection.name",
  "blocks": [
    { "type": "@theme" },
    { "type": "@app" }
  ],
  "settings": [
    {
      "type": "header",
      "content": "t:labels.layout"
    },
    {
      "type": "collection",
      "id": "collection",
      "label": "t:labels.collection"
    }
  ],
  "disabled_on": {
    "groups": ["header", "footer"]
  },
  "presets": [
    {
      "name": "t:sections.featured_collection.name",
      "blocks": [
        { "type": "heading", "settings": { "text": "Featured collection" } }
      ]
    }
  ]
}
{% endschema %}
```

### Section Rules
- `{{ section.shopify_attributes }}` on root HTML element
- `{ "type": "@theme" }` + `{ "type": "@app" }` in blocks array
- Use `disabled_on` to exclude from header/footer groups
- Presets can pre-populate child blocks with default settings
- Section groups (`header-group.json`, `footer-group.json`) define header/footer
- Use `"type": "header"` settings to organize settings in editor

## Snippet Pattern

Snippets live in `/snippets/`. They are reusable fragments rendered with `{% render %}`.

```liquid
{% doc %}
  Renders a product card with image, title, price.

  @param {product} product - The product to render
  @param {string} [class] - Additional CSS classes
  @param {string} [loading] - Image loading: 'lazy' or 'eager' (default: 'lazy')

  @example
  {% render 'product-card', product: product %}
  {% render 'product-card', product: product, loading: 'eager' %}
{% enddoc %}

{%- liquid
  assign loading = loading | default: 'lazy'
-%}

<div class="group relative {{ class }}">
  <a href="{{ product.url }}" class="block overflow-hidden rounded-lg">
    {{ product.featured_image
      | image_url: width: 1200
      | image_tag:
          loading: loading,
          alt: product.featured_image.alt,
          class: 'w-full transition-transform duration-300 group-hover:scale-105',
          widths: '240, 352, 832, 1200',
          sizes: '(min-width: 1024px) 25vw, (min-width: 768px) 33vw, 50vw'
    }}
  </a>
  <h3 class="mt-3 text-sm font-medium">
    <a href="{{ product.url }}">{{ product.title }}</a>
  </h3>
  <p class="mt-1 text-sm text-muted-foreground">
    {{ product.price | money }}
  </p>
</div>
```

### Snippet Rules
- `{% doc %}` required with typed `@param` and `@example`
- No `{% schema %}` (snippets don't have schemas)
- Accept parameters via `{% render 'snippet', param: value %}`
- Snippets cannot access parent scope variables (only passed params + global objects)
- Use `| default:` for optional string/object params. Avoid for booleans.
- Always specify `widths` and `sizes` on `image_tag`
- Always pass `alt` to `image_tag`

## Translation Pattern

### Two locale files

**`locales/en.default.json`** - Storefront runtime text:
```json
{
  "general": {
    "accessibility": {
      "skip_to_content": "Skip to content",
      "close": "Close"
    }
  },
  "products": {
    "add_to_cart": "Add to cart",
    "sold_out": "Sold out",
    "price": {
      "from": "From {{ price }}"
    }
  }
}
```

Usage: `{{ 'products.add_to_cart' | t }}`
With variables: `{{ 'products.price.from' | t: price: product.price | money }}`

**`locales/en.default.schema.json`** - Editor UI labels:
```json
{
  "labels": {
    "heading": "Heading",
    "heading_level": "Heading level",
    "collection": "Collection",
    "layout": "Layout",
    "size": "Size"
  },
  "options": {
    "small": "Small",
    "medium": "Medium",
    "large": "Large"
  },
  "sections": {
    "featured_collection": { "name": "Featured collection" }
  },
  "blocks": {
    "heading": { "name": "Heading" }
  }
}
```

Usage in schema: `"label": "t:labels.heading"`, `"name": "t:blocks.heading.name"`

### Translation Rules
- Max 3 levels deep, snake_case keys
- Sentence case for all text (not Title Case)
- American English (color, center, gray, canceled)
- No Lorem Ipsum as defaults
- Update both locale files when creating components

## Performance

| Pattern | When |
|---|---|
| `loading: 'eager', fetchpriority: 'high'` | Above-fold hero images (first section) |
| `loading: 'lazy', fetchpriority: 'low'` | Everything below fold |
| `widths: '240, 352, 832, 1200, 1600, 1920'` | Responsive srcset on all images |
| `sizes: '(min-width: 1024px) 25vw, 50vw'` | Match actual rendered size |
| Deferred media | Videos: poster image + `<template>` for lazy content |
| CSS/HTML first | Use CSS solutions before JavaScript |

### Responsive Image Example
```liquid
{{ image
  | image_url: width: 1920
  | image_tag:
      loading: 'lazy',
      alt: image.alt,
      widths: '240, 352, 832, 1200, 1600, 1920',
      sizes: '(min-width: 1024px) 50vw, 100vw'
}}
```

## SEO

- `{{ product | structured_data }}` in product sections
- `{{ article | structured_data }}` in article sections
- Meta tags snippet for Open Graph + Twitter cards
- `<html lang="{{ request.locale.iso_code }}">`
- Use `routes` object for all URLs

## Accessibility (WCAG 2.1)

- Semantic HTML: `<nav>`, `<article>`, `<section>`, `<details>`, `<dialog>`
- `alt` on all images
- Form `<label>` with matching `for` attribute
- Visible focus states on interactive elements
- Color contrast: 4.5:1 body text, 3:1 large text
- Touch targets: minimum 24x24 CSS pixels
- Keyboard accessible (all interactive elements)

## Theme Store Compliance Quick Reference

### Product Page
- Title (not truncated), price, compare-at, unit price as individual blocks
- `selected_or_first_available_variant` for default
- Variant options as separate selectors
- Add to cart disabled for unavailable variants
- `{{ product | structured_data }}`
- Accelerated checkout: `{{ form | payment_button }}` inside `{% form 'product' %}` (default on)
- Pickup availability, Shop Pay Installments
- Product recommendations (related + complementary)
- `@app` blocks supported

### Collection Page
- Title, description, image (not truncated)
- Grid handles varying aspect ratios
- Pagination, sort, faceted search
- Empty collection message
- `price_varies` with `price_min`/`price_max`

### Cart Page
- Line items: title, unit_price, image, final_price, quantity, options
- `cart.total_price`, `cart.taxes_included`
- Checkout button, quantity change per line item
- Cart notes, selling plans, accelerated checkout

### General
- Use `routes` object for URLs
- `{{ block.shopify_attributes }}` / `{{ section.shopify_attributes }}`
- Lighthouse: performance >= 60, accessibility >= 90
- No minified CSS/JS (except vendor/third-party)
- American English, sentence case

### Validation
- Optionally run `validate_theme` via Shopify MCP to verify Liquid syntax
- Run `shopify theme check` before Theme Store submission
