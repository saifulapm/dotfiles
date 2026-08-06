---
name: shopify-research
description: Analyze 17,000+ Shopify apps AND the Shopify theme marketplace (300+ themes) to find development opportunities, market gaps, and product ideas. Use when the user asks for app or theme ideas, market analysis, competitor research, Shopify Functions opportunities, trending categories/industries, quick wins, or asks to analyze apps/themes by category, industry, pricing, ratings, features, or recent launches. Also use when comparing Shopify apps or themes, or researching a specific app or theme niche.
argument-hint: "[topic or question about the Shopify app or theme market]"
allowed-tools: Bash(shopify_apps *)
---

# Shopify App Market Analyzer

You have access to a database of 17,000+ Shopify apps via the `shopify_apps` CLI tool. The data includes titles, descriptions, ratings, reviews, pricing plans, developer info, categories, integrations, launch dates, and "Built for Shopify" status.

Use this tool to answer any question about the Shopify app marketplace with **real data**.

## Tool Reference

The binary is at `shopify_apps` (in PATH). Data file is at `~/.shopify_apps.json` (default).

### Commands

```
shopify_apps search <query>          # Search apps by keyword
shopify_apps stats                   # Overall market statistics
shopify_apps categories              # Category breakdown
shopify_apps developers              # Top developer analysis
shopify_apps pricing                 # Pricing analysis
shopify_apps trends                  # Launch trends & rising apps
shopify_apps opportunities           # Market gaps & opportunities
shopify_apps compare <app1> <app2>   # Side-by-side comparison
shopify_apps export                  # Export filtered data as JSON
```

### Common Flags

| Flag | Description |
|------|-------------|
| `-n, --limit <N>` | Max results (default: 20) |
| `-s, --sort <field>` | Sort by: `rating`, `reviews`, `price` |
| `-d, --detailed` | Show full details (search only) |
| `--min-rating <N>` | Min rating filter (0.0-5.0) |
| `--min-reviews <N>` | Min review count |
| `--built-for-shopify` | Only "Built for Shopify" apps |
| `--developer <name>` | Filter by developer |
| `--json` | JSON output (stats command) |
| `-c, --category <cat>` | Filter by category (pricing/export) |
| `-q, --query <q>` | Search query (export command) |

### Example Commands

```bash
# Market overview
shopify_apps stats

# Find top shipping apps
shopify_apps search "shipping" --min-reviews 50 --sort rating -n 10

# Analyze pricing in SEO category
shopify_apps pricing --category "seo"

# Compare competing review apps
shopify_apps compare "Judge.me" "Loox" "Yotpo"

# Find opportunities
shopify_apps opportunities -n 15

# Recent trending apps
shopify_apps trends --year 2025 -n 20

# Export data for deep analysis
shopify_apps export --query "subscription" --min-reviews 100 -n 20

# Top developers by review count
shopify_apps developers --sort reviews -n 15

# Category breakdown sorted by reviews
shopify_apps categories --sort reviews -n 20

# Built for Shopify apps in a niche
shopify_apps search "upsell" --built-for-shopify --sort reviews

# Detailed view of specific apps
shopify_apps search "Klaviyo" --detailed -n 5

# Apps by a specific developer
shopify_apps search "" --developer "Shopify" --sort reviews
```

## How to Respond

When the user asks about the Shopify app market:

1. **Run the relevant commands** to gather data. Run multiple commands in parallel when possible.
2. **Analyze the output** — don't just dump raw output. Synthesize insights.
3. **Answer the question** with specific numbers, app names, and actionable findings.
4. **Suggest follow-ups** — what else they might want to explore.

### Research Patterns

**"What apps exist for X?"**
→ `shopify_apps search "X" --sort reviews -n 15`
→ Follow up with `--detailed` on the top 3

**"Is there opportunity in X?"**
→ `shopify_apps search "X" --sort reviews` (see competition)
→ `shopify_apps pricing --category "X"` (see pricing landscape)
→ `shopify_apps search "X" --max-rating 4.0 --min-reviews 20` (find pain points from low-rated popular apps)

**"Compare these apps"**
→ `shopify_apps compare "App1" "App2" "App3"`

**"What's trending?"**
→ `shopify_apps trends --year 2025 -n 20`
→ `shopify_apps opportunities`

**"Market overview / stats"**
→ `shopify_apps stats`
→ `shopify_apps categories -n 30`

**"Pricing research for X"**
→ `shopify_apps pricing --category "X"`
→ `shopify_apps search "X" --sort price -n 20`

**"Who are the top developers?"**
→ `shopify_apps developers --sort reviews -n 20`
→ `shopify_apps developers --sort rating -n 20`

**"Find underserved niches"**
→ `shopify_apps opportunities -n 20`
→ Look for: low avg ratings, few BfS apps, low top-5 review counts

**"Deep dive on a category"**
→ `shopify_apps search "category" --sort reviews -n 20`
→ `shopify_apps pricing --category "category"`
→ `shopify_apps search "category" --built-for-shopify`
→ `shopify_apps search "category" --min-reviews 100 --detailed -n 5`

## Theme Marketplace Analysis

The same CLI also analyzes the **Shopify theme marketplace** (300+ themes) via the `shopify_apps theme` subcommand. Data file is `~/.shopify_themes.json` by default. Override with `--theme-file <PATH>` placed **before** the subcommand (e.g. `shopify_apps theme --theme-file ./themes.json stats`).

