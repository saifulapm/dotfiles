import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dateLines, readQuery, siteRows, digitSite, words } from './newtab.mjs';

// Friday 23 October 2026, in the afternoon.
const FRI = new Date(2026, 9, 23, 14, 32);

test('each voice writes the date as its board does', () => {
  assert.deepEqual(dateLines('caps', FRI), { day: 'FRIDAY', date: '23 October 2026' });
  assert.deepEqual(dateLines('bracket', FRI), { day: 'FRIDAY', date: '2026-10-23' });
  assert.deepEqual(dateLines('plain', FRI), { day: 'Friday', date: '23 October 2026' });
  assert.deepEqual(dateLines('bracket', new Date(2026, 0, 4)), { day: 'SUNDAY', date: '2026-01-04' });
});

test('a typed line opens as an address when it reads as one, else it is a search', () => {
  assert.deepEqual(readQuery('github.com'), { url: 'https://github.com' });
  assert.deepEqual(readQuery('  github.com/saifulapm/dotfiles '), { url: 'https://github.com/saifulapm/dotfiles' });
  assert.deepEqual(readQuery('https://claude.ai/new'), { url: 'https://claude.ai/new' });
  assert.deepEqual(readQuery('http://example.org:8080/x?y=1'), { url: 'http://example.org:8080/x?y=1' });
  assert.deepEqual(readQuery('localhost:5173'), { url: 'http://localhost:5173' });
  assert.deepEqual(readQuery('192.168.0.1/admin'), { url: 'http://192.168.0.1/admin' });
  assert.deepEqual(readQuery('fedora'), { search: 'fedora' });
  assert.deepEqual(readQuery('fedora 44 release'), { search: 'fedora 44 release' });
  assert.deepEqual(readQuery('node.js streams'), { search: 'node.js streams' });
  assert.deepEqual(readQuery('v1.2'), { search: 'v1.2' });
  // Only the web's own schemes open from the page; anything else is searched for, never run.
  assert.deepEqual(readQuery('javascript:alert(1)'), { search: 'javascript:alert(1)' });
  assert.deepEqual(readQuery('file:///etc/passwd'), { search: 'file:///etc/passwd' });
  assert.equal(readQuery('   '), null);
});

test('the six most visited web sites become rows with a number, a letter tile, a title and an address', () => {
  const rows = siteRows(
    [
      { url: 'https://github.com/saifulapm/dotfiles', title: 'dotfiles' },
      { url: 'data:text/html,<b>x</b>', title: 'start' },
      { url: 'https://claude.ai/new', title: 'Claude' },
      { url: 'chrome://settings/', title: 'Settings' },
      { url: 'https://login.tailscale.com/admin', title: 'Tailscale admin' },
      { url: 'https://news.ycombinator.com/', title: 'Hacker News' },
      { url: 'https://www.themoviedb.org/', title: 'The Movie Database' },
      { url: 'https://discussion.fedoraproject.org/', title: 'Fedora Discussion' },
      { url: 'https://example.com/', title: 'Seventh' },
    ],
    'caps',
  );
  assert.deepEqual(rows, [
    { n: '1', url: 'https://github.com/saifulapm/dotfiles', tile: 'd', title: 'dotfiles', address: 'github.com/saifulapm/dotfiles' },
    { n: '2', url: 'https://claude.ai/new', tile: 'C', title: 'Claude', address: 'claude.ai/new' },
    { n: '3', url: 'https://login.tailscale.com/admin', tile: 'T', title: 'Tailscale admin', address: 'login.tailscale.com/admin' },
    { n: '4', url: 'https://news.ycombinator.com/', tile: 'H', title: 'Hacker News', address: 'news.ycombinator.com' },
    { n: '5', url: 'https://www.themoviedb.org/', tile: 'T', title: 'The Movie Database', address: 'themoviedb.org' },
    { n: '6', url: 'https://discussion.fedoraproject.org/', tile: 'F', title: 'Fedora Discussion', address: 'discussion.fedoraproject.org' },
  ]);
  assert.equal(siteRows([{ url: 'https://github.com/', title: 'dotfiles' }], 'bracket')[0].tile, 'D');
  assert.deepEqual(siteRows([], 'plain'), []);
  // Chromium lists its Web Store on a profile with no history, so a fresh profile would never read empty.
  assert.deepEqual(siteRows([{ url: 'https://chrome.google.com/webstore?hl=en', title: 'Web Store' }, { url: 'https://chromewebstore.google.com/', title: 'Chrome Web Store' }], 'plain'), []);
});

// A page's title is whatever its author wrote, so it is one line with no control characters or bidi marks.
test('a forged or missing title still draws one line and a letter tile', () => {
  const forged = 'x\ny\u001bz\u0007q\u0085w‮v‎u' + 'A'.repeat(300);
  const [row] = siteRows([{ url: 'https://evil.example/‮gnp.exe', title: forged }], 'plain');
  assert.equal(row.title, 'x y z q wvu' + 'A'.repeat(300));
  assert.equal(row.tile, 'x');
  assert.equal(row.address, 'evil.example/gnp.exe');
  assert.deepEqual(siteRows([{ url: 'https://www.themoviedb.org/movie', title: '' }], 'plain')[0], {
    n: '1', url: 'https://www.themoviedb.org/movie', tile: 't', title: 'themoviedb.org/movie', address: 'themoviedb.org/movie',
  });
  assert.equal(siteRows([{ url: 'https://8.8.8.8/', title: '‮\u0000 ' }], 'bracket')[0].tile, '8');
  assert.equal(siteRows([{ url: 'https://example.com/', title: '— «»' }], 'plain')[0].tile, 'e');
});

test('1 to 6 open a row only while the field is empty and the row is there', () => {
  assert.equal(digitSite('2', '', 6), 1);
  assert.equal(digitSite('6', '', 6), 5);
  assert.equal(digitSite('2', 'f', 6), -1);
  assert.equal(digitSite('5', '', 4), -1);
  assert.equal(digitSite('7', '', 6), -1);
  assert.equal(digitSite('0', '', 6), -1);
  assert.equal(digitSite('a', '', 6), -1);
});

test('each voice labels the field, the list and the keys as its board does', () => {
  assert.deepEqual(words('caps'), {
    go: '↵ go', head: 'MOST VISITED', empty: 'NOTHING VISITED YET', placeholder: 'Search the web or type a URL',
    keys: [['type', 'search'], ['↓ / tab', 'most visited'], ['1–6', 'open'], ['↵', 'go']],
  });
  assert.deepEqual(words('bracket'), {
    go: '[↵] GO', head: 'MOST VISITED', empty: 'NOTHING VISITED YET', placeholder: 'Search the web or type a URL',
    keys: [['[TYPE]', 'SEARCH'], ['[↓ / TAB]', 'MOST VISITED'], ['[1–6]', 'OPEN'], ['[↵]', 'GO']],
  });
  assert.deepEqual(words('plain'), {
    go: '↵ go', head: 'Most visited', empty: 'Nothing visited yet', placeholder: 'Search the web or type a URL',
    keys: [['type', 'search'], ['↓ / tab', 'most visited'], ['1–6', 'open'], ['↵', 'go']],
  });
});
