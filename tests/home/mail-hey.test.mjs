// bin/mail hey on a scratch store (tests/home/mail-rig.mjs): an agent files mail only in ways that can be undone, on one message it names, and screens out only a sender Saiful names.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mailRig, repo } from './mail-rig.mjs';

function rig(t) {
  const r = mailRig(t);
  const mail = (...args) => {
    const res = r.run(join(repo, 'bin/mail'), args);
    let json = null;
    try {
      json = JSON.parse(res.stdout);
    } catch {}
    return { ...res, json };
  };
  // A newsletter in the Imbox, and a person's mail beside it.
  r.deliver({ From: 'Shop News <news@shop.test>', Subject: 'sale', 'Message-ID': '<h1@shop.test>' });
  r.deliver({ From: 'Bob <bob@people.test>', Subject: 'lunch', 'Message-ID': '<b1@x.test>' });
  r.notmuch('tag', '+screened', '-new', '--', '*');
  const tags = (id) => r.notmuch('search', '--output=tags', '--', `id:${id}`).split('\n').filter(Boolean);
  const imbox = () => mail('search', '--box', 'Imbox').json.data.map((row) => row.id);
  return { ...r, mail, tags, imbox };
}

test('mail hey feed moves the sender to The Feed, and the mail leaves the Imbox', (t) => {
  const r = rig(t);
  assert.ok(r.imbox().includes('h1@shop.test'));
  const res = r.mail('hey', 'feed', 'id:h1@shop.test');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.match(r.db('thefeed.db'), /^news@shop\.test$/m);
  assert.deepEqual(r.imbox(), ['b1@x.test']);
  assert.ok(r.tags('h1@shop.test').includes('thefeed'));
});

test('mail hey replylater, setaside, archive and bubble each set their tag on the thread', (t) => {
  const r = rig(t);
  const day = new Date(Date.now() + 10 * 86400e3).toISOString().slice(0, 10);
  for (const [action, extra, tag] of [['replylater', [], 'replylater'], ['setaside', [], 'setaside'], ['archive', [], 'archived'], ['bubble', ['--at', day], 'bubble']]) {
    const res = r.mail('hey', action, 'b1@x.test', ...extra);
    assert.equal(res.status, 0, `${action}: ${res.stdout}${res.stderr}`);
    assert.ok(r.tags('b1@x.test').includes(tag), `${action} sets ${tag}`);
  }
  assert.ok(!r.tags('b1@x.test').includes('inbox'), 'archive and bubble take it out of the inbox');
  assert.match(r.db('bubble.db'), /^id:b1@x\.test \d+$/m);
  const cleared = r.mail('hey', 'clear', 'b1@x.test');
  assert.equal(cleared.status, 0, cleared.stdout);
  assert.ok(!r.tags('b1@x.test').includes('replylater'));
});

test('mail hey screen-in and papertrail decide on the sender of the message', (t) => {
  const r = rig(t);
  r.deliver({ From: 'Carol <carol@new.test>', Subject: 'hello', 'Message-ID': '<c1@x.test>' });
  assert.equal(r.mail('hey', 'screen-in', 'c1@x.test').status, 0);
  assert.match(r.db('screened.db'), /^carol@new\.test$/m);
  const res = r.mail('hey', 'papertrail', 'h1@shop.test', '--category', 'receipts');
  assert.equal(res.status, 0, res.stdout);
  assert.match(r.db('ledger.db'), /^receipts news@shop\.test$/m);
});

test('mail hey screen-out takes only a sender, never a message', (t) => {
  const r = rig(t);
  const byId = r.mail('hey', 'screen-out', 'id:h1@shop.test');
  assert.equal(byId.status, 1, byId.stdout);
  assert.equal(byId.json.error, 'screen-out takes --sender ADDR');
  assert.equal(r.db('spam.db'), '');
  const res = r.mail('hey', 'screen-out', '--sender', 'news@shop.test');
  assert.equal(res.status, 0, res.stdout + res.stderr);
  assert.match(r.db('spam.db'), /^news@shop\.test$/m);
  assert.ok(!r.imbox().includes('h1@shop.test'));
  for (const bad of ['a b@x.test', 'news@shop.test or *', 'not-an-address']) {
    const res2 = r.mail('hey', 'screen-out', '--sender', bad);
    assert.equal(res2.status, 1, `${bad}: ${res2.stdout}`);
  }
});

