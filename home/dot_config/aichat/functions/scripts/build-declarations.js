#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const TOOL_ENTRY_FUNC = "run";

function main() {
  const scriptfile = process.argv[2];
  const isTool = path.dirname(scriptfile) == "tools";
  const contents = fs.readFileSync(process.argv[2], "utf8");
  const functions = extractFunctions(contents, isTool);
  let declarations = [];
  for (const { funcName, jsdoc } of functions) {
    const { description, params } = parseJsDoc(jsdoc, funcName);
    if (!description) continue;
    const declaration = buildDeclaration(funcName, description, params);
    declarations.push(declaration);
  }
  if (isTool) {
    const name = getBasename(scriptfile);
    if (declarations.length > 0) {
      declarations = declarations.slice(0, 1);
      declarations[0].name = name;
    }
  }
  console.log(JSON.stringify(declarations, null, 2));
}

/**
 * @param {string} contents
 * @param {bool} isTool
 */
function extractFunctions(contents, isTool) {
  const output = [];
  const lines = contents.split("\n");
  let isInComment = false;
  let jsdoc = "";
  let incompleteComment = "";
  for (let line of lines) {
    if (/^\s*\/\*/.test(line)) {
      isInComment = true;
      incompleteComment += `\n${line}`;
    } else if (/^\s*\*\//.test(line)) {
      isInComment = false;
      incompleteComment += `\n${line}`;
      jsdoc = incompleteComment;
      incompleteComment = "";
    } else if (isInComment) {
      incompleteComment += `\n${line}`;
    } else {
      if (!jsdoc || line.trim() === "") {
        continue;
      }
      if (isTool) {
        if (new RegExp(`^export (async )?function ${TOOL_ENTRY_FUNC}|^exports\.${TOOL_ENTRY_FUNC}`).test(line)) {
          output.push({
            funcName: TOOL_ENTRY_FUNC,
            jsdoc,
          });
        }
      } else {
        let match = /^export (async )?function ([A-Za-z0-9_]+)/.exec(line);
        let funcName = null;
        if (match) {
          funcName = match[2];
        }
        if (!funcName) {
          match = /^exports\.([A-Za-z0-9_]+) = (async )?function /.exec(line);
          if (match) {
            funcName = match[1];
          }
        }
        if (funcName && !funcName.startsWith("_")) {
          output.push({ funcName, jsdoc });
        }
      }
      jsdoc = "";
    }
  }
  return output;
}

/**
 * @param {string} jsdoc
 * @param {string} funcName,
 */
function parseJsDoc(jsdoc, funcName) {
  const lines = jsdoc.split("\n");
  let description = "";
  const rawParams = [];
  let tag = "";
  for (let line of lines) {
    line = line.replace(/^\s*(\/\*\*|\*\/|\*)/, "").trim();
    let match = /^@(\w+)/.exec(line);
    if (match) {
      tag = match[1];
    }
    if (!tag) {
      description += `\n${line}`;
    } else if (tag == "property") {
      if (match) {
        rawParams.push(line.slice(tag.length + 1).trim());
      } else {
        rawParams[rawParams.length - 1] += `\n${line}`;
      }
    }
  }
  const params = [];
  for (const rawParam of rawParams) {
    try {
      params.push(parseParam(rawParam));
    } catch (err) {
      throw new Error(
        `Unable to parse function '${funcName}' of jsdoc '@property ${rawParam}'`,
      );
    }
  }
  return {
    description: description.trim(),
    params,
  };
}

/**
 * @typedef {ReturnType<parseParam>} Param
 */

/**
 * @param {string} rawParam
 */
function parseParam(rawParam) {
  const regex = /^{([^}]+)} +(\S+)( *- +| +)?/;
  const match = regex.exec(rawParam);
  if (!match) {
    throw new Error(`Invalid jsdoc comment`);
  }
  const type = match[1];
  let name = match[2];
  const description = rawParam.replace(regex, "");

  // Extract default value if present (must be done before optional check)
  let defaultValue = null;
  let required = true;

  // Check for default value syntax: [propertyName=defaultValue]
  const defaultMatch = /^\[([^=\]]+)=(.+)\]$/.exec(name);
  if (defaultMatch) {
    name = defaultMatch[1];
    defaultValue = defaultMatch[2];
    required = false;
  } else if (/^\[.*\]$/.test(name)) {
    // Optional property without default value: [propertyName]
    name = name.slice(1, -1);
    required = false;
  }

  // Handle nested object properties (e.g., "codeblocks[].fileName")
  if (name.includes('[]')) {
    // For nested properties, extract the actual property name after []
    const nestedMatch = /\[\]\.(.+)/.exec(name);
    if (nestedMatch) {
      const propertyName = nestedMatch[1];
      // Check for default value in nested property name
      const nestedDefaultMatch = /^([^=]+)=(.+)$/.exec(propertyName);
      if (nestedDefaultMatch) {
        const cleanPropertyName = nestedDefaultMatch[1];
        defaultValue = nestedDefaultMatch[2];
        name = name.replace(/\[\]\..*/, `[].${cleanPropertyName}`);
      }
    }
    return { name, type, description, required, defaultValue, isNestedProperty: true };
  }

  let property = buildProperty(type, description, defaultValue);
  return { name, property, required };
}

