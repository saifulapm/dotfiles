---
name: shopify-theme-store-requirements
description: Use when building, reviewing, or validating a Shopify theme for Theme Store submission. Triggers on creating templates, sections, blocks, settings, product pages, collection pages, cart pages, or any Shopify theme Liquid code. Also use when auditing an existing theme for compliance before submission.
---

# Shopify Theme Store Requirements

## Overview

Complete reference for all Shopify Theme Store submission requirements. Every requirement must be met or the theme will be rejected. Use this as a checklist during development and before submission.

**Source:** [Shopify Theme Store Requirements](https://shopify.dev/docs/storefronts/themes/store/requirements)

**Approved codebase:** [Shopify Skeleton Theme](https://github.com/shopify/skeleton-theme) is the ONLY approved starter. Dawn/Horizon-based themes are NOT eligible.

## When to Use

- Building any new Shopify theme template, section, or block
- Creating or modifying theme settings (settings_schema.json, section schemas)
- Writing Liquid code for product, collection, cart, or any storefront page
- Reviewing a theme before Theme Store submission
- Naming sections, presets, settings, or the theme itself
- Setting up a demo store for the theme

## Required Templates

Every theme MUST include these files:

| File | Format |
|------|--------|
| `theme.liquid` | Layout |
| `404.json` | JSON template |
| `article.json` | JSON template |
| `blog.json` | JSON template |
| `cart.json` | JSON template |
| `collection.json` | JSON template |
| `index.json` | JSON template |
| `list-collections.json` | JSON template |
| `page.json` | JSON template |
| `page.contact.json` | JSON template |
| `password.json` | JSON template |
| `product.json` | JSON template |
| `search.json` | JSON template |
| `gift_card.liquid` | Liquid template |
| `settings_data.json` | Config |
| `settings_schema.json` | Config |

**Do NOT include:** `config/markets.json`, `robots.txt.liquid`

## Required Features Checklist

Every theme must support ALL of these:

- [ ] **Sections Everywhere** - All templates use JSON (OS 2.0)
- [ ] **Custom Liquid section** - with `liquid` type setting, available on all section-supporting templates
- [ ] **Custom Liquid blocks** - in sections where app blocks are supported
- [ ] **App blocks** (`@app`) - in main product section and featured product section
- [ ] **Section groups** - Header and footer rendered within section groups
- [ ] **Product blocks** - Price, vendor, description etc. as individual blocks in main product section
- [ ] **Discounts** - Display on cart, checkout, and order templates
- [ ] **Accelerated checkout buttons** - Product page + Cart page (enabled by default, don't modify colors)
- [ ] **Faceted search filtering** - Collection pages + Search pages
- [ ] **Gift cards** - `gift_card.liquid` template with recipient support (`form.email`, `form.name`, `form.message`, `send_on`)
- [ ] **Image focal points** - Support `image_picker` focal points
- [ ] **Social sharing images** - `page_image` object
- [ ] **Country selection** - Currency/country selector following UX guidelines
- [ ] **Language selection** - Language selector following UX guidelines
- [ ] **Multi-level menus** - Nested dropdown menus
- [ ] **Newsletter forms** - Email signup
- [ ] **Pickup availability** - On product page
- [ ] **Related product recommendations** - On product pages
- [ ] **Complementary product recommendations** - On product pages
- [ ] **Rich product media** - 3D models, embedded videos, YouTube/Vimeo
- [ ] **Predictive search** - Search template + predictive search
- [ ] **Selling plans** - Cart page + Customer page
- [ ] **Shop Pay Installments** - On product page
- [ ] **Unit pricing** - Collection, Product, Cart, Customer pages
- [ ] **Variant images** - Show when variant selected
- [ ] **Product swatches** - Support `swatch.image` and `swatch.color`
- [ ] **Follow on Shop** - `login_button` filter (don't modify colors)

## Page Requirements Quick Reference

### Product Page
- `product.title` (not truncated), `variant.price`, `variant.unit_price`, compare-at price, `product.description`, option names/values
- All images viewable, variant images on selection, different ratios don't break layout
- `cart.taxes_included` indicator
- Variant options split into separate selectors
- Quantity selector
- Add to cart button (disabled/replaced for unavailable variants)
- Price/compare-at/sold-out callback on variant change
- First available variant loads by default (`selected_or_first_available_variant`)
- Product recommendations, rich media, accelerated checkout (default on), pickup availability, Shop Pay Installments

### Collection Page
- `collection.title` (not truncated), `collection.description`, `collection.image`
- Product grid/list: `product.title` (not truncated, links to `product.url`), `product.price`, `product.images`, `variant.unit_price`, at least one media
- Grid handles varying aspect ratios
- Sale badge or `compare_at_price_max` when appropriate
- Sort functionality
- Empty collection message
- `product.price_varies` with `price_min`/`price_max` range
- Pagination or lazy loading

### Cart Page
- Line item: `title`, `unit_price`, `image`, `final_price`, `quantity`, `options_with_values`
- `cart.total_price` visible
- `cart.taxes_included` indicator
- Checkout button submitting cart form
- Refresh all line items on quantity update
- Quantity change per line item
- Cart notes, selling plans, automatic discounts, accelerated checkout (default on)

### Blog Page
- `blog.title`
- Each article: `article.title` (not truncated, links to `article.url`), `article.image`, `article.excerpt_or_content` (NOT `article.content`)
- Pagination or lazy loading

### Article Page
- `article.title` (not truncated), `article.comments`, `article.published_at` (NOT `article.created_at`)
- Paginated comments
- Comments work without moderation, proper success/error messages

### Search Page
- No results message
- Return different object types (products, blogs, pages) using `object_type`
- Pagination or lazy loading

### 404 Page
- Clear "page not found" message
- Options to proceed (search bar or home page link)

### Gift Card Page
- Apple Wallet support
- Gift card code displayed
- QR code (minimum 120px x 120px)
- Logo or `shop.name`

### Password Page
- Logo or `shop.name`
- `shop.password_message`
- Storefront password form

### Customer Page
- `line_item.unit_price`
- Selling plans, unit pricing

### Collection List Page
- `collection.title` (not truncated)
- `collection.featured_image` (falls back to first product image)
- Pagination or lazy loading

### Page Template
- `page.title`, `page.content`
- Alternate contact form template

## Layout Requirements

- `<html lang="{{ request.locale.iso_code }}">`
- Use `routes` object for all URLs (e.g., `{{ routes.root_url }}` not `/`)
- Don't modify or parse `content_for_header`
- Payment icons: use `shop.enabled_payment_types` + `payment_type_img_url` or `payment_type_svg_tag` (full color)

## Settings Requirements

- All settings must have a `label`
- `theme_info` section required in `settings_schema.json`
- Favicon setting required
- Logo upload works with different aspect ratios
- `link_list` settings in Header/Footer must default to `main-menu` or `footer`
- Resource-based setting defaults must reference existing resources
- `metaobject`/`metaobject_list`: only standard definitions for `metaobject_type`
- No Lorem Ipsum or demo store content as default placeholder text
- Theme editor changes must reflect in preview (`request.design_mode`)
- Minimum 4 colors, every background color needs a corresponding foreground color
- Color settings use `type: "color"`

### Font Settings
- Use `font_picker` type
- Default font loaded (e.g., `default: work_sans_n6`)
- Only currently available Shopify fonts
- CSS loads bold, italic, bold-italic variants via `font_modify`
- No custom fonts

## Terminology (MUST USE)

| Correct | Incorrect |
|---------|-----------|
| home page | homepage |
| top bar | meta-nav, search bar |
| bottom bar | below footer, legal |
| slideshow | slider |
| checkout | check out |
| heading | title |
| subheading | sub-heading |
| body text | main text |
| signup | sign-up, sign up |
| favicon | shortcut icon, website icon |
| sidebar | side bar |
| button label | button name |
| social media | social, social sharing |
| social media icons | social media buttons |
| navigation | menus, menu (for all nav) |
| main menu | navigation, menu (for primary) |
| footer menu | navigation, menu (for footer) |
| cart type | Ajax, Ajaxify, Ajax cart |
| .png | PNG, png, .PNG |

### Action Verbs for Settings
| Verb | Use for |
|------|---------|
| **use** | Actionable options with next step (e.g., uploading) |
| **show** | Show/hide a basic element |
| **enable** | Apps/plugins or significant layout changes |

### Text Style Rules
- Sentence case for section/preset/category names
- Descriptive names, not numbered (e.g., "Collage" not "Image 1")
- American English (color, center, gray, canceled, catalog, customize, organize, dialog)
- No ampersands (&)
- Declarative statements, not questions
- Active voice
- Buttons/actions start with a verb

## Performance and Accessibility

- **Lighthouse Performance:** Minimum average **60** across product, collection, home (desktop + mobile)
- **Lighthouse Accessibility:** Minimum average **90** across product, collection, home (desktop + mobile)
- Keyboard accessible (all page parts including dropdowns)
- Visible focus states
- All images have `alt` attribute (`image.alt` or `image_tag` with alt)
- Form inputs: unique ID + labels with matching `for`
- Valid HTML
- Color contrast: 4.5:1 body text, 3:1 for text >18pt and non-text elements
- Focus order matches DOM order (top-bottom, left-right)
- Touch targets: minimum 24x24 CSS pixels
- Headings h1-h6 visually distinct

## SEO Requirements

- SEO metadata: title, meta description, canonical URL
- Google rich product snippets (structured data)
- No `robots.txt.liquid` template

## Social Media

- Social media icon set
- Open Graph tags + Twitter card tags
- Social media placeholder text left empty

## Assets Rules

- No Sass/`.scss`/`.scss.liquid` files
- No minified `.css` or `.js` (except ES6 and third-party libraries)
- Protocol-relative URLs (no hard `http` or `https`)
- Scripts hosted on Shopify servers (except approved third-party)
- Responsive image strategy (lazy load, load as needed)

## Consistency and Functionality

- RTE content (`h1`-`h6`, blockquotes, `ul`, `ol`) consistent across all templates
- No JS interfering with theme editor or Shopify admin
- Links to Shopify domains must include `rel="nofollow"`
- Appropriate licenses for all third-party code and images
- No app-dependent functionality
- No app-like features requiring API access (wishlists, scheduling, cart-level discounts, Instagram feeds)
- No fake urgency/scarcity (countdown timers, stock levels, viewer counts)

## Browser Compatibility

**Desktop:** Safari (latest 2), Chrome (latest 3, Mac+PC), Firefox (latest 3, Mac+PC), Edge (latest 2)
**Mobile:** Mobile Safari (latest 2), Chrome Mobile (latest 3, Android+iOS), Samsung Internet (latest 2)
**Webviews:** Instagram, Facebook, Pinterest (latest, Android+iOS)
**Must be mobile responsive.**

## Theme Naming

- 1-2 words, under 30 characters
- Not similar to Shopify products/events/branded content
- Not company name or Partner account name
- Not platform/SEO terms (Performance, Mobile, Sales)
- Not industry/collection names (Fashion, Electronics)
- One preset must share the parent theme name
- Unique from existing Theme Store themes
- Use nouns, easy to spell/pronounce

## Preset File Structure (Multiple Presets)

```
listings/
  preset-name-one/
    templates/*.json
    sections/*.json (optional)
  another-preset-name/
    templates/*.json
    sections/*.json (optional)
```

Single preset: no `/listings` folder needed.

## Demo Store Requirements

- At least one demo per preset
- Match industry/catalog size the preset is tagged to
- Install state must match demo expectations
- Bogus Gateway or Shopify Payments test mode enabled
- Authentic text (no Lorem Ipsum, no profanities)
- `powered_by_link` unaltered
- No affiliate links
- Shopify domain links: `rel="nofollow"`
- No embedded text/buttons in images (except physical product text, infographics, badges)
- No animated GIFs mimicking theme functionality
- No apps (exceptions: free review apps, free translation apps with full translation)
- Obtain rights for all assets per Shopify Partner Agreement

## Pre-Submission Validation

Before submitting, verify:

1. Run `shopify theme check` for Liquid linting
2. Lighthouse audit on product, collection, home page (performance >= 60, accessibility >= 90)
3. Test all required features manually
4. Verify all page requirements met
5. Check terminology compliance in all settings/labels
6. Test browser compatibility (desktop + mobile + webviews)
7. Ensure no `config/markets.json` or `robots.txt.liquid`
8. Theme version number and release notes set
9. Documentation and contact form ready and linked
10. Demo store fully configured with authentic content

## Common Rejection Reasons

- Missing required template files
- Product page missing blocks (price, vendor, description should be individual blocks)
- No Custom Liquid section or blocks
- No app block support in product section
- Missing accelerated checkout on product or cart (or not default-enabled)
- Missing unit pricing on required pages
- Incorrect terminology in settings
- Minified CSS/JS in assets (non-third-party)
- Hard-coded URLs instead of `routes` object
- Missing `lang` attribute on `<html>`
- Lighthouse scores below threshold
- App-like features without full functionality
- Dawn/Horizon-derived codebase
