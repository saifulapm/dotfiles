// bin/mail hey on a scratch store (tests/home/mail-rig.mjs): an agent files mail only in ways that can be undone, on one message it names, and screens out only a sender Saiful names.
import { test } from 'node:test';
import assert from 'node:assert/strict';
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
