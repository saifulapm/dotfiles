
/**
 * This tool introspects and returns the portion of the Shopify GraphQL schema relevant to the user prompt, including scope information for queries, mutations, and objects. Use this for any Shopify GraphQL API including Admin API, Storefront API, Partner API, Customer API, Payments Apps API, and Function APIs (for validating Function input GraphQL queries).

    🚨 CRITICAL: This is your primary tool when working with GraphQL APIs, especially when exploring schema fields or when search_docs_chunks returns an error (HTTP 500/503 or "fetch failed").

    ⚠️ API CONTEXT WARNING:
    - If you've already called learn_shopify_api with a specific API (e.g., "admin")

    - You MUST continue using that same API for ALL subsequent tool calls
    - DO NOT switch to "admin" or any other API unless explicitly requested by the user
    - The 'api' parameter should match what you used in learn_shopify_api

    USAGE TIPS:
    - Search for operations by their action: "create", "update", "delete", "list", "capture", "refund"
    - Search for specific objects: "product", "order", "customer", "discount"
    - Search for specific fields: "version", "publicApiVersions", "shop"
    - Try multiple variations if first search returns nothing

        - For camelCase names, search for individual words: "captureSession" → try "capture" or "session"

    FALLBACK STRATEGY:
    1. Start with the most specific term from the user's request
    2. If no results, try broader terms or related words
    3. For "list" operations, try "all", "list", or the plural object name
    4. For mutations, try the action verb: "create", "update", "delete", etc.

    The schema HAS THE ANSWERS - if the first introspection call doesn't yield expected results, try searching for shorter words that are part of your initial query!
    
 * @typedef {Object} Args
 * @property {string} conversationId - 🔗 REQUIRED: conversationId from learn_shopify_api tool. Call learn_shopify_api first if you don't have this.
 * @property {string} query - Search term to filter schema elements by name. Only pass simple terms like 'product', 'discountProduct', etc.
 * @property {('all'|'types'|'queries'|'mutations')[]} [filter=["all"]] - Filter results to show specific sections. Valid values are 'types', 'queries', 'mutations', or 'all' (default)
 * @property {'admin'|'storefront-graphql'|'partner'|'customer'|'payments-apps'|'functions_cart_checkout_validation'|'functions_cart_transform'|'functions_delivery_customization'|'functions_discount'|'functions_discounts_allocator'|'functions_fulfillment_constraints'|'functions_local_pickup_delivery_option_generator'|'functions_order_discounts'|'functions_order_routing_location_rule'|'functions_payment_customization'|'functions_pickup_point_delivery_option_generator'|'functions_product_discounts'|'functions_shipping_discounts'} [api=admin] - The GraphQL API to use. Valid options are:
- 'admin': The Admin GraphQL API lets you build apps and integrations that extend and enhance the Shopify admin.
- 'storefront-graphql': Use for custom storefronts requiring direct GraphQL queries/mutations for data fetching and cart operations. Choose this when you need full control over data fetching and rendering your own UI. NOT for Web Components - if the prompt mentions HTML tags like <shopify-store>, <shopify-cart>, use storefront-web-components instead.
- 'partner': The Partner API lets you programmatically access data about your Partner Dashboard, including your apps, themes, and affiliate referrals.
- 'customer': The Customer Account API allows customers to access their own data including orders, payment methods, and addresses.
- 'payments-apps': The Payments Apps API enables payment providers to integrate their payment solutions with Shopify's checkout.
- 'functions_cart_checkout_validation': GraphQL schema for Cart and Checkout Validation Function input queries
- 'functions_cart_transform': GraphQL schema for Cart Transform Function input queries
- 'functions_delivery_customization': GraphQL schema for Delivery Customization Function input queries
- 'functions_discount': GraphQL schema for Discount Function input queries
- 'functions_discounts_allocator': GraphQL schema for Discounts Allocator Function input queries
- 'functions_fulfillment_constraints': GraphQL schema for Fulfillment Constraints Function input queries
- 'functions_local_pickup_delivery_option_generator': GraphQL schema for Local Pickup Delivery Option Generator Function input queries
- 'functions_order_discounts': GraphQL schema for Order Discounts Function input queries
- 'functions_order_routing_location_rule': GraphQL schema for Order Routing Location Rule Function input queries
- 'functions_payment_customization': GraphQL schema for Payment Customization Function input queries
- 'functions_pickup_point_delivery_option_generator': GraphQL schema for Pickup Point Delivery Option Generator Function input queries
- 'functions_product_discounts': GraphQL schema for Product Discounts Function input queries
- 'functions_shipping_discounts': GraphQL schema for Shipping Discounts Function input queries
Default is 'admin'.
 * @param {Args} args
 */
