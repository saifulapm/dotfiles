// Guard: every Text element in the shell declares a textFormat. Run with:
//
//     node shell/textFormat.test.js
//
// WHY THIS IS A TEST AND NOT A CONVENTION. Qt's default is Text.AutoText,
// which SNIFFS the string and renders anything that looks like markup as rich
// text. Almost every string this shell draws comes from somewhere we do not
// control — wifi SSIDs, window titles, notification summaries, MPRIS track
// names, filenames, tray menu labels, TMDB overviews — so a body containing
// `<img src="http://host/x">` makes the shell issue that GET with no user
// action, and `<font color=…>` lets a sender repaint our chrome.
//
// StyledText and OpticalGlyph default to PlainText, which covers most of the
// tree; this catches the raw `Text {` elements, where the default is Qt's.
// A new one is easy to add without thinking about it, which is exactly the
// case a guard is for.
//
// The check is deliberately SHALLOW-SCOPED: it only accepts a textFormat
// declared at the element's own brace depth, so a nested child carrying one
// cannot satisfy its parent. Upstream hit precisely that (omarchy 0260d2ac,
// "Stop the textFormat test from passing when it has not checked").

const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.join(__dirname);

function qmlFiles(dir) {
    const out = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory())
            out.push(...qmlFiles(full));
        else if (entry.name.endsWith(".qml"))
            out.push(full);
    }
    return out;
}

// Every `Text {` opening and whether its OWN scope declares a textFormat.
function offenders(source) {
    const lines = source.split("\n");
    const bad = [];
    for (let i = 0; i < lines.length; i++) {
        if (!/^\s*Text\s*\{\s*$/.test(lines[i]))
            continue;
        let depth = 1;
        let found = false;
        for (let j = i + 1; j < lines.length && depth > 0; j++) {
            if (depth === 1 && /^\s*textFormat\s*:/.test(lines[j]))
                found = true;
            for (const ch of lines[j]) {
                if (ch === "{")
                    depth++;
                else if (ch === "}")
                    depth--;
            }
        }
        if (!found)
            bad.push(i + 1);
    }
    return bad;
}

// The scanner has to be able to fail, or a green run means nothing. Upstream's
// test passed for a while without checking anything at all.
let selfTestFailures = 0;
function selfTest(name, source, expected) {
    const got = offenders(source);
    const ok = JSON.stringify(got) === JSON.stringify(expected);
    if (!ok) {
        selfTestFailures++;
        console.log(`FAIL  self-test: ${name}\n      expected ${JSON.stringify(expected)}, got ${JSON.stringify(got)}`);
    } else {
        console.log(`  ok  self-test: ${name}`);
    }
}

selfTest("a bare Text is caught", "Item {\n    Text {\n        text: \"x\"\n    }\n}", [2]);
selfTest("a declared Text passes", "Item {\n    Text {\n        textFormat: Text.PlainText\n    }\n}", []);
selfTest("StyledText opt-out passes", "Item {\n    Text {\n        textFormat: Text.StyledText\n    }\n}", []);
// The bug upstream shipped: a child's declaration must not satisfy the parent.
selfTest("a nested child's textFormat does NOT satisfy its parent", "Item {\n    Text {\n        Rectangle {\n            Text {\n                textFormat: Text.PlainText\n            }\n        }\n    }\n}", [2]);

let failures = 0;
for (const file of qmlFiles(ROOT)) {
    const bad = offenders(fs.readFileSync(file, "utf8"));
    if (bad.length > 0) {
        failures += bad.length;
        console.log(`FAIL  ${path.relative(ROOT, file)}: Text without textFormat at line(s) ${bad.join(", ")}`);
    }
}

if (selfTestFailures > 0) {
    console.log(`\n${selfTestFailures} self-test(s) failing — the scanner itself is broken, ignore the result above`);
    process.exit(1);
}
console.log(failures === 0 ? "\nevery Text element declares a textFormat" : `\n${failures} Text element(s) missing textFormat`);
process.exit(failures === 0 ? 0 : 1);
