// node cdp.mjs <port> urls | open <url> | eval <url-part> <js> | shot <url-part> <png> | fonts <url-part> <selector> | visit <url>: reads and drives a Chromium started with --remote-debugging-port.
const [port, cmd, ...args] = process.argv.slice(2);
const base = `http://127.0.0.1:${port}`;
const pages = async () => (await (await fetch(`${base}/json/list`)).json()).filter((t) => t.type === 'page');

// One DevTools session on a page: send(method, params) resolves with the call's result.
async function session(target) {
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok, fail) => {
    ws.onopen = ok;
    ws.onerror = fail;
  });
  let id = 0;
  const waiting = new Map();
  ws.addEventListener('message', (m) => {
    const msg = JSON.parse(m.data);
    if (waiting.has(msg.id)) waiting.get(msg.id)(msg);
  });
  const send = (method, params = {}) => new Promise((ok) => {
    waiting.set(++id, ok);
    ws.send(JSON.stringify({ id, method, params }));
  });
  return { send, close: () => ws.close() };
}

if (cmd === 'urls') {
  for (const t of await pages()) console.log(t.url);
} else if (cmd === 'open') {
  if (!(await fetch(`${base}/json/new?${args[0]}`, { method: 'PUT' })).ok) process.exit(1);
} else if (cmd === 'eval') {
  const target = (await pages()).find((t) => t.url.includes(args[0]));
  if (!target) process.exit(1);
  const s = await session(target);
  const r = await s.send('Runtime.evaluate', { expression: args[1], returnByValue: true, awaitPromise: true });
  s.close();
  if (r.result?.exceptionDetails || !r.result) process.exit(1);
  console.log(JSON.stringify(r.result.result.value));
} else if (cmd === 'shot') {
  const target = (await pages()).find((t) => t.url.includes(args[0]));
  if (!target) process.exit(1);
  const s = await session(target);
  const r = await s.send('Page.captureScreenshot', { format: 'png' });
  s.close();
  if (!r.result) process.exit(1);
  (await import('node:fs')).writeFileSync(args[1], Buffer.from(r.result.data, 'base64'));
} else if (cmd === 'fonts') {
  // The fonts Chromium drew the element's text in, which a missing font cannot fake the way a computed font-family can.
  const target = (await pages()).find((t) => t.url.includes(args[0]));
  if (!target) process.exit(1);
  const s = await session(target);
  await s.send('DOM.enable');
  await s.send('CSS.enable');
  const doc = await s.send('DOM.getDocument', { depth: 0 });
  const node = await s.send('DOM.querySelector', { nodeId: doc.result.root.nodeId, selector: args[1] });
  const fonts = await s.send('CSS.getPlatformFontsForNode', { nodeId: node.result.nodeId });
  s.close();
  if (!fonts.result) process.exit(1);
  console.log(fonts.result.fonts.map((f) => f.familyName).join(','));
} else if (cmd === 'visit') {
  // A typed visit, as from the address bar, which Chromium counts toward its most visited sites.
  const s = await session((await pages())[0]);
  await s.send('Page.enable');
  await s.send('Page.navigate', { url: args[0], transitionType: 'typed' });
  await new Promise((ok) => setTimeout(ok, 300));
  s.close();
} else {
  process.exit(2);
}