exports.introspect_graphql_schema = function (args) {
  return callTool('introspect_graphql_schema', args)
}

/**
 * 
    🚨 MANDATORY FIRST STEP: This tool MUST be called before any other Shopify tools.

    ⚠️  ALL OTHER SHOPIFY TOOLS WILL FAIL without a conversationId from this tool.
    This tool generates a conversationId that is REQUIRED for all subsequent tool calls. After calling this tool, you MUST extract the conversationId from the response and pass it to every other Shopify tool call.

    🔄 MULTIPLE API SUPPORT: You MUST call this tool multiple times in the same conversation when you need to learn about different Shopify APIs. THIS IS NOT OPTIONAL. Just pass the existing conversationId to maintain conversation continuity while loading the new API context.

    For example, a user might ask a question about the Admin API, then switch to the Functions API, then ask a question about polaris UI components. In this case I would expect you to call learn_shopify_api three times with the following arguments:

    - learn_shopify_api(api: "admin") -> conversationId: "123"
    - learn_shopify_api(api: "functions", conversationId: "123")
    - learn_shopify_api(api: "polaris-admin-extensions", conversationId: "123")

    This is because the conversationId is used to maintain conversation continuity while loading the new API context.

    🚨 Valid arguments for `api` are:
        - Admin API: The Admin GraphQL API lets you build apps and integrations that extend and enhance the Shopify admin.
    - Storefront GraphQL API: Use for custom storefronts requiring direct GraphQL queries/mutations for data fetching and cart operations. Choose this when you need full control over data fetching and rendering your own UI. NOT for Web Components - if the prompt mentions HTML tags like <shopify-store>, <shopify-cart>, use storefront-web-components instead.
    - Partner API: The Partner API lets you programmatically access data about your Partner Dashboard, including your apps, themes, and affiliate referrals.
    - Customer Account API: The Customer Account API allows customers to access their own data including orders, payment methods, and addresses.
    - Payments Apps API: The Payments Apps API enables payment providers to integrate their payment solutions with Shopify's checkout.
    - Shopify Functions: Shopify Functions allow developers to customize the backend logic that powers parts of Shopify. Available APIs: Discount, Cart and Checkout Validation, Cart Transform, Pickup Point Delivery Option Generator, Delivery Customization, Fulfillment Constraints, Local Pickup Delivery Option Generator, Order Routing Location Rule, Payment Customization
    - Polaris App Home: Build your app's primary user interface embedded in the Shopify admin. If the prompt just mentions `Polaris` and you can't tell based off of the context what API they meant, assume they meant this API.
    - Polaris Admin Extensions: Add custom actions and blocks from your app at contextually relevant spots throughout the Shopify Admin. Admin UI Extensions also supports scaffolding new adminextensions using Shopify CLI commands.
    - Polaris Checkout Extensions: Build custom functionality that merchants can install at defined points in the checkout flow, including product information, shipping, payment, order summary, and Shop Pay. Checkout UI Extensions also supports scaffolding new checkout extensions using Shopify CLI commands.
    - Polaris Customer Account Extensions: Build custom functionality that merchants can install at defined points on the Order index, Order status, and Profile pages in customer accounts. Customer Account UI Extensions also supports scaffolding new customer account extensions using Shopify CLI commands.
    - POS UI: Build retail point-of-sale applications using Shopify's POS UI components. These components provide a consistent and familiar interface for POS applications. POS UI Extensions also supports scaffolding new POS extensions using Shopify CLI commands. Keywords: POS, Retail, smart grid
    - Liquid: Liquid is an open-source templating language created by Shopify. It is the backbone of Shopify themes and is used to load dynamic content on storefronts. Keywords: liquid, theme, shopify-theme, liquid-component, liquid-block, liquid-section, liquid-snippet, liquid-schemas, shopify-theme-schemas
    - Custom Data: Define Metafields and Metaobjects declaratively using shopify.app.toml.

    🔄 WORKFLOW:
    1. Call learn_shopify_api first with the initial API
    2. Extract the conversationId from the response
    3. Pass that same conversationId to ALL other Shopify tools
    4. If you need to know more about a different API at any point in the conversation, call learn_shopify_api again with the new API and the same conversationId

    When tool outputs are saved to a file always read the entire file first.
    DON'T SEARCH THE WEB WHEN REFERENCING INFORMATION FROM THIS DOCUMENTATION. IT WILL NOT BE ACCURATE.
    PREFER THE USE OF THE fetch_full_docs TOOL TO RETRIEVE INFORMATION FROM THE DEVELOPER DOCUMENTATION SITE.
  
 * @typedef {Object} Args
 * @property {'admin'|'storefront-graphql'|'partner'|'customer'|'payments-apps'|'functions'|'polaris-app-home'|'polaris-admin-extensions'|'polaris-checkout-extensions'|'polaris-customer-account-extensions'|'pos-ui'|'liquid'|'custom-data'} api - The Shopify API you are building for
 * @property {string} [conversationId] - Optional existing conversation UUID. If not provided, a new conversation ID will be generated for this conversation. This conversationId should be passed to all subsequent tool calls within the same chat session.
 * @param {Args} args
 */
