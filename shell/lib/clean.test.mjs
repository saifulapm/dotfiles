import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import * as accounts from './accounts.mjs';
import * as btPairing from './bt-pairing.mjs';
import * as controlNet from './control-net.mjs';
import * as dekhoTitle from './dekho-title.mjs';
import * as deen from './deen.mjs';
import * as deenHadith from './deen-hadith.mjs';
import * as dns from './dns.mjs';
import * as island from './island.mjs';
import * as launcher from './launcher.mjs';
import * as lease from './lease.mjs';
import * as newtab from './newtab.mjs';
import * as notes from './notes.mjs';
import * as notesLook from './notes-look.mjs';
import * as picker from './picker.mjs';
import * as pinentry from './pinentry.mjs';
import * as questions from './questions.mjs';
import * as reminders from './reminders.mjs';
import * as tailscale from './tailscale.mjs';
import * as voice from './voice.mjs';

const lib = new URL('.', import.meta.url).pathname;

// Each export that passes text the shell did not write through a class of controls or bidi marks, called the way its surface calls it.
const ROWS = {
  'accounts context7Notice': (s) => accounts.context7Notice(s),
  'bt-pairing deviceName': (s) => btPairing.deviceName(s, ''),
  'bt-pairing serviceName': (s) => btPairing.serviceName(s),
  'control-net btRow': (s) => controlNet.btRow({ name: s, address: 'addr' }).title,
  'dekho-title links': (s) => dekhoTitle.links({ kind: 'movie', id: 1, homepage: 'https://' + s }).length,
  'deen oneLine': (s) => deen.oneLine(s),
  'deen-hadith wrapped': (s) => deenHadith.wrapped(s),
  'deen-hadith boardName': (s) => deenHadith.boardName('none', s),
  'dns writeError': (s) => dns.writeError(s),
  'dns allowArgs': (s) => dns.allowArgs({ kid: true, key: 'k' }, s),
  'dns addArgs': (s) => dns.addArgs({ mac: 'm' }, s),
  'island trackText': (s) => island.trackText({ title: s }),
  'launcher overviewChar': (s) => launcher.overviewChar(s, {}),
  'lease holder': (s) => lease.holder(s),
  'newtab siteRows': (s) => newtab.siteRows([{ url: 'https://x.org/', title: s }])[0].title,
  'notes displayText': (s) => notes.displayText(s),
  'notes-look tabLabels': (s) => notesLook.tabLabels({ sectionLabel: (x) => '#' + x }, [s], '')[0].label,
  'picker oneLine': (s) => picker.oneLine(s),
  'picker nameText': (s) => picker.nameText(s),
  'pinentry pinAnswer': (s) => pinentry.pinAnswer(s),
  'questions unbidi': (s) => questions.unbidi(s),
  'questions summary': (s) => questions.summary({ options: [1], recommend: s }),
  'reminders readReminders': (s) => reminders.readReminders(JSON.stringify([{ id: '1', text: s, due: 0, created: 0 }])).list[0].text,
  'reminders parseReminder': (s) => reminders.parseReminder('20m ' + s, 0)?.text ?? null,
  'tailscale offlineText': (s) => tailscale.offlineText(s),
  'tailscale toggleFailedText': (s) => tailscale.toggleFailedText(true, s),
  'voice inOrder': (s) => voice.inOrder(s),
  'voice line': (s) => voice.line(s),
  'voice chipLook name': (s) => voice.chipLook(null).name([s]),
  'voice marginLook tail': (s) => voice.marginLook(null).tail({ app: s, title: s }),
};

// A newline, ESC, BEL, RLO, LRI and RLM around ab; then ab alone, ab around each character one set holds and another does not, and each such character alone.
const FULL = '\n\u001b\u0007\u202e\u2066\u200fab\u200f\u2066\u202e\u0007\u001b\n';
const CHARS = ['\t', '\n', '\r', '\u0000', '\u001b', '\u007f', '\u0085', '\u009f', '\u061c', '\u200b', '\u200c', '\u200e', '\u200f', '\u202a', '\u202e', '\u2066', '\u2069', '\ufeff', '%'];
const INPUTS = [FULL, 'ab', ...CHARS.map((c) => `a${c}b`), ...CHARS];