test('mail hey acts on one message it can find, never on a query', (t) => {
  const r = rig(t);
  for (const q of ['*', 'tag:inbox', 'from:bob@people.test']) {
    const res = r.mail('hey', 'archive', q);
    assert.equal(res.status, 2, `${q}: ${res.stdout}`);
  }
  assert.deepEqual(r.imbox().sort(), ['b1@x.test', 'h1@shop.test']);
  const sender = r.mail('hey', 'archive', 'b1@x.test', '--sender', 'bob@people.test');
  assert.equal(sender.status, 1, sender.stdout);
  const unknown = r.mail('hey', 'mute', 'b1@x.test');
  assert.equal(unknown.status, 1, unknown.stdout);
});

test('mail hey decides on no address holding a *, which notmuch reads as every sender', (t) => {
  const r = rig(t);
  r.deliver({ From: 't*@*', Subject: 'wild', 'Message-ID': '<w1@x.test>' });
  r.notmuch('tag', '+screened', '--', 'id:w1@x.test');
  const res = r.mail('hey', 'feed', 'w1@x.test');
  assert.equal(res.status, 1, res.stdout);
  assert.equal(r.db('thefeed.db'), '');
  assert.ok(r.imbox().includes('b1@x.test'));
  const out = r.mail('hey', 'screen-out', '--sender', '*@shop.test');
  assert.equal(out.status, 1, out.stdout);
  assert.equal(r.db('spam.db'), '');
});

test('mail hey papertrail needs --category and bubble needs --at, with the usage as the hint', (t) => {
  const r = rig(t);
  for (const action of ['papertrail', 'bubble']) {
    const res = r.mail('hey', action, 'b1@x.test');
    assert.equal(res.status, 1, res.stdout);
    assert.match(res.json.error, action === 'papertrail' ? /--category/ : /--at/);
    assert.match(res.json.hint, /^usage: mail/);
  }
});

test('mail hey undo-last with nothing to undo says so, and hints at what it undoes', (t) => {
  const r = rig(t);
  const res = r.mail('hey', 'undo-last');
  assert.equal(res.status, 1);
  assert.equal(res.json.error, 'nothing to undo');
  assert.match(res.json.hint, /last archive or Feed move/);
});

// A sender screened in from The Feed, Paper Trail or screen-out has their mail where a sender screened in from the Screener has it.
test('mail hey screen-in after feed, papertrail or screen-out leaves no archived or class tag on the sender\'s mail', (t) => {
  for (const [first, extra] of [['feed', []], ['papertrail', ['--category', 'receipts']], ['screen-out', []]]) {
    const r = rig(t);
    r.deliver({ From: 'Shop News <news@shop.test>', Subject: 'older', 'Message-ID': '<h2@shop.test>' });
    r.notmuch('tag', '-new', '--', '*');
    const res = first === 'screen-out' ? r.mail('hey', 'screen-out', '--sender', 'news@shop.test') : r.mail('hey', first, 'h1@shop.test', ...extra);
    assert.equal(res.status, 0, `${first}: ${res.stdout}${res.stderr}`);
    assert.ok(r.tags('h1@shop.test').includes('archived'), `${first} archives`);
    const back = r.mail('hey', 'screen-in', 'h1@shop.test');
    assert.equal(back.status, 0, back.stdout + back.stderr);
    for (const id of ['h1@shop.test', 'h2@shop.test']) {
      const tags = r.tags(id);
      assert.ok(tags.includes('inbox') && tags.includes('screened'), `${first}: ${id} ${tags}`);
      for (const gone of ['archived', 'thefeed', 'ledger/receipts', 'spam', 'deleted']) assert.ok(!tags.includes(gone), `${first}: ${id} keeps ${gone}`);
    }
  }
});

// undo-last puts back only a move made in the last 10 minutes; an older one, or one from before moves were timed, is past undoing.
test('mail hey undo-last restores a move made 9 minutes ago, or ahead of a clock set back, and refuses one made 11 minutes ago', (t) => {
  for (const [ago, restores] of [[9 * 60, true], [-5 * 60, true], [11 * 60, false], [null, false]]) {
    const r = rig(t);
    assert.equal(r.mail('hey', 'archive', 'b1@x.test').status, 0);
    const file = join(r.M, 'home/.local/state/hey-mail/undo.json');
    const move = JSON.parse(readFileSync(file, 'utf8'));
    assert.ok(Math.abs(move.at - Date.now() / 1000) < 60, `the move is timed: ${JSON.stringify(move.at)}`);
    if (ago === null) delete move.at;
    else move.at = Date.now() / 1000 - ago;
    writeFileSync(file, JSON.stringify(move));
    const res = r.mail('hey', 'undo-last');
    if (restores) {
      assert.equal(res.status, 0, `${ago}: ${res.stdout}${res.stderr}`);
      assert.ok(r.imbox().includes('b1@x.test'), `${ago}: back in the Imbox`);
      assert.ok(r.tags('b1@x.test').includes('inbox') && !r.tags('b1@x.test').includes('archived'), `${ago}: restored`);
    } else {
      assert.equal(res.status, 1, `${ago}: ${res.stdout}${res.stderr}`);
      assert.equal(res.json.error, 'nothing to undo', `${ago}`);
      assert.match(res.json.hint, /10 minutes/);
      assert.ok(r.tags('b1@x.test').includes('archived') && !r.tags('b1@x.test').includes('inbox'), `${ago}: stays archived`);
    }
  }
});