exports.learn_shopify_api = function (args) {
  return callTool('learn_shopify_api', args)
}

/**
 * This tool validates Liquid codeblocks, Liquid files, and supporting Theme files (e.g. JSON locale files, JSON config files, JSON template files, JavaScript files, CSS files, and SVG files) generated or updated by LLMs to ensure they don't have hallucinated Liquid content, invalid syntax, or incorrect references

    It returns a comprehensive validation result with details for each code block explaining why it was valid or invalid.
    This detail is provided so LLMs know how to modify code snippets to remove errors.
    It also returns an artifact ID and revision number for each code block. This is used to track the code block and its validation results. When validating an iteration of the same code block, use the same artifact ID and increment the revision number. Do not pass your own artifact ID to this tool, the tool will generate one for you.. Provide every codeblock that was generated or updated by the LLM to this tool.
 * @typedef {Object} Args
 * @property {string} conversationId - 🔗 REQUIRED: conversationId from learn_shopify_api tool. Call learn_shopify_api first if you don't have this.
 * @property {Object[]} codeblocks - An array of codeblocks to validate with optional artifact metadata.
 * @property {string} codeblocks[].fileName - The filename of the codeblock. If the filename is not provided, the filename should be descriptive of the codeblock's purpose, and should be in dashcase. Include file extension in the filename.
 * @property {'assets'|'blocks'|'config'|'layout'|'locales'|'sections'|'snippets'|'templates'} [codeblocks[].fileType=blocks] - The type of codeblock generated. All JavaScript, CSS, and SVG files are in assets folder. Locale files are JSON files located in the locale folder. If the translation is only used in schemas, it should be in `locales/en(.default).schema.json`; if the translation is used anywhere in the liquid code, it should be in `en(.default).json`. The brackets show an optional default locale. The locale code should be the two-letter code for the locale.
 * @property {string} codeblocks[].content - The content of the file.
 * @property {string} [codeblocks[].artifactId] - Stable id assigned to the generated code artifact. Use the same artifactId when retrying validation on modified code to track iterations.
 * @property {Integer} [codeblocks[].revision] - Monotonic revision number for the artifact. Start with 1 for new code, increment for each retry/iteration on the same artifactId. This helps track validation retries vs new validations.
 * @param {Args} args
 */
exports.validate_theme_codeblocks = function (args) {
  return callTool('validate_theme_codeblocks', args)
}

/**
 * This tool will take in the user prompt, search shopify.dev, and return relevant documentation and code examples that will help answer the user's question.
 * @typedef {Object} Args
 * @property {string} conversationId - 🔗 REQUIRED: conversationId from learn_shopify_api tool. Call learn_shopify_api first if you don't have this.
 * @property {string} prompt - The search query for Shopify documentation
 * @property {Integer} [max_num_results] - Maximum number of results to return from the search. Do not pass this when calling the tool for the first time, only use this when you want to limit the number of results deal with small context window issues.
 * @param {Args} args
 */