/**
 * @param {string} type
 * @param {string} description
 * @param {string} defaultValue
 */
function buildProperty(type, description, defaultValue = null) {
  type = type.toLowerCase();
  const property = {};
  // Handle enum arrays like ('a'|'b')[]
  const enumArrayMatch = /^\(([^)]+)\)\[\]$/.exec(type);
  if (enumArrayMatch) {
    property.type = "array";
    property.items = {
      type: "string",
      enum: enumArrayMatch[1].replace(/'/g, "").split("|")
    };
  } else if (type.includes("|")) {
    property.type = "string";
    property.enum = type.replace(/'/g, "").split("|");
  } else if (/^'[^']+'$/.test(type)) {
    // Single enum value: 'admin'
    property.type = "string";
    property.enum = [type.replace(/'/g, "")];
  } else if (type === "boolean") {
    property.type = "boolean";
  } else if (type === "string") {
    property.type = "string";
  } else if (type === "integer") {
    property.type = "integer";
  } else if (type === "number") {
    property.type = "number";
  } else if (type === "string[]") {
    property.type = "array";
    property.items = { type: "string" };
  } else if (type === "object[]") {
    property.type = "array";
    property.items = { type: "object" };
  } else {
    throw new Error(`Unsupported type '${type}'`);
  }
  property.description = description;
  if (defaultValue !== null) {
    // Handle different default value types
    if (property.type === "array") {
      // For arrays, try to parse as JSON array, fallback to single value
      try {
        property.default = JSON.parse(defaultValue);
      } catch {
        // If not valid JSON, treat as single string value and wrap in array
        property.default = [defaultValue.replace(/^["']|["']$/g, '')];
      }
    } else if (property.type === "boolean") {
      property.default = defaultValue === "true";
    } else if (property.type === "integer") {
      property.default = parseInt(defaultValue);
    } else if (property.type === "number") {
      property.default = parseFloat(defaultValue);
    } else {
      property.default = defaultValue.replace(/^["']|["']$/g, ''); // Remove quotes
    }
  }
  return property;
}

/**
 * @param {string} name
 * @param {string} description
 * @param {Param[]} params
 */
function buildDeclaration(name, description, params) {
  const declaration = {
    name,
    description,
    parameters: {
      type: "object",
      properties: {},
    },
  };
  const schema = declaration.parameters;
  const requiredParams = [];
  const nestedObjects = {};

  for (const param of params) {
    if (param.isNestedProperty) {
      // Handle nested object properties like "codeblocks[].fileName"
      const [parentName, childName] = param.name.split('[].');
      if (!nestedObjects[parentName]) {
        nestedObjects[parentName] = {
          type: "array",
          items: {
            type: "object",
            properties: {},
            required: []
          }
        };
      }

      const childProperty = buildProperty(param.type, param.description, param.defaultValue);
      nestedObjects[parentName].items.properties[childName] = childProperty;

      if (param.required) {
        nestedObjects[parentName].items.required.push(childName);
      }
    } else {
      const { name, property, required } = param;
      // Check if this is meant to be a parent for nested objects
      if (property.type === "array" && property.items && property.items.type === "object" && nestedObjects[name]) {
        schema.properties[name] = nestedObjects[name];
      } else {
        schema.properties[name] = property;
      }
      if (required) {
        requiredParams.push(name);
      }
    }
  }

  // Add nested objects to schema
  for (const [parentName, nestedSchema] of Object.entries(nestedObjects)) {
    if (nestedSchema.items.required.length === 0) {
      delete nestedSchema.items.required;
    }

    schema.properties[parentName] = nestedSchema;
  }

  if (requiredParams.length > 0) {
    schema.required = requiredParams;
  }
  return declaration;
}

/**
 * @param {string} filePath
 */
function getBasename(filePath) {
  const filenameWithExt = filePath.split(/[/\\]/).pop();

  const lastDotIndex = filenameWithExt.lastIndexOf(".");

  if (lastDotIndex === -1) {
    return filenameWithExt;
  }

  return filenameWithExt.substring(0, lastDotIndex);
}

main();