// A pile takes its thread out of the inbox, and clearing it puts back what the pile took: the Imbox while any of it is unread, Read once it is all read.
test('mail hey replylater and setaside take a thread out of the Imbox and Read, and clear puts it back', (t) => {
  const r = rig(t);
  const box = (name) => r.mail('search', '--box', name).json.data.map((row) => row.id);
  assert.equal(r.mail('hey', 'replylater', 'b1@x.test').status, 0);
  assert.deepEqual(r.imbox(), ['h1@shop.test']);
  assert.deepEqual(box('Reply Later'), ['b1@x.test']);
  r.notmuch('tag', '-unread', '--', 'id:h1@shop.test');
  assert.equal(r.mail('hey', 'setaside', 'h1@shop.test').status, 0);
  assert.deepEqual(box('Read'), []);
  assert.deepEqual(box('Set Aside'), ['h1@shop.test']);
  assert.equal(r.mail('hey', 'clear', 'b1@x.test').status, 0);
  assert.deepEqual(r.imbox(), ['b1@x.test']);
  assert.deepEqual(box('Reply Later'), []);
  assert.equal(r.mail('hey', 'clear', 'h1@shop.test').status, 0);
  assert.deepEqual(box('Read'), ['h1@shop.test']);
  assert.deepEqual(box('Set Aside'), []);
});

test('clear on a thread with read and unread mail and a sent reply puts it in the Imbox alone, and the reply stays out of every box', (t) => {
  const r = rig(t);
  const threads = (name) => r.mail('search', '--box', name).json.data.map((row) => row.thread);
  r.deliver({ From: 'Ann <ann@people.test>', Subject: 'plan', 'Message-ID': '<p1@x.test>' });
  r.notmuch('tag', '+screened', '-unread', '-new', '--', 'id:p1@x.test');
  const c = r.kakMail('compose', 'reply', 'id:p1@x.test');
  assert.equal(c.status, 0, c.stderr);
  assert.equal(r.kakMail('send', c.stdout.trim()).status, 0);
  r.deliver({ From: 'Ann <ann@people.test>', Subject: 'Re: plan', 'Message-ID': '<p2@x.test>', 'In-Reply-To': '<p1@x.test>' });
  r.notmuch('tag', '+screened', '-new', '--', 'id:p2@x.test');
  const tid = r.notmuch('search', '--output=threads', 'id:p1@x.test').trim().replace(/^thread:/, '');
  assert.equal(r.notmuch('count', `thread:${tid}`).trim(), '3');
  assert.equal(r.mail('hey', 'replylater', 'p2@x.test').status, 0);
  for (const name of ['Imbox', 'Read', 'Screener']) assert.ok(!threads(name).includes(tid), `piled, not in ${name}`);
  assert.equal(r.mail('hey', 'clear', 'p2@x.test').status, 0);
  assert.ok(threads('Imbox').includes(tid));
  for (const name of ['Read', 'Screener', 'Reply Later']) assert.ok(!threads(name).includes(tid), `cleared, not in ${name}`);
  assert.equal(r.notmuch('count', `thread:${tid} and tag:sent and tag:inbox`).trim(), '0');
});

test('clear gives inbox back only where a pile took it: never to archived, Feed or unpiled mail', (t) => {
  const r = rig(t);
  assert.equal(r.mail('hey', 'archive', 'b1@x.test').status, 0);
  assert.equal(r.mail('hey', 'clear', 'b1@x.test').status, 0);
  assert.ok(!r.tags('b1@x.test').includes('inbox'), 'an archived thread in no pile stays archived');
  assert.equal(r.mail('hey', 'feed', 'h1@shop.test').status, 0);
  assert.equal(r.mail('hey', 'replylater', 'h1@shop.test').status, 0);
  assert.equal(r.mail('hey', 'clear', 'h1@shop.test').status, 0);
  assert.ok(!r.tags('h1@shop.test').includes('inbox'), 'a Feed thread goes back to The Feed alone');
  assert.ok(r.tags('h1@shop.test').includes('thefeed'));
});