// What each gave on the commit before the classes moved into clean.mjs, one value per input.
const BEFORE = {
  'accounts context7Notice': ["Context7 · ab is active on this device", "Context7 · ab is active on this device", "Context7 · a b is active on this device", "Context7 · a b is active on this device", "Context7 · a b is active on this device", "Context7 · a b is active on this device", "Context7 · a b is active on this device", "Context7 · a b is active on this device", "Context7 · a b is active on this device", "Context7 · a b is active on this device", "Context7 · ab is active on this device", "Context7 · a\u200bb is active on this device", "Context7 · a\u200cb is active on this device", "Context7 · ab is active on this device", "Context7 · ab is active on this device", "Context7 · ab is active on this device", "Context7 · ab is active on this device", "Context7 · ab is active on this device", "Context7 · ab is active on this device", "Context7 · a b is active on this device", "Context7 · a%b is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 · \u200b is active on this device", "Context7 · \u200c is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 ·  is active on this device", "Context7 · % is active on this device"],
  'bt-pairing deviceName': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "", "%"],
  'bt-pairing serviceName': ["service ab", "service ab", "service ab", "service ab", "service ab", "service ab", "service ab", "service ab", "service ab", "service ab", "service ab", "service a\u200bb", "service a\u200cb", "service ab", "service ab", "service ab", "service ab", "service ab", "service ab", "service ab", "service a%b", "service ", "service ", "service ", "service ", "service ", "service ", "service ", "service ", "service ", "service \u200b", "service \u200c", "service ", "service ", "service ", "service ", "service ", "service ", "service ", "service %"],
  'control-net btRow': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "addr", "addr", "addr", "addr", "addr", "addr", "addr", "addr", "addr", "\u200b", "\u200c", "addr", "addr", "addr", "addr", "addr", "addr", "addr", "%"],
  'dekho-title links': [1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2],
  'deen oneLine': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "", "%"],
  'deen-hadith wrapped': ["\n\u200fab\u200f\n", "ab", "ab", "a\nb", "ab", "ab", "ab", "ab", "ab", "ab", "a\u061cb", "a\u200bb", "a\u200cb", "a\u200eb", "a\u200fb", "ab", "ab", "ab", "ab", "a\ufeffb", "a%b", "", "\n", "", "", "", "", "", "", "\u061c", "\u200b", "\u200c", "\u200e", "\u200f", "", "", "", "", "\ufeff", "%"],
  'deen-hadith boardName': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "", "%"],
  'dns writeError': ["", "ab", "a b", "a", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "", "%"],
  'dns allowArgs': [["allow","k","ab"], ["allow","k","ab"], ["allow","k","a b"], ["allow","k","a b"], ["allow","k","a b"], ["allow","k","a b"], ["allow","k","a b"], ["allow","k","a b"], ["allow","k","a b"], ["allow","k","a b"], ["allow","k","ab"], ["allow","k","a\u200bb"], ["allow","k","a\u200cb"], ["allow","k","ab"], ["allow","k","ab"], ["allow","k","ab"], ["allow","k","ab"], ["allow","k","ab"], ["allow","k","ab"], ["allow","k","a b"], ["allow","k","a%b"], null, null, null, null, null, null, null, null, null, ["allow","k","\u200b"], ["allow","k","\u200c"], null, null, null, null, null, null, null, ["allow","k","%"]],
  'dns addArgs': [["add","m","ab"], ["add","m","ab"], ["add","m","a b"], ["add","m","a b"], ["add","m","a b"], ["add","m","a b"], ["add","m","a b"], ["add","m","a b"], ["add","m","a b"], ["add","m","a b"], ["add","m","ab"], ["add","m","a\u200bb"], ["add","m","a\u200cb"], ["add","m","ab"], ["add","m","ab"], ["add","m","ab"], ["add","m","ab"], ["add","m","ab"], ["add","m","ab"], ["add","m","a b"], ["add","m","a%b"], null, null, null, null, null, null, null, null, null, ["add","m","\u200b"], ["add","m","\u200c"], null, null, null, null, null, null, null, ["add","m","%"]],
  'island trackText': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "", "%"],
  'launcher overviewChar': ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "\u0085", "\u009f", "\u061c", "\u200b", "\u200c", "\u200e", "\u200f", "\u202a", "\u202e", "\u2066", "\u2069", "\ufeff", "%"],
  'lease holder': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "agent", "agent", "agent", "agent", "agent", "agent", "agent", "agent", "agent", "\u200b", "\u200c", "agent", "agent", "agent", "agent", "agent", "agent", "agent", "%"],
  'newtab siteRows': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "x.org", "x.org", "x.org", "x.org", "x.org", "x.org", "x.org", "x.org", "x.org", "\u200b", "\u200c", "x.org", "x.org", "x.org", "x.org", "x.org", "x.org", "x.org", "%"],
  'notes displayText': ["\n\u001b\u0007⟨U+202E⟩⟨U+2066⟩⟨U+200F⟩ab⟨U+200F⟩⟨U+2066⟩⟨U+202E⟩\u0007\u001b\n", "ab", "a\tb", "a\nb", "a\rb", "a\u0000b", "a\u001bb", "a\u007fb", "a\u0085b", "a\u009fb", "a⟨U+61C⟩b", "a\u200bb", "a\u200cb", "a⟨U+200E⟩b", "a⟨U+200F⟩b", "a⟨U+202A⟩b", "a⟨U+202E⟩b", "a⟨U+2066⟩b", "a⟨U+2069⟩b", "a\ufeffb", "a%b", "\t", "\n", "\r", "\u0000", "\u001b", "\u007f", "\u0085", "\u009f", "⟨U+61C⟩", "\u200b", "\u200c", "⟨U+200E⟩", "⟨U+200F⟩", "⟨U+202A⟩", "⟨U+202E⟩", "⟨U+2066⟩", "⟨U+2069⟩", "\ufeff", "%"],
  'notes-look tabLabels': ["#⟨U+202E⟩⟨U+2066⟩⟨U+200F⟩ab⟨U+200F⟩⟨U+2066⟩⟨U+202E⟩", "#ab", "#a b", "#a b", "#a b", "#a b", "#a b", "#a b", "#a b", "#a b", "#a⟨U+61C⟩b", "#a\u200bb", "#a\u200cb", "#a⟨U+200E⟩b", "#a⟨U+200F⟩b", "#a⟨U+202A⟩b", "#a⟨U+202E⟩b", "#a⟨U+2066⟩b", "#a⟨U+2069⟩b", "#a\ufeffb", "#a%b", "#", "#", "#", "#", "#", "#", "#", "#", "#⟨U+61C⟩", "#\u200b", "#\u200c", "#⟨U+200E⟩", "#⟨U+200F⟩", "#⟨U+202A⟩", "#⟨U+202E⟩", "#⟨U+2066⟩", "#⟨U+2069⟩", "#", "#%"],
  'picker oneLine': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "", "%"],
  'picker nameText': ["ab", "ab", "ab", "ab", "ab", "ab", "ab", "ab", "ab", "ab", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a\ufeffb", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "\ufeff", "%"],
  'pinentry pinAnswer': ["D %0A%1B%07\u202e\u2066\u200fab\u200f\u2066\u202e%07%1B%0A\nOK\n", "D ab\nOK\n", "D a%09b\nOK\n", "D a%0Ab\nOK\n", "D a%0Db\nOK\n", "D a%00b\nOK\n", "D a%1Bb\nOK\n", "D a%7Fb\nOK\n", "D a\u0085b\nOK\n", "D a\u009fb\nOK\n", "D a\u061cb\nOK\n", "D a\u200bb\nOK\n", "D a\u200cb\nOK\n", "D a\u200eb\nOK\n", "D a\u200fb\nOK\n", "D a\u202ab\nOK\n", "D a\u202eb\nOK\n", "D a\u2066b\nOK\n", "D a\u2069b\nOK\n", "D a\ufeffb\nOK\n", "D a%25b\nOK\n", "D %09\nOK\n", "D %0A\nOK\n", "D %0D\nOK\n", "D %00\nOK\n", "D %1B\nOK\n", "D %7F\nOK\n", "D \u0085\nOK\n", "D \u009f\nOK\n", "D \u061c\nOK\n", "D \u200b\nOK\n", "D \u200c\nOK\n", "D \u200e\nOK\n", "D \u200f\nOK\n", "D \u202a\nOK\n", "D \u202e\nOK\n", "D \u2066\nOK\n", "D \u2069\nOK\n", "D \ufeff\nOK\n", "D %25\nOK\n"],
  'questions unbidi': ["\n\u001b\u0007ab\u0007\u001b\n", "ab", "a\tb", "a\nb", "a\rb", "a\u0000b", "a\u001bb", "a\u007fb", "a\u0085b", "a\u009fb", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a\ufeffb", "a%b", "\t", "\n", "\r", "\u0000", "\u001b", "\u007f", "\u0085", "\u009f", "", "\u200b", "\u200c", "", "", "", "", "", "", "\ufeff", "%"],
  'questions summary': ["1 option · ★ \n\u001b\u0007ab\u0007\u001b\n", "1 option · ★ ab", "1 option · ★ a\tb", "1 option · ★ a\nb", "1 option · ★ a\rb", "1 option · ★ a\u0000b", "1 option · ★ a\u001bb", "1 option · ★ a\u007fb", "1 option · ★ a\u0085b", "1 option · ★ a\u009fb", "1 option · ★ ab", "1 option · ★ a\u200bb", "1 option · ★ a\u200cb", "1 option · ★ ab", "1 option · ★ ab", "1 option · ★ ab", "1 option · ★ ab", "1 option · ★ ab", "1 option · ★ ab", "1 option · ★ a\ufeffb", "1 option · ★ a%b", "1 option · ★ \t", "1 option · ★ \n", "1 option · ★ \r", "1 option · ★ \u0000", "1 option · ★ \u001b", "1 option · ★ \u007f", "1 option · ★ \u0085", "1 option · ★ \u009f", "1 option · ★ ", "1 option · ★ \u200b", "1 option · ★ \u200c", "1 option · ★ ", "1 option · ★ ", "1 option · ★ ", "1 option · ★ ", "1 option · ★ ", "1 option · ★ ", "1 option · ★ \ufeff", "1 option · ★ %"],
  'reminders readReminders': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "", "%"],
  'reminders parseReminder': ["ab", "ab", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "a b", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", null, null, null, null, null, null, null, null, null, "\u200b", "\u200c", null, null, null, null, null, null, null, "%"],
  'tailscale offlineText': ["ab is offline", "ab is offline", "a b is offline", "a b is offline", "a b is offline", "a b is offline", "a b is offline", "a b is offline", "a b is offline", "a b is offline", "ab is offline", "a\u200bb is offline", "a\u200cb is offline", "ab is offline", "ab is offline", "ab is offline", "ab is offline", "ab is offline", "ab is offline", "a b is offline", "a%b is offline", " is offline", " is offline", " is offline", " is offline", " is offline", " is offline", " is offline", " is offline", " is offline", "\u200b is offline", "\u200c is offline", " is offline", " is offline", " is offline", " is offline", " is offline", " is offline", " is offline", "% is offline"],
  'tailscale toggleFailedText': ["Tailscale not turned off", "Tailscale not turned off · ab", "Tailscale not turned off · a b", "Tailscale not turned off · a", "Tailscale not turned off · a b", "Tailscale not turned off · a b", "Tailscale not turned off · a b", "Tailscale not turned off · a b", "Tailscale not turned off · a b", "Tailscale not turned off · a b", "Tailscale not turned off · ab", "Tailscale not turned off · a\u200bb", "Tailscale not turned off · a\u200cb", "Tailscale not turned off · ab", "Tailscale not turned off · ab", "Tailscale not turned off · ab", "Tailscale not turned off · ab", "Tailscale not turned off · ab", "Tailscale not turned off · ab", "Tailscale not turned off · a b", "Tailscale not turned off · a%b", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off · \u200b", "Tailscale not turned off · \u200c", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off", "Tailscale not turned off · %"],
  'voice inOrder': ["\nab\n", "ab", "a\tb", "a\nb", "a\rb", "ab", "ab", "ab", "ab", "ab", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a\ufeffb", "a%b", "\t", "\n", "\r", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "\ufeff", "%"],
  'voice line': ["ab", "ab", "a b", "a b", "a b", "ab", "ab", "ab", "ab", "ab", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "", "%"],
  'voice chipLook name': ["ab", "ab", "a b", "a b", "a b", "ab", "ab", "ab", "ab", "ab", "ab", "a\u200bb", "a\u200cb", "ab", "ab", "ab", "ab", "ab", "ab", "a b", "a%b", "", "", "", "", "", "", "", "", "", "\u200b", "\u200c", "", "", "", "", "", "", "", "%"],
  'voice marginLook tail': [" / ab — ab", " / ab — ab", " / a b — a b", " / a b — a b", " / a b — a b", " / a b — a b", " / a b — a b", " / a b — a b", " / a b — a b", " / a b — a b", " / ab — ab", " / a\u200bb — a\u200bb", " / a\u200cb — a\u200cb", " / ab — ab", " / ab — ab", " / ab — ab", " / ab — ab", " / ab — ab", " / ab — ab", " / a b — a b", " / a%b — a%b", " /  — ", " /  — ", " /  — ", " /  — ", " /  — ", " /  — ", " /  — ", " /  — ", " /  — ", " / \u200b — \u200b", " / \u200c — \u200c", " /  — ", " /  — ", " /  — ", " /  — ", " /  — ", " /  — ", " /  — ", " / % — %"],
};

for (const [name, fn] of Object.entries(ROWS)) {
  test(`${name} cleans each input as it did before the classes moved`, () => {
    assert.deepEqual(INPUTS.map(fn), BEFORE[name]);
  });
}

// What a reviewer cannot see in an editor: C0 but the newline, DEL and C1, the zero-width and bidi characters, and the BOM.
const INVISIBLE = /[\u0000-\u0009\u000b-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069\u061c\ufeff]/;

test('clean.mjs and its test write every invisible character as an escape', () => {
  for (const f of ['clean.mjs', 'clean.test.mjs']) assert.equal(INVISIBLE.exec(readFileSync(lib + f, 'utf8')), null, f);
});

// Code points a class may not hold outside clean.mjs: C0, DEL and C1, and the bidi marks, embeddings, overrides and isolates.
const BANNED = [[0x00, 0x1f], [0x7f, 0x9f], [0x61c, 0x61c], [0x200e, 0x200f], [0x202a, 0x202e], [0x2066, 0x2069]];

// The code point of one class member at i, or null for \t, \n, \s and the other named escapes, which name whitespace and not a control range.
function member(body, i) {
  if (body[i] !== '\\') return { cp: body.codePointAt(i), next: i + (body.codePointAt(i) > 0xffff ? 2 : 1) };
  const m = /^\\(?:x([0-9a-f]{2})|u\{([0-9a-f]+)\}|u([0-9a-f]{4})|([0-7]{1,3})|c([a-z]))/i.exec(body.slice(i));
  if (!m) return { cp: /[a-z]/i.test(body[i + 1] ?? '') ? null : body.codePointAt(i + 1), next: i + 2 };
  const cp = m[5] ? m[5].toUpperCase().charCodeAt(0) % 32 : m[4] ? parseInt(m[4], 8) : parseInt(m[1] || m[2] || m[3], 16);
  return { cp, next: i + m[0].length };
}

// True when a class body, the text between [ and ], holds a banned code point or a range over one.
function holdsBanned(body) {
  for (let i = 0; i < body.length; ) {
    const a = member(body, i);
    let lo = a.cp;
    let hi = a.cp;
    i = a.next;
    if (body[i] === '-' && i + 1 < body.length) {
      const b = member(body, i + 1);
      if (a.cp !== null && b.cp !== null) hi = b.cp;
      i = b.next;
    }
    if (lo !== null && BANNED.some(([from, to]) => lo <= to && hi >= from)) return true;
  }
  return false;
}

// A property escape naming the controls, the format characters or the bidi controls, which names a set without listing it.
const PROPERTY = /\\[pP]\{(?:(?:gc|General_Category)=)?(?:C|Cc|Cf|Other|Control|Format|Bidi_C|Bidi_Control)\}/;
// A bidi mark anywhere on a line, raw or escaped, since no module but clean.mjs has a reason to write one.
const BIDI_ANYWHERE = /[\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]|\\u(?:061c|200[ef]|202[a-e]|206[6-9])|\\u\{(?:61c|200[ef]|202[a-e]|206[6-9])\}/i;

// Each run from [ to ] on each line, read as written and with doubled backslashes halved, so a class built in a string for new RegExp counts too; and any line with a property escape or a bidi mark outside a class.
function bannedLines(src) {
  const found = [];
  src.split('\n').forEach((text, n) => {
    for (const variant of [text, text.replace(/\\\\/g, '\\')]) {
      if (PROPERTY.test(variant) || BIDI_ANYWHERE.test(variant) || [...variant.matchAll(/\[((?:\\.|[^\]\\])*)\]/g)].some((m) => holdsBanned(m[1]))) {
        found.push(n + 1);
        break;
      }
    }
  });
  return found;
}

test('the scan finds a banned class written raw or escaped, in either case', () => {
  const raw = (cp) => String.fromCharCode(cp);
  for (const src of [`/[${raw(0x200e)}]/`, `/[${raw(0x202a)}-${raw(0x202e)}]/`, '/[\\u200E]/', '/[\\u200e]/', '/[\\x00-\\x1f]/', '/[\\u007F]/','/[%\\x00-\\x1F\\x7f]/', "new RegExp('[\\\\u0000-\\\\u001f]')", '/[^\\s\\u200b-\\u200f]/', '/[a\\u{2066}]/u', '/[\\0]/']) {
    assert.deepEqual(bannedLines(src), [1], src);
  }
  // The spellings that name a set without listing it: a property escape, a bidi mark outside a class, and octal.
  for (const src of ['/[\\p{Cc}]/gu', '/\\P{Cc}/u', '/\\p{Bidi_Control}/gu', '/\\p{gc=Control}/u', '/[\\p{Cf}]/u', '/\\u202E/g', '/\\u{2066}/gu', `/${raw(0x202e)}/g`, '/[\\1-\\37]/']) {
    assert.deepEqual(bannedLines(src), [1], src);
  }
  for (const src of ['/[\\p{L}\\p{N}]/u', '/^[\\x21-\\x7e]$/', '/[\\u200c\\u200d]/', '/[\\s\\S]/', '/[^\\n\\t]/', "text.split('\\0')", '`\\x1b]${body}\\x1b\\\\`', "['a', 'b']"]) {
    assert.deepEqual(bannedLines(src), [], src);
  }
});

test('no module of the library but clean.mjs defines a class of controls or bidi marks', () => {
  const found = [];
  for (const f of readdirSync(lib).filter((f) => f.endsWith('.mjs') && !f.endsWith('.test.mjs') && f !== 'clean.mjs').sort()) {
    for (const n of bannedLines(readFileSync(lib + f, 'utf8'))) found.push(`${f}:${n}`);
  }
  assert.deepEqual(found, []);
});
