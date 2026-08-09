#!/usr/bin/env -S mise exec -- node
// helix-to-kak — convert a Helix theme TOML into a Kakoune colorscheme.
// The mac dotfiles converter (it generated the old colors/*.kak set),
// resurrected as bin/theme-apply's kak bridge: the rendered helix theme
// (~/.config/helix/themes/qshell.toml) is converted straight to
// ~/.config/kak/colors/qshell.kak, so kak and helix always agree face for
// face — statusline inversion, mode colors, ts_* scope expansion and the
// missing-face fallback walk included. Also a standalone CLI:
//   helix-to-kak.js <input.toml> [output.kak]


const fs = require("fs");
const path = require("path");

// Simple TOML parser for theme files
function parseToml(content) {
  const result = {};
  let currentSection = result;

  content.split("\n").forEach(line => {
    line = line.trim();
    if (!line || line.startsWith("#")) return;

    // Section header
    if (line.match(/^\[(.+)\]$/)) {
      const section = line.match(/^\[(.+)\]$/)[1];
      currentSection = result[section] = result[section] || {};
      return;
    }

    // Key-value pair
    const match = line.match(/^([^=]+)=(.+)$/);
    if (match) {
      let key = match[1].trim();
      let value = match[2].trim();

      // Remove quotes from key if present
      key = key.replace(/^["']|["']$/g, "");

      // Parse objects like { fg = "color", bg = "color" } or { underline = { color = "x", style = "y" } }
      if (value.startsWith("{") && value.endsWith("}")) {
        const obj = {};
        let depth = 0;
        let currentPair = "";
        let pairs = [];

        // Manual parsing to handle nested objects
        for (let i = 1; i < value.length - 1; i++) {
          const char = value[i];
          if (char === "{") depth++;
          else if (char === "}") depth--;
          else if (char === "," && depth === 0) {
            pairs.push(currentPair.trim());
            currentPair = "";
            continue;
          }
          currentPair += char;
        }
        if (currentPair.trim()) pairs.push(currentPair.trim());

        pairs.forEach(pair => {
          const eqIndex = pair.indexOf("=");
          if (eqIndex === -1) return;

          const k = pair.substring(0, eqIndex).trim();
          let v = pair.substring(eqIndex + 1).trim();

          // Handle nested objects (like underline = { ... })
          if (v.startsWith("{") && v.endsWith("}")) {
            const nestedObj = {};
            const nestedPairs = v.slice(1, -1).split(",");
            nestedPairs.forEach(np => {
              const [nk, nv] = np.split("=").map(s => s.trim());
              if (nk && nv) {
                nestedObj[nk] = nv.replace(/^["']|["']$/g, "");
              }
            });
            obj[k] = nestedObj;
          } else {
            // Remove quotes from simple values
            obj[k] = v.replace(/^["']|["']$/g, "");
          }
        });
        currentSection[key] = obj;
      } else {
        // Remove quotes if present
        if (
          (value.startsWith("\"") || value.startsWith("'"))
          && (value.includes("\"") || value.includes("'"))
        ) {
          const quoteChar = value[0];
          const endQuoteIndex = value.indexOf(quoteChar, 1);
          if (endQuoteIndex > 0) {
            value = value.substring(1, endQuoteIndex);
          }
        }
        currentSection[key] = value;
      }
    }
  });

  return result;
}

// Deep merge two objects
function deepMerge(base, override) {
  const result = { ...base };

  for (const key in override) {
    if (override[key] && typeof override[key] === "object" && !Array.isArray(override[key])) {
      if (result[key] && typeof result[key] === "object" && !Array.isArray(result[key])) {
        result[key] = deepMerge(result[key], override[key]);
      } else {
        result[key] = override[key];
      }
    } else {
      result[key] = override[key];
    }
  }

  return result;
}

// Load theme with inheritance support
function loadThemeWithInheritance(themePath) {
  const content = fs.readFileSync(themePath, "utf8");
  const theme = parseToml(content);

  // Check if theme inherits from another
  if (theme.inherits) {
    const parentName = theme.inherits;
    const themeDir = path.dirname(themePath);
    const parentPath = path.join(themeDir, `${parentName}.toml`);

    if (!fs.existsSync(parentPath)) {
      console.warn(`Warning: Parent theme not found: ${parentPath}`);
      console.warn(`Continuing with current theme only...`);
      delete theme.inherits;
      return theme;
    }

    console.log(`Loading parent theme: ${parentName}`);
    const parentTheme = loadThemeWithInheritance(parentPath);

    // Remove the inherits key before merging
    delete theme.inherits;

    // Merge parent theme with current theme (current theme overrides parent)
    return deepMerge(parentTheme, theme);
  }

  return theme;
}

// Resolve color from palette or return as-is
function resolveColor(color, palette) {
  if (!color) return null;
  if (color.startsWith("#")) return color;
  // Check if it's a palette reference
  if (palette && palette[color]) {
    // Replace dots and hyphens with underscores for Kakoune option names
    const optionName = color.replace(/[.\-]/g, "_");
    return `%opt{${optionName}}`;
  }
  return color;
}

// Convert Helix modifiers and underline to Kakoune attributes
function convertModifiers(modifiers, underline) {
  let attrs = "";

  if (modifiers) {
    if (modifiers.includes("bold")) attrs += "b";
    if (modifiers.includes("dim")) attrs += "d";
    if (modifiers.includes("italic")) attrs += "i";
    if (modifiers.includes("slow_blink") || modifiers.includes("rapid_blink")) attrs += "B";
    if (modifiers.includes("reversed")) attrs += "r";
    if (modifiers.includes("crossed_out")) attrs += "s";
  }

  if (underline) {
    const style = typeof underline === "object" ? underline.style : "line";
    switch (style) {
      case "line":
      case "underlined":
        attrs += "u";
        break;
      case "curl":
        attrs += "c";
        break;
      case "double_line":
        attrs += "U";
        break;
      case "dashed":
      case "dotted":
        attrs += "u"; // Fallback to regular underline
        break;
    }
  }

  return attrs ? `+${attrs}` : "";
}

// Format color for Kakoune (don't quote here, we'll quote the whole face later)
function formatColor(color) {
  if (!color) return "default";
  if (color === "default") return "default";

  // Ensure we have a clean string
  color = String(color).trim();

  // If it's a palette reference, return as-is (will be quoted later)
  if (color.startsWith("%opt{")) {
    return color;
  }

  if (color.startsWith("#")) {
    return `rgb:${color.slice(1)}`;
  }
  return color;
}

// Build Kakoune face string
function buildFace(helixValue, palette) {
  if (typeof helixValue === "string") {
    const color = resolveColor(helixValue, palette);
    return formatColor(color);
  }

  if (typeof helixValue === "object") {
    const fg = resolveColor(helixValue.fg, palette);
    const bg = resolveColor(helixValue.bg, palette);
    const underlineColor = helixValue.underline?.color
      ? resolveColor(helixValue.underline.color, palette)
      : null;
    const attrs = convertModifiers(helixValue.modifiers, helixValue.underline);

    // Special case for diagnostic underlines (no fg/bg, just underline color)
    if (!fg && !bg && underlineColor) {
      return ",," + formatColor(underlineColor) + attrs;
    }

    // Only modifiers, no colors
    if (!fg && !bg && !underlineColor && attrs) {
      return attrs;
    }

    // Only background, no foreground
    if (!fg && bg) {
      return "," + formatColor(bg) + attrs;
    }

    // Foreground only (with possible modifiers)
    if (fg && !bg && !underlineColor) {
      return formatColor(fg) + attrs;
    }

    // Foreground and background
    let face = formatColor(fg);
    if (bg) {
      face += "," + formatColor(bg);
    }

    // Add underline color if present (requires fg,bg to be set first)
    if (underlineColor) {
      if (!bg) face += ",default";
      face += "," + formatColor(underlineColor);
    }

    face += attrs;

    return face;
  }

  return "default";
}

// Map Helix keys to Kakoune faces
function helixToKakoune(helixTheme) {
  const palette = helixTheme.palette || {};
  const faces = {};

  // Built-in UI face mappings: Kakoune => Helix
  const uiMappings = {
    "Default": "ui.background",
    "LineNumbers": "ui.linenr",
    "LineNumberCursor": "ui.linenr.selected",
    "LineNumbersWrapped": "ui.virtual.wrap",
    "StatusLine": "ui.statusline",
    "StatusLineMode": "warning",
    "StatusLineInfo": "info",
    "StatusLineValue": "info",
    "StatusCursor": "ui.menu.selected|ui.cursor",
    "Prompt": "ui.statusline",
    "PrimarySelection": "ui.selection.primary|ui.selection",
    "SecondarySelection": "ui.selection",
    "PrimaryCursor": "ui.cursor.primary|ui.cursor",
    "SecondaryCursor": "ui.cursor",
    "PrimaryCursorEol": "ui.cursor.primary.select|ui.cursor",
    "SecondaryCursorEol": "ui.cursor.primary.select|ui.cursor",
    "MenuBackground": "ui.menu",
    "MenuForeground": "ui.menu.selected",
    "MenuInfo": "ui.menu",
    "InlineInformation": "ui.virtual.inlay-hint|ui.virtual",
    "InlayHint": "ui.virtual.inlay-hint",
    "Error": "error",
    "DiagnosticError": "diagnostic.error",
    "DiagnosticWarning": "diagnostic.warning",
    "MatchingChar": "ui.cursor.match",
    "Whitespace": "ui.virtual.whitespace|comment",
    "Search": "ui.selection",
    "WrapMarker": "ui.virtual.wrap|ui.virtual",
    // "BufferPadding": "ui.background",
    "Information": "ui.help",

    // Some extra
    "hop_label_head": "ui.virtual.jump-label|ui.selection",
    "hop_label_tail": "ui.virtual.jump-label|ui.selection.primary",
  };

  // Built-in code face mappings: Kakoune => Helix
  const codeMappings = {
    "value": "type.builtin",
    "type": "type",
    "variable": "variable",
    "module": "type.parameter",
    "function": "function",
    "string": "string",
    "keyword": "keyword",
    "operator": "operator",
    "attribute": "attribute",
    "comment": "comment",
    "documentation": "comment",
    "meta": "special",
    "builtin": "variable.builtin",
    "InfoDefault": "ui.help",
    "InfoBlock": "markup.raw.block|markup.raw",
    "InfoBlockQuote": "markup.quote|markup.raw",
    "InfoBullet": "markup.list.unnumbered|markup.list",
    "InfoHeader": "markup.heading.1|markup.heading",
    "InfoLink": "markup.link.url|markup.link",
    "InfoLinkMono": "markup.link.label|markup.link",
    "InfoMono": "markup.raw.inline|markup.raw",
    "InfoRule": "ui.virtual.ruler|comment",
    "InfoDiagnosticError": "diagnostic.error|diagnostic",
    "InfoDiagnosticHint": "diagnostic.hint|diagnostic",
    "InfoDiagnosticInformation": "diagnostic.info|diagnostic",
    "InfoDiagnosticWarning": "diagnostic.warning|diagnostic",
    "Reference": "ui.cursor.match|ui.selection",
    "InlayHint": "ui.virtual.inlay-hint|ui.text.inactive",
    "InlayCodeLens": "ui.virtual.inlay-hint|ui.text.inactive",
    "SnippetsNextPlaceholders": "tabstop",
    "SnippetsOtherPlaceholders": "tabstop",
    "LineFlagError": "error",
    "LineFlagHint": "hint",
    "LineFlagInfo": "info",
    "LineFlagWarning": "warning",
  };

  // Built-in markup face mappings: Kakoune => Helix
  const markupMappings = {
    "title": "markup.heading",
    "header": "markup.heading.1|markup.heading",
    "mono": "markup.raw.inline|markup.raw",
    "block": "markup.raw.block|markup.raw",
    "link": "markup.link.url|markup.link",
    "bullet": "markup.list.unnumbered|markup.list",
    "list": "markup.list.numbered|markup.list",
  };

  // Map UI faces
  for (const [kakFace, helixKey] of Object.entries(uiMappings)) {
    const arr = helixKey.split("|");
    const value = helixTheme[arr[0]];
    if (value) {
      faces[kakFace] = buildFace(value, palette);
    } else if (arr[1]) {
      const value = helixTheme[arr[1]];
      if (value) {
        faces[kakFace] = buildFace(value, palette);
      }
    }
  }

  // Map code faces
  for (const [kakFace, helixKey] of Object.entries(codeMappings)) {
    const arr = helixKey.split("|");
    const value = helixTheme[arr[0]];
    if (value) {
      faces[kakFace] = buildFace(value, palette);
    } else if (arr[1]) {
      const value = helixTheme[arr[1]];
      if (value) {
        faces[kakFace] = buildFace(value, palette);
      }
    }
  }

  // Map markup faces
  for (const [kakFace, helixKey] of Object.entries(markupMappings)) {
    const arr = helixKey.split("|");
    const value = helixTheme[arr[0]];
    if (value) {
      faces[kakFace] = buildFace(value, palette);
    } else if (arr[1]) {
      const value = helixTheme[arr[1]];
      if (value) {
        faces[kakFace] = buildFace(value, palette);
      }
    }
  }

  // Map all syntax keys to ts_ prefixed faces (but not ui.*, error, warning, etc.)
  for (const [key, value] of Object.entries(helixTheme)) {
    if (key === "palette") continue;
    if (key.startsWith("ui.")) continue;

    // Convert key to Kakoune face name: string.special.url => ts_string_special_url
    // Replace dots and hyphens with underscores
    const kakFace = "ts_" + key.replace(/[.\-]/g, "_");
    faces[kakFace] = buildFace(value, palette);
  }

  return faces;
}

// Generate Kakoune colorscheme file
function generateKakouneTheme(faces, themeName, palette) {
  let output = `# ${themeName}\n# Converted from Helix theme\n\n`;

  // Generate palette declarations
  if (palette && Object.keys(palette).length > 0) {
    output += `# Palette\n`;
    for (const [name, color] of Object.entries(palette)) {
      // Replace dots and hyphens with underscores in option names for Kakoune compatibility
      const optionName = name.replace(/[.\-]/g, "_");
      const cleanColor = String(color).replace("#", "");
      output += `declare-option str ${optionName} 'rgb:${cleanColor}'\n`;
    }
    output += `\n`;
  }

  // List of all standard Kakoune faces
  const standardFaces = [
    // Built-in UI faces
    "Default",
    "LineNumbers",
    "LineNumberCursor",
    "LineNumbersWrapped",
    "StatusLine",
    "StatusLineMode",
    "StatusLineInfo",
    "StatusLineValue",
    "StatusCursor",
    "Prompt",
    "PrimarySelection",
    "SecondarySelection",
    "PrimaryCursor",
    "SecondaryCursor",
    "PrimaryCursorEol",
    "SecondaryCursorEol",
    "MenuBackground",
    "MenuForeground",
    "MenuInfo",
    "InlineInformation",
    "Error",
    "DiagnosticError",
    "DiagnosticWarning",
    "MatchingChar",
    "Whitespace",
    "Search",
    "WrapMarker",
    "BufferPadding",
    "Information",

    // Code faces
    "value",
    "type",
    "variable",
    "module",
    "function",
    "string",
    "keyword",
    "operator",
    "attribute",
    "comment",
    "meta",
    "builtin",
    "documentation",

    // Markup faces
    "title",
    "header",
    "mono",
    "block",
    "link",
    "bullet",
    "list",

    // Tree-sitter faces
    "ts_variable",
    "ts_variable_builtin",
    "ts_variable_parameter",
    "ts_variable_parameter_builtin",
    "ts_variable_member",
    "ts_variable_other_member",
    "ts_variable_other_member_private",
    "ts_constant",
    "ts_constant_builtin",
    "ts_constant_builtin_boolean",
    "ts_constant_character",
    "ts_constant_character_escape",
    "ts_constant_macro",
    "ts_constant_numeric",
    "ts_constant_integer",
    "ts_constant_float",
    "ts_module",
    "ts_module_builtin",
    "ts_label",
    "ts_string",
    "ts_string_documentation",
    "ts_string_regexp",
    "ts_string_escape",
    "ts_string_special",
    "ts_string_special_symbol",
    "ts_string_special_url",
    "ts_string_special_path",
    "ts_character",
    "ts_character_special",
    "ts_boolean",
    "ts_number",
    "ts_number_float",
    "ts_type",
    "ts_type_builtin",
    "ts_type_definition",
    "ts_type_parameter",
    "ts_type_enum",
    "ts_type_enum_variant",
    "ts_attribute",
    "ts_attribute_builtin",
    "ts_property",
    "ts_function",
    "ts_function_builtin",
    "ts_function_call",
    "ts_function_macro",
    "ts_function_method",
    "ts_function_method_call",
    "ts_function_method_private",
    "ts_function_special",
    "ts_constructor",
    "ts_operator",
    "ts_keyword",
    "ts_keyword_coroutine",
    "ts_keyword_function",
    "ts_keyword_operator",
    "ts_keyword_import",
    "ts_keyword_type",
    "ts_keyword_modifier",
    "ts_keyword_repeat",
    "ts_keyword_return",
    "ts_keyword_debug",
    "ts_keyword_exception",
    "ts_keyword_conditional",
    "ts_keyword_conditional_ternary",
    "ts_keyword_directive",
    "ts_keyword_directive_define",
    "ts_keyword_storage",
    "ts_keyword_storage_type",
    "ts_keyword_storage_modifier",
    "ts_keyword_control_conditional",
    "ts_keyword_control_repeat",
    "ts_keyword_control_import",
    "ts_keyword_control_return",
    "ts_keyword_control_exception",
    "ts_punctuation_delimiter",
    "ts_punctuation_bracket",
    "ts_punctuation_special",
    "ts_comment",
    "ts_comment_line",
    "ts_comment_line_documentation",
    "ts_comment_block",
    "ts_comment_block_documentation",
    "ts_comment_unused",
    "ts_comment_documentation",
    "ts_comment_error",
    "ts_comment_warning",
    "ts_comment_todo",
    "ts_comment_note",
    "ts_markup",
    "ts_markup_strong",
    "ts_markup_bold",
    "ts_markup_italic",
    "ts_markup_strikethrough",
    "ts_markup_underline",
    "ts_markup_heading",
    "ts_markup_heading_marker",
    "ts_markup_heading_1",
    "ts_markup_heading_2",
    "ts_markup_heading_3",
    "ts_markup_heading_4",
    "ts_markup_heading_5",
    "ts_markup_heading_6",
    "ts_markup_quote",
    "ts_markup_math",
    "ts_markup_link",
    "ts_markup_link_label",
    "ts_markup_link_url",
    "ts_markup_link_text",
    "ts_markup_raw",
    "ts_markup_raw_block",
    "ts_markup_raw_inline",
    "ts_markup_list",
    "ts_markup_list_checked",
    "ts_markup_list_unchecked",
    "ts_markup_list_unnumbered",
    "ts_markup_list_numbered",
    "ts_diff",
    "ts_diff_plus",
    "ts_diff_plus_gutter",
    "ts_diff_minus",
    "ts_diff_minus_gutter",
    "ts_diff_delta",
    "ts_diff_delta_moved",
    "ts_diff_delta_conflict",
    "ts_diff_delta_gutter",
    "ts_tag",
    "ts_tag_builtin",
    "ts_tag_attribute",
    "ts_tag_delimiter",
    "ts_none",
    "ts_special",
    "ts_conceal",
    "ts_spell",
    "ts_nospell",
    "ts_embedded",
  ];

  const overrides = {
    Default: (val) => val.includes(",") ? val.split(",")[0] || "default" : val,
    Whitespace: (val) => val.includes("+") ? val + "f" : val + "+f",
    hop_label_head: (val) => val.includes("+") ? val + "f" : val + "+f",
    hop_label_tail: (val) => val.includes("+") ? val + "f" : val + "+f",
    InlayHint: (val) => val.includes("+") ? val + "f" : val + "+f",
    LineNumbers: (val) => val.includes(",") ? val.split(",")[0] || "default" : val,
    LineNumberCursor: (val) => val.includes(",") ? val.split(",")[0] || "default" : val,
    // Example: StatusLine remove underline if present
    // StatusLine: (val) => val.replace(/\+u/g, ""),
  };

  // Generate face definitions
  output += `# Faces\n`;

  // Apply overrides
  for (const [face, modify] of Object.entries(overrides)) {
    if (faces[face]) {
      faces[face] = modify(faces[face]);
    }
  }

  for (const [face, value] of Object.entries(faces)) {
    // Quote the value if it contains %opt references or starts with + (attributes only)
    const quotedValue = (value.includes("%opt{") || value.startsWith("+")) ? `"${value}"` : value;
    output += `set-face global ${face} ${quotedValue}\n`;
  }

  // Add missing faces with appropriate fallbacks
  const missingFaces = standardFaces.filter(face => !faces[face]);
  if (missingFaces.length > 0) {
    output += `\n# Missing faces (with fallbacks)\n`;
    for (const face of missingFaces) {
      let fallback = "Default";

      // For ts_ faces, try to find parent face
      if (face.startsWith("ts_")) {
        const parts = face.split("_");
        // Try progressively shorter parent paths
        for (let i = parts.length - 1; i > 1; i--) {
          const parentFace = parts.slice(0, i).join("_");
          if (faces[parentFace]) {
            fallback = parentFace;
            break;
          }
        }
      }

      output += `set-face global ${face} ${fallback}\n`;
    }
  }

  return output;
}

// Main function
function convertTheme(inputPath, outputPath) {
  try {
    // Read Helix theme file with inheritance support
    const helixTheme = loadThemeWithInheritance(inputPath);

    // Convert to Kakoune format
    const faces = helixToKakoune(helixTheme);

    // Generate theme name from filename
    const themeName = path.basename(inputPath, path.extname(inputPath));

    // Generate Kakoune colorscheme
    const kakTheme = generateKakouneTheme(faces, themeName, helixTheme.palette);

    // Write output. mkdir first: only kakrc and autoload/ are chezmoi-managed,
    // so ~/.config/kak/colors does not exist on a fresh machine and the write
    // would ENOENT (fresh NUC 2026-08-10).
    if (outputPath) {
      fs.mkdirSync(path.dirname(outputPath), { recursive: true });
      fs.writeFileSync(outputPath, kakTheme);
      console.log(`✓ Converted theme saved to: ${outputPath}`);
    } else {
      console.log(kakTheme);
    }
  } catch (error) {
    console.error(`Error: ${error.message}`);
    // Only the CLI may exit. As bin/theme-apply's library this function runs
    // INSIDE the host process, and the exit() that used to live here killed
    // theme-apply mid-run — past theme-apply's own try/catch, which cannot
    // catch an exit — so the whole first-boot theme bootstrap reported failure
    // over one missing directory (fresh NUC 2026-08-10). Rethrow instead: the
    // caller already warns and carries on.
    if (require.main === module) process.exit(1);
    throw error;
  }
}

// CLI
if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    console.log(`Usage: node helix-to-kak.js <input.toml> [output.kak]

Convert Helix theme files to Kakoune colorschemes.

Arguments:
  input.toml    Path to Helix theme TOML file
  output.kak    Optional output path (prints to stdout if omitted)

Example:
  node helix-to-kak.js kanagawa.toml kanagawa.kak
`);
    process.exit(0);
  }

  const inputPath = args[0];
  const outputPath = args[1];

  if (!fs.existsSync(inputPath)) {
    console.error(`Error: Input file not found: ${inputPath}`);
    process.exit(1);
  }

  convertTheme(inputPath, outputPath);
}

module.exports = { convertTheme, helixToKakoune, parseToml };