test('a reply sent on a read Reply Later thread puts the thread in Read and out of Reply Later', (t) => {
  const r = rig(t);
  const box = (name) => r.mail('search', '--box', name).json.data.map((row) => row.thread);
  r.notmuch('tag', '-unread', '--', 'id:b1@x.test');
  const tid = r.notmuch('search', '--output=threads', 'id:b1@x.test').trim().replace(/^thread:/, '');
  assert.equal(r.mail('hey', 'replylater', 'b1@x.test').status, 0);
  assert.ok(!box('Read').includes(tid));
  const c = r.kakMail('compose', 'reply', 'id:b1@x.test');
  assert.equal(c.status, 0, c.stderr);
  const s = r.kakMail('send', c.stdout.trim());
  assert.equal(s.status, 0, s.stderr);
  assert.ok(box('Read').includes(tid));
  assert.ok(!box('Reply Later').includes(tid));
  assert.ok(!box('Imbox').includes(tid));
});

// Review m97: the phone moves a thread back to INBOX file by file, and never moves a sent copy out of Sent Messages, so a pile on the sent copy would outlive it.
test('a pile leaves the thread\'s sent copy out, unless the thread holds nothing else', (t) => {
  const r = rig(t);
  const c = r.kakMail('compose', 'reply', 'id:b1@x.test');
  assert.equal(c.status, 0, c.stderr);
  assert.equal(r.kakMail('send', c.stdout.trim()).status, 0);
  const tid = r.notmuch('search', '--output=threads', 'id:b1@x.test').trim();
  assert.equal(r.mail('hey', 'replylater', 'b1@x.test').status, 0);
  assert.equal(r.notmuch('count', `${tid} and tag:sent`).trim(), '1');
  assert.equal(r.notmuch('count', `${tid} and tag:sent and tag:replylater`).trim(), '0');
  assert.ok(r.tags('b1@x.test').includes('replylater'));
});

// Walk finding 73BQY9EY: moving a sender between classes gave inbox back to their piled mail, so it sat in Read and Reply Later at once.
test('moving a sender between classes, or unscreening them, leaves their piled mail out of the inbox', (t) => {
  const r = rig(t);
  const box = (name) => r.mail('search', '--box', name).json.data.map((row) => row.id);
  r.notmuch('tag', '-unread', '--', 'id:h1@shop.test');
  assert.equal(r.mail('hey', 'replylater', 'h1@shop.test').status, 0);
  for (const action of ['feed', 'screen-in']) assert.equal(r.mail('hey', action, 'h1@shop.test').status, 0, action);
  assert.ok(!r.tags('h1@shop.test').includes('inbox'), `${r.tags('h1@shop.test')}`);
  assert.deepEqual(box('Read'), []);
  assert.deepEqual(box('Reply Later'), ['h1@shop.test']);
  assert.equal(r.kakMail('hey', 'unscreen', 'id:h1@shop.test').status, 0);
  assert.ok(!r.tags('h1@shop.test').includes('inbox'), `unscreen: ${r.tags('h1@shop.test')}`);
});

test('a reply that puts unread piled mail back in the Imbox updates the margin\'s count', (t) => {
  const r = rig(t);
  const count = join(r.M, 'home/.local/state/dots/mail-unread');
  r.deliver({ From: 'Bob <bob@people.test>', Subject: 'Re: lunch', 'Message-ID': '<b2@x.test>', 'In-Reply-To': '<b1@x.test>' });
  r.notmuch('tag', '+screened', '-new', '--', 'id:b2@x.test');
  assert.equal(r.mail('hey', 'replylater', 'b1@x.test').status, 0);
  assert.equal(readFileSync(count, 'utf8'), '1\n');
  const c = r.kakMail('compose', 'reply', 'id:b1@x.test');
  assert.equal(c.status, 0, c.stderr);
  assert.equal(r.kakMail('send', c.stdout.trim()).status, 0);
  assert.equal(readFileSync(count, 'utf8'), '3\n');
});

test('an undo file that does not parse is nothing to undo, never a trace', (t) => {
  const r = rig(t);
  assert.equal(r.mail('hey', 'archive', 'b1@x.test').status, 0);
  const file = join(r.M, 'home/.local/state/hey-mail/undo.json');
  for (const text of ['', '{', '[]', JSON.stringify({ at: Date.now() / 1000 })]) {
    writeFileSync(file, text);
    const res = r.mail('hey', 'undo-last');
    assert.equal(res.status, 1, `${text}: ${res.stdout}${res.stderr}`);
    assert.equal(res.json.error, 'nothing to undo', text);
  }
});