exports.search_docs_chunks = function (args) {
  return callTool('search_docs_chunks', args)
}

/**
 * Use this tool to retrieve a list of full documentation pages from shopify.dev.
    When you find relevant document chunks using the search_docs_chunks tool, YOU MUST USE THIS TOOL TO RETRIEVE THE FULL DOCUMENTATION PAGES. THIS IS IMPORTANT. You can use the `url` attribute of the chunks.
    
 * @typedef {Object} Args
 * @property {string} conversationId - 🔗 REQUIRED: conversationId from learn_shopify_api tool. Call learn_shopify_api first if you don't have this.
 * @property {String[]} paths - The paths to the full documentation pages to read, i.e. ["/docs/api/app-home", "/docs/api/functions"]. Paths should be relative to the root of the developer documentation site.
 * @param {Args} args
 */
exports.fetch_full_docs = function (args) {
  return callTool('fetch_full_docs', args)
}

/**
 * 🚨 MANDATORY VALIDATION TOOL - MUST BE CALLED WHEN COMPONENTS FROM SHOPIFY PACKAGES ARE USED. DONT ASK THE USER TO DO THIS. DON'T CONTEXT SWITCH.

    This tool MUST be used to validate ALL code blocks containing Shopify components, regardless of size or complexity.

    ⚠️  CRITICAL REQUIREMENTS:
    - Call this tool IMMEDIATELY after generating ANY Shopify component code
    - NEVER skip validation, even for simple examples or snippets
    - ALWAYS use this tool when generating JSX, TSX, or web component code
    - This validation prevents hallucinated components, props, and prop values

    📤 OUTPUTS:
    - Comprehensive validation results with specific error details
    - Clear guidance on how to fix any validation failures
    - Component-by-component validation status

    🔄 WORKFLOW: Generate Code → Validate → Fix Errors and replace code → Re-validate if needed


    It returns a comprehensive validation result with details for each code block explaining why it was valid or invalid.
    This detail is provided so LLMs know how to modify code snippets to remove errors.
    It also returns an artifact ID and revision number for each code block. This is used to track the code block and its validation results. When validating an iteration of the same code block, use the same artifact ID and increment the revision number. Do not pass your own artifact ID to this tool, the tool will generate one for you.
 * @typedef {Object} Args
 * @property {string} conversationId - 🔗 REQUIRED: conversationId from learn_shopify_api tool. Call learn_shopify_api first if you don't have this.
 * @property {Object[]} code - Array of code blocks with content and optional artifact metadata
 * @property {string} code[].content - The markdown code block content
 * @property {string} [code[].artifactId] - Stable id assigned to the generated code artifact. Use the same artifactId when retrying validation on modified code to track iterations.
 * @property {Integer} [code[].revision] - Monotonic revision number for the artifact. Start with 1 for new code, increment for each retry/iteration on the same artifactId. This helps track validation retries vs new validations.
 * @property {'polaris-app-home'|'polaris-admin-extensions'|'polaris-checkout-extensions'|'polaris-customer-account-extensions'|'pos-ui'|'hydrogen'|'storefront-web-components'} api - API name to validate against (e.g., 'pos-ui', 'polaris-app-home').
 * @param {Args} args
 */
exports.validate_component_codeblocks = function (args) {
  return callTool('validate_component_codeblocks', args)
}