> Note: theme ratings are a **percentage 0–100** (not 0–5 stars like apps). Themes are organized by **industry**, not category. There is no "Built for Shopify" badge for themes.

### Theme Commands

```
shopify_apps theme stats                     # Theme marketplace statistics
shopify_apps theme industries                # Industry breakdown (themes, ratings, pricing, competition)
shopify_apps theme search <query>            # Search themes by keyword/industry/feature
shopify_apps theme info <name>               # Detailed info for a specific theme
shopify_apps theme developers                # Top theme developer analysis
shopify_apps theme pricing                   # Pricing analysis across themes
shopify_apps theme opportunities             # Market gaps & theme dev opportunities
shopify_apps theme features                  # Feature analysis — common vs rare, gaps by industry
shopify_apps theme compare <t1> <t2> ...     # Side-by-side theme comparison
shopify_apps theme export                    # Export filtered theme data as JSON
```

### Theme Flags

| Flag | Applies to | Description |
|------|-----------|-------------|
| `-n, --limit <N>` | search/industries/developers/opportunities/features/export | Max results |
| `-s, --sort <field>` | search/export (`reviews`,`rating`,`price`); industries (`themes`,`rating`,`price`,`reviews`); developers (`themes`,`reviews`,`rating`) | Sort order |
| `--industry <name>` | search/pricing/features/export | Filter by industry |
| `--min-rating <0-100>` | search | Min rating percentage |
| `--max-price <USD>` | search/export | Max price filter |
| `--free-only` | search | Only free themes |
| `-d, --detailed` | search | Show full details |
| `--developer <name>` | export | Filter by developer |
| `-q, --query <q>` | export | Search query |
| `--json` | all | JSON output (use for programmatic analysis) |

### Theme Example Commands

```bash
# Theme market overview
shopify_apps theme stats

# Most competitive / largest industries
shopify_apps theme industries --sort themes -n 20
shopify_apps theme industries --sort rating

# Find fashion themes, best-reviewed first
shopify_apps theme search "fashion" --sort reviews -n 10

# Affordable, well-rated themes in an industry
shopify_apps theme search "" --industry "Food & drink" --max-price 200 --min-rating 90

# Free themes
shopify_apps theme search "" --free-only --sort reviews

# Deep dive on a theme
shopify_apps theme info "Dawn"

# Compare leading themes
shopify_apps theme compare "Dawn" "Impulse" "Prestige"

# Pricing landscape (overall or by industry)
shopify_apps theme pricing
shopify_apps theme pricing --industry "Electronics"

# Feature gaps by industry
shopify_apps theme features --industry "Jewelry" -n 20

# Where to build a new theme
shopify_apps theme opportunities -n 15

# Top theme developers
shopify_apps theme developers --sort reviews -n 15

# Export for deep analysis
shopify_apps theme export --industry "Beauty" --max-price 300 -n 20
```

### Theme Research Patterns

**"What themes exist for industry X?"**
→ `shopify_apps theme search "X" --sort reviews -n 15` (or `--industry "X"`)
→ Follow up with `theme info` on the top picks

**"Is there opportunity to build a theme for X?"**
→ `shopify_apps theme opportunities`
→ `shopify_apps theme industries --sort themes` (find thin/competitive industries)
→ `shopify_apps theme features --industry "X"` (find missing features)
→ `shopify_apps theme pricing --industry "X"` (price landscape)

**"Compare these themes"**
→ `shopify_apps theme compare "T1" "T2" "T3"`

**"Theme pricing research"**
→ `shopify_apps theme pricing` / `theme pricing --industry "X"`
→ `shopify_apps theme search "X" --sort price -n 20`

**"Who are the top theme developers?"**
→ `shopify_apps theme developers --sort reviews -n 20`
→ `shopify_apps theme developers --sort rating`

**"Theme market overview"**
→ `shopify_apps theme stats`
→ `shopify_apps theme industries -n 30`

Synthesize insights the same way as apps — don't dump raw output; lead with numbers, theme names, industries, and actionable findings; suggest follow-ups.

## Data Fields Available (via export)

Each app record contains: `title`, `tagline`, `description`, `description_full`, `rating`, `review_count`, `rating_distribution`, `developer`, `developer_url`, `developer_website`, `developer_email`, `developer_address`, `languages`, `works_with`, `categories`, `launched_date`, `built_for_shopify`, `pricing_plans` (with name, price, features, trial_info, additional_charges), `reviews` (with rating, date, merchant_name, comment), `app_url`, `icon_url`, `screenshots`, `video_urls`, `support_url`, `privacy_policy_url`, `scraped_at`.

Each theme record (via `theme export`) contains: `name`, `price`, `theme_url`, `tagline`, `description`, `thumbnail_url`, `screenshots`, `video_urls`, `rating_percentage` (0–100), `review_count`, `reviews_positive`, `reviews_neutral`, `reviews_negative`, `reviews` (with reviewer, date, comment), `developer`, `developer_location`, `developer_email`, `support_url`, `documentation_url`, `presets`, `features` (map of category → feature list), `industries`, `catalog_size`, `version`, `version_date`, `is_new`, `scraped_at`.

$ARGUMENTS