const twoSenders = 'From names two senders, ann@first.test and bob@second.test; nothing was decided';

// The engine decided on the From's first address while routing reads its last, so a decision on a From naming two people reported one and filed nothing.
test('mail hey refuses every sender decision on a From naming two senders, and changes nothing', (t) => {
  const r = rig(t);
  r.deliver({ From: 'Ann <ann@first.test>, Bob <bob@second.test>', 'Message-ID': '<two@x.test>' });
  const tags = r.tags('two@x.test');
  for (const args of [['screen-in'], ['feed'], ['papertrail', '--category', 'receipts'], ['screen-in', '--domain'], ['feed', '--domain']]) {
    const res = r.mail('hey', args[0], 'two@x.test', ...args.slice(1));
    assert.equal(res.status, 1, `${args.join(' ')}: ${res.stdout}${res.stderr}`);
    assert.equal(res.json.ok, false);
    assert.equal(res.json.error, twoSenders, args.join(' '));
  }
  for (const db of ['screened.db', 'thefeed.db', 'ledger.db']) assert.equal(r.db(db), '', db);
  assert.equal(existsSync(join(r.env.XDG_STATE_HOME, 'hey-mail/decided')), false, 'a decision was stamped');
  assert.deepEqual(r.tags('two@x.test'), tags);
});

test('mail hey refuses a From naming a sender and one of your own addresses, naming both', (t) => {
  const r = rig(t);
  r.deliver({ From: 'Bob <bob@second.test>, Me <me@x.test>', 'Message-ID': '<two@x.test>' });
  const res = r.mail('hey', 'screen-in', 'two@x.test');
  assert.equal(res.status, 1, res.stdout);
  assert.equal(res.json.error, 'From names two senders, bob@second.test and me@x.test; nothing was decided');
  assert.equal(r.db('screened.db'), '');
});

test('mail hey decides a From naming one address twice as that one sender', (t) => {
  const r = rig(t);
  r.deliver({ From: 'Ann <ann@first.test>, "A" <ANN@first.test>', 'Message-ID': '<one@x.test>' });
  const res = r.mail('hey', 'screen-in', 'one@x.test');
  assert.equal(res.status, 0, res.stdout);
  assert.equal(res.json.data.sender, 'ann@first.test');
  assert.equal(r.db('screened.db'), 'ann@first.test\n');
});

// notmuch's parse drops an address holding a control character, which routing still reads as the From's last address.
test('mail hey refuses a two-sender From whose last address holds a control character', (t) => {
  const r = rig(t);
  for (const [n, c] of [['1', '\x01'], ['2', '\x7f']]) {
    r.deliver({ From: `A <a@x1.test>, B <b${c}ob@second.test>`, 'Message-ID': `<ctl${n}@x.test>` });
    const res = r.mail('hey', 'screen-in', `ctl${n}@x.test`);
    assert.equal(res.status, 1, res.stdout);
    assert.match(res.json.error, /^From names two senders, a@x1\.test and b.ob@second\.test; nothing was decided$/);
  }
  assert.equal(r.db('screened.db'), '');
});

test('mail hey reads one address holding a line separator as one, never as two senders', (t) => {
  const r = rig(t);
  r.deliver({ From: 'Ann <ann\u2028x@first.test>', 'Message-ID': '<sep@x.test>' });
  const res = r.mail('hey', 'screen-in', 'sep@x.test');
  assert.doesNotMatch(res.json.error ?? '', /^From names/);
});

// A control character in a key reaches every machine's db and the status line raw; U+009B is an 8-bit CSI.
test('mail hey decides no address holding a control character, and says so in one plain line', (t) => {
  const r = rig(t);
  for (const [n, c] of [['1', '\u009b'], ['2', '\u0080'], ['3', '\u2028'], ['4', '\u0085']]) {
    r.deliver({ From: `Ann <ann${c}x@first.test>`, 'Message-ID': `<c${n}@x.test>` });
    const res = r.mail('hey', 'screen-in', `c${n}@x.test`);
    assert.equal(res.status, 1, res.stdout);
    assert.doesNotMatch(res.stdout.trimEnd(), /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/, `${n}: ${JSON.stringify(res.stdout)}`);
    assert.match(res.json.error, /is not one plain address/);
    assert.doesNotMatch(res.json.hint, /notmuch failed/);
  }
  assert.equal(r.db('screened.db'), '');
});