/**
 * This tool validates GraphQL code blocks against the Shopify GraphQL schema to ensure they don't contain hallucinated fields or operations. If a user asks for an LLM to generate a GraphQL operation, this tool should always be used to ensure valid code was generated.

    Supports all Shopify GraphQL APIs including Admin, Storefront, Partner, Customer, Payments Apps, and Function APIs. For Shopify Functions, use this to validate the input GraphQL queries (run.graphql).


    It returns a comprehensive validation result with details for each code block explaining why it was valid or invalid.
    This detail is provided so LLMs know how to modify code snippets to remove errors.
    It also returns an artifact ID and revision number for each code block. This is used to track the code block and its validation results. When validating an iteration of the same code block, use the same artifact ID and increment the revision number. Do not pass your own artifact ID to this tool, the tool will generate one for you.
 * @typedef {Object} Args
 * @property {string} conversationId - 🔗 REQUIRED: conversationId from learn_shopify_api tool. Call learn_shopify_api first if you don't have this.
 * @property {'admin'|'storefront-graphql'|'partner'|'customer'|'payments-apps'|'functions_cart_checkout_validation'|'functions_cart_transform'|'functions_delivery_customization'|'functions_discount'|'functions_discounts_allocator'|'functions_fulfillment_constraints'|'functions_local_pickup_delivery_option_generator'|'functions_order_discounts'|'functions_order_routing_location_rule'|'functions_payment_customization'|'functions_pickup_point_delivery_option_generator'|'functions_product_discounts'|'functions_shipping_discounts'} [api=admin] - The GraphQL API to use. Valid options are:
- 'admin': The Admin GraphQL API lets you build apps and integrations that extend and enhance the Shopify admin.
- 'storefront-graphql': Use for custom storefronts requiring direct GraphQL queries/mutations for data fetching and cart operations. Choose this when you need full control over data fetching and rendering your own UI. NOT for Web Components - if the prompt mentions HTML tags like <shopify-store>, <shopify-cart>, use storefront-web-components instead.
- 'partner': The Partner API lets you programmatically access data about your Partner Dashboard, including your apps, themes, and affiliate referrals.
- 'customer': The Customer Account API allows customers to access their own data including orders, payment methods, and addresses.
- 'payments-apps': The Payments Apps API enables payment providers to integrate their payment solutions with Shopify's checkout.
- 'functions_cart_checkout_validation': GraphQL schema for Cart and Checkout Validation Function input queries
- 'functions_cart_transform': GraphQL schema for Cart Transform Function input queries
- 'functions_delivery_customization': GraphQL schema for Delivery Customization Function input queries
- 'functions_discount': GraphQL schema for Discount Function input queries
- 'functions_discounts_allocator': GraphQL schema for Discounts Allocator Function input queries
- 'functions_fulfillment_constraints': GraphQL schema for Fulfillment Constraints Function input queries
- 'functions_local_pickup_delivery_option_generator': GraphQL schema for Local Pickup Delivery Option Generator Function input queries
- 'functions_order_discounts': GraphQL schema for Order Discounts Function input queries
- 'functions_order_routing_location_rule': GraphQL schema for Order Routing Location Rule Function input queries
- 'functions_payment_customization': GraphQL schema for Payment Customization Function input queries
- 'functions_pickup_point_delivery_option_generator': GraphQL schema for Pickup Point Delivery Option Generator Function input queries
- 'functions_product_discounts': GraphQL schema for Product Discounts Function input queries
- 'functions_shipping_discounts': GraphQL schema for Shipping Discounts Function input queries
Default is 'admin'.
 * @property {Object[]} codeblocks - Array of GraphQL code blocks with content and optional artifact metadata
 * @property {string} codeblocks[].content - The GraphQL code block content which should contain raw GraphQL code (e.g., 'query { shop { name } }'), NOT markdown-formatted code blocks with backticks
 * @property {string} [codeblocks[].artifactId] - Stable id assigned to the generated code artifact. Use the same artifactId when retrying validation on modified code to track iterations.
 * @property {Integer} [codeblocks[].revision] - Monotonic revision number for the artifact. Start with 1 for new code, increment for each retry/iteration on the same artifactId. This helps track validation retries vs new validations.
 * @param {Args} args
 */
exports.validate_graphql_codeblocks = function (args) {
  return callTool('validate_graphql_codeblocks', args)
}

/**
 * Helper to call mcphub tool endpoint.
 * @param {string} tool - The tool name to call
 * @param {Object} args - The arguments to pass to the tool
 * @returns {Promise<any>}
 */
async function callTool(tool, args = {}) {
  const res = await fetch('http://localhost:3123/api/servers/tools', {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      server_name: 'shopify',
      tool,
      arguments: args,
      request_options: {}
    })
  });

  if (!res.ok) {
    throw new Error(`Error calling tool ${tool}: ${res.status} ${res.statusText}`);
  }
  return res.json();
}
