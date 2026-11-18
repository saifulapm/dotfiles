import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { blocks, sse } from './chat.mjs';

const bin = new URL('../../bin/dev-fake-pxy', import.meta.url).pathname;

async function withFake(fn) {
  const dir = mkdtempSync(join(tmpdir(), 'pxy-'));
  const child = spawn(bin, [dir], { stdio: 'ignore' });
  try {
    for (let i = 0; i < 100 && !existsSync(join(dir, 'port')); i++) await new Promise((r) => setTimeout(r, 20));
    const url = `http://127.0.0.1:${readFileSync(join(dir, 'port'), 'utf8')}/v1/chat/completions`;
    await fn(url, dir);
  } finally {
    child.kill('SIGTERM');
    rmSync(dir, { recursive: true, force: true });
  }
}

const ask = (url, body, key = 'pxy-local') =>
  fetch(url, { method: 'POST', headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' }, body: JSON.stringify(body) });

test('the fake pxy streams the fish loop on the chat alias, names its model, and logs the request', async () => {
  await withFake(async (url, dir) => {
    const res = await ask(url, { model: 'chat', stream: true, messages: [{ role: 'user', content: 'write a fish loop' }] });
    const reader = sse();
    const { events, done } = reader.feed(await res.text());
    assert.equal(done, true);
    assert.equal(events[0].model, 'fake/chat-model');
    const text = events.map((e) => e.choices[0].delta.content ?? '').join('');
    assert.deepEqual(blocks().end(text).closed.map((b) => b.kind), ['p', 'code', 'p']);
    assert.equal(JSON.parse(readFileSync(join(dir, 'requests.jsonl'), 'utf8')).model, 'chat');
  });
});

test('the fake pxy asks for a tool first, and answers once the tool result comes back', async () => {
  await withFake(async (url) => {
    const user = { role: 'user', content: "what did we decide about the island's shape?" };
    const first = sse().feed(await (await ask(url, { model: 'chat', messages: [user] })).text()).events;
    assert.deepEqual(first[0].choices[0].delta.tool_calls[0].function, { name: 'mem_search', arguments: '{"query":"island shape"}' });
    assert.equal(first.at(-1).choices[0].finish_reason, 'tool_calls');
    const call = first[0].choices[0].delta.tool_calls[0];
    const second = sse().feed(
      await (
        await ask(url, {
          model: 'chat',
          messages: [user, { role: 'assistant', content: null, tool_calls: [call] }, { role: 'tool', tool_call_id: call.id, content: 'SHAPE-1' }],
        })
      ).text(),
    ).events;
    assert.match(second.map((e) => e.choices[0].delta.content ?? '').join(''), /SHAPE-1/);
  });
});

test('the fake pxy refuses a wrong key and the 401 word with an error body', async () => {
  await withFake(async (url) => {
    const wrong = await ask(url, { model: 'chat', messages: [{ role: 'user', content: 'hi' }] }, 'nope');
    assert.equal(wrong.status, 401);
    const asked = await ask(url, { model: 'chat', messages: [{ role: 'user', content: 'send 401' }] });
    assert.equal(asked.status, 401);
    assert.equal((await asked.json()).error.message, 'fake pxy: invalid API key');
  });
});
