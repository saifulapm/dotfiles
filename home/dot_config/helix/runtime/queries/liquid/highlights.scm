; Liquid Highlights for kak-tree-sitter (Helix-style)

; Comments
(comment) @comment

; Documentation tags (@param, @description, @example, etc.)
(doc_tag) @attribute

; Documentation text
(doc_text) @comment.documentation

; Strings
(string) @string

; Numbers
(number) @constant.numeric

; Booleans
(boolean) @constant.builtin.boolean

; Variables
(identifier) @variable

; Property access
(access
  property: (identifier) @variable.other.member)

; Known Shopify filters
((filter
  name: (identifier) @function.builtin)
 (#any-of? @function.builtin
  ; Array
  "compact" "concat" "find" "find_index" "first" "has" "join" "last" "map" "reject" "reverse" "size" "sort" "sort_natural" "sum" "uniq" "where"
  ; Cart
  "item_count_for_variant" "line_items_for"
  ; Collection
  "highlight_active_tag" "link_to_type" "link_to_vendor" "sort_by" "url_for_type" "url_for_vendor" "within"
  ; Color
  "brightness_difference" "color_brightness" "color_contrast" "color_darken" "color_desaturate" "color_difference" "color_extract" "color_lighten" "color_mix" "color_modify" "color_saturate" "color_to_hex" "color_to_hsl" "color_to_oklch" "color_to_rgb" "hex_to_rgba"
  ; Customer
  "avatar" "customer_login_link" "customer_logout_link" "customer_register_link" "login_button"
  ; Default
  "default" "default_errors" "default_pagination"
  ; Font
  "font_face" "font_modify" "font_url"
  ; Format
  "date" "json" "structured_data" "unit_price_with_measurement" "weight_with_unit"
  ; HTML
  "highlight" "inline_asset_content" "link_to" "placeholder_svg_tag" "preload_tag" "script_tag" "stylesheet_tag" "time_tag"
  ; Hosted File
  "asset_img_url" "asset_url" "file_img_url" "file_url" "global_asset_url" "shopify_asset_url"
  ; Localization
  "currency_selector" "format_address" "translate" "t"
  ; Math
  "abs" "at_least" "at_most" "ceil" "divided_by" "floor" "minus" "modulo" "plus" "round" "times"
  ; Media
  "article_img_url" "collection_img_url" "external_video_tag" "external_video_url" "image_tag" "image_url" "img_tag" "img_url" "media_tag" "model_viewer_tag" "product_img_url" "video_tag"
  ; Metafield
  "metafield_tag" "metafield_text"
  ; Money
  "money" "money_with_currency" "money_without_currency" "money_without_trailing_zeros"
  ; Payment
  "payment_button" "payment_terms" "payment_type_img_url" "payment_type_svg_tag"
  ; String
  "append" "base64_decode" "base64_encode" "base64_url_safe_decode" "base64_url_safe_encode" "blake3" "camelize" "capitalize" "downcase" "escape" "escape_once" "handleize" "hmac_sha1" "hmac_sha256" "lstrip" "md5" "newline_to_br" "pluralize" "prepend" "remove" "remove_first" "remove_last" "replace" "replace_first" "replace_last" "rstrip" "sha1" "sha256" "slice" "split" "strip" "strip_html" "strip_newlines" "truncate" "truncatewords" "upcase" "url_decode" "url_encode" "url_escape" "url_param_escape"
  ; Tag
  "link_to_add_tag" "link_to_remove_tag" "link_to_tag"))

; Unknown/custom filters (fallback)
(filter
  name: (identifier) @function)

; Operators
(predicate) @operator

[
  "|"
  ":"
  "="
] @operator

; Keyword operators
[
  "and"
  "contains"
  "in"
  "or"
] @keyword.operator

; Control flow keywords
[
  "if"
  "elsif"
  "else"
  "endif"
  "unless"
  "endunless"
  "case"
  "when"
  "endcase"
] @keyword.control.conditional

; Loop keywords
[
  "for"
  "endfor"
  "tablerow"
  "endtablerow"
  "cycle"
  "paginate"
  "endpaginate"
] @keyword.control.repeat

(break_statement) @keyword.control.repeat
(continue_statement) @keyword.control.repeat

; Deprecated tags
[
  "include"
  "include_relative"
] @keyword.deprecated

; Other keywords
[
  "as"
  "assign"
  "by"
  "capture"
  "endcapture"
  "content_for"
  "decrement"
  "doc"
  "enddoc"
  "echo"
  "form"
  "endform"
  "increment"
  "javascript"
  "endjavascript"
  "layout"
  "liquid"
  "raw"
  "endraw"
  "render"
  "schema"
  "endschema"
  "section"
  "sections"
  "style"
  "endstyle"
  "stylesheet"
  "endstylesheet"
  "with"
] @keyword

; Loop modifiers (limit, offset, cols)
((argument
  key: (identifier) @keyword.control.repeat)
 (#any-of? @keyword.control.repeat "limit" "offset" "cols"))

; reversed modifier
((identifier) @keyword.control.repeat
 (#eq? @keyword.control.repeat "reversed"))

; Tag delimiters
[
  "{{"
  "}}"
  "{{-"
  "-}}"
  "{%"
  "%}"
  "{%-"
  "-%}"
] @tag

; Punctuation
[
  ","
  "."
] @punctuation.delimiter

[
  "["
  "]"
  "("
  ")"
] @punctuation.bracket

; Raw content
(raw_statement
  (raw_content) @string.special)

; Schema JSON content
(schema_statement
  (json_content) @string.special)

; Style content
(style_statement
  (style_content) @string.special)

; Stylesheet content
(stylesheet_statement
  (stylesheet_content) @string.special)

; JavaScript content
(javascript_statement
  (js_content) @string.special)
