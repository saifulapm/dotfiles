import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// A handler of a readonly binding runs inside the change that moved it, while other bindings of the same sources may still hold their old values; five defects came from one reading them (lessons, 2026-11-19). So a handler that assigns defers through Qt.callLater, or a comment line just above it says why it need not.
const shell = new URL('..', import.meta.url).pathname;

// Each `on<Name>Changed` of a readonly property the same file declares, whose body assigns, with no Qt.callLater in it and no `// Not deferred:` line just above: [line, name].
export function staleHandlers(src) {
  const lines = src.split('\n');
  const readonly = new Set([...src.matchAll(/readonly property [\w.<>]+ (\w+)\s*:/g)].map((m) => m[1]));
  const found = [];
  lines.forEach((line, i) => {
    const m = line.match(/^\s*on([A-Z]\w*)Changed\s*:\s*(.*)$/);
    if (!m) return;
    const name = m[1][0].toLowerCase() + m[1].slice(1);
    if (!readonly.has(name)) return;
    let body = m[2];
    if (body.trim().startsWith('{')) {
      let depth = 0;
      body = '';
      for (let j = i; j < lines.length; j++) {
        const s = j === i ? m[2] : lines[j];
        body += s + '\n';
        for (const c of s) depth += c === '{' ? 1 : c === '}' ? -1 : 0;
        if (depth <= 0) break;
      }
    }
    const code = body
      .replace(/\/\/.*$/gm, '')
      .replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/g, '""')
      .replace(/\b(?:const|let|var)\s+\w+\s*=/g, '');
    if (!/(?:^|[^=!<>+\-*/%&|?])=(?![=>])/.test(code) || /Qt\.callLater/.test(code)) return;
    if (/^\s*\/\/ Not deferred: \S/.test(lines[i - 1] ?? '')) return;
    found.push([i + 1, name]);
  });
  return found;
}

test('the stale-handler lint flags an assigning handler of a readonly binding, and passes a deferred, explained or reading one', () => {
  const ro = 'Item {\n  readonly property var rows: list.filter(r => r.ok)\n  property int selected: 0\n';
  assert.deepEqual(staleHandlers(ro + '  onRowsChanged: selected = 0\n}\n'), [[4, 'rows']]);
  assert.deepEqual(staleHandlers(ro + '  onRowsChanged: {\n    const i = rows.indexOf(x);\n    selected = i;\n  }\n}\n'), [[4, 'rows']]);
  assert.deepEqual(staleHandlers(ro + '  onRowsChanged: Qt.callLater(() => { selected = 0 })\n}\n'), []);
  assert.deepEqual(staleHandlers(ro + '  // Not deferred: rows is the only value it reads.\n  onRowsChanged: selected = 0\n}\n'), []);
  // A comparison, an arrow, a local and a call are not assignments, and a plain property's handler is not this lint's.
  assert.deepEqual(staleHandlers(ro + '  onRowsChanged: {\n    const n = rows.length;\n    if (n === 0 || n >= 3) fetch(rows.map(r => r.id));\n  }\n}\n'), []);
  assert.deepEqual(staleHandlers(ro + '  onSelectedChanged: selected = 1\n}\n'), []);
  // The explanation sits on the line just above, not somewhere earlier.
  assert.deepEqual(staleHandlers(ro + '  // Not deferred: x\n\n  onRowsChanged: selected = 0\n}\n'), [[6, 'rows']]);
});

// These were written before the lint and are not yet read for a stale value; some pair two bindings of one source (ControlBluetooth's rows and devices). Take one off as it is deferred or explained, and add none.
const older = new Set([
  'Chat.qml onPickedChanged', 'ControlAudio.qml onEntriesChanged', 'ControlBluetooth.qml onRowsChanged', 'ControlWifi.qml onRowsChanged',
  'Goals.qml onListChanged', 'Island.qml onScreencopyPidsChanged', 'Island.qml onSlotsChanged', 'Island.qml onModeChanged', 'Island.qml onAtChanged',
  'Launcher.qml onQueryChanged', 'Launcher.qml onModeChanged', 'Motion.qml onOpenChanged', 'Notes.qml onFocusedChanged', 'Notifications.qml onQueryChanged',
  'Pass.qml onQueryChanged', 'services/Media.qml onPlayerChanged', 'services/Osd.qml onSinkChanged', 'services/Reminders.qml onSoonestChanged',
]);

test('every assigning handler of a readonly binding under shell/ defers or says why not', () => {
  const found = readdirSync(shell, { recursive: true })
    .filter((f) => f.endsWith('.qml'))
    .flatMap((f) => staleHandlers(readFileSync(join(shell, f), 'utf8')).map(([line, name]) => [f, line, `on${name[0].toUpperCase()}${name.slice(1)}Changed`]));
  assert.deepEqual(found.filter(([f, , h]) => !older.has(`${f} ${h}`)).map(([f, line, h]) => `${f}:${line} ${h}`), [], 'defer through Qt.callLater, or put a `// Not deferred: <why>` line above');
  // A handler on the older list that is gone or now passes comes off it, so the list only shrinks.
  assert.deepEqual([...older].filter((k) => !found.some(([f, , h]) => `${f} ${h}` === k)), []);
});
