# Shopify Dev MCP Server

## Prerequisites

Node.js 18+

## Setup

```bash
claude mcp add --transport stdio shopify-dev-mcp -- npx -y @shopify/dev-mcp@latest
```

## Environment Variables

| Variable | Description |
|---|---|
| `OPT_OUT_INSTRUMENTATION` | Disable telemetry |
| `LIQUID_VALIDATION_MODE` | Liquid validation mode (not relevant for App Home, defaults to `full`) |

## Available Tools

| Tool | Description |
|---|---|
| `learn_shopify_api` | **Call first** before any API work. Returns context about the requested Shopify API. |
| `validate_component_codeblocks` | Validates Polaris Web Component usage in code blocks. Run after generating pages. |
| `validate_graphql_codeblocks` | Validates GraphQL queries/mutations against Shopify schemas. Run after writing GraphQL. |
| `fetch_full_docs` | Fetches complete documentation for a specific API or component. Use for unfamiliar components. |
| `search_docs_chunks` | Searches Shopify documentation by keyword. Returns relevant doc chunks. |
| `introspect_graphql_schema` | Introspects a Shopify GraphQL schema for types, fields, and arguments. |
| `validate_theme_codeblocks` | Validates Liquid theme code blocks. Not used for App Home. |
| `validate_theme` | Validates a full theme. Not used for App Home. |

## Supported APIs

- Admin GraphQL
- Customer Account
- Functions
- Liquid
- Partner API
- Payment Apps
- Polaris Web Components
- POS UI Extensions
- Storefront API

## Workflow

1. **Always call `learn_shopify_api` first** when starting any API work. This provides essential context.
2. For unfamiliar components, run `fetch_full_docs` before generating code.
3. After generating pages with Polaris Web Components, run `validate_component_codeblocks` to verify correctness.
4. After writing GraphQL queries or mutations, run `validate_graphql_codeblocks` to check against the schema.
5. Use `search_docs_chunks` for quick lookups when you need specific information.
6. Use `introspect_graphql_schema` to explore available types and fields before writing queries.
