// Chromium's new-tab page: the date, a search field with focus, and the six most visited sites.
import { dateLines, readQuery, siteRows, digitSite, words } from './words.mjs';

// Chromium hands an overridden new tab's keys to its address bar; a tab the page opens itself takes them, so the first load only swaps itself for one.
if (!location.search) {
  chrome.tabs.getCurrent((tab) => {
    chrome.tabs.create({ url: chrome.runtime.getURL('newtab.html?f'), index: tab.index + 1, windowId: tab.windowId }, () => chrome.tabs.remove(tab.id));
  });
} else {
  draw();
}

function draw() {
  const voice = document.documentElement.dataset.voice;
  const w = words(voice);
  const q = document.getElementById('q');
  const sites = document.getElementById('sites');
  const { day, date } = dateLines(voice, new Date());
  document.getElementById('day').textContent = day;
  document.getElementById('date').textContent = date;
  q.placeholder = w.placeholder;
  document.querySelector('.go').textContent = w.go;
  document.querySelector('.head').textContent = w.head;
  for (const [key, word] of w.keys) {
    const span = document.createElement('span');
    const b = document.createElement('b');
    b.textContent = key;
    span.append(b, ` ${word}`);
    document.querySelector('.keys').append(span);
  }
  document.querySelector('main').hidden = false;
  q.focus();

  let rows = [];
  const rowEls = () => [...sites.querySelectorAll('.row')];
  const open = (url) => location.assign(url);

  chrome.topSites.get((top) => {
    rows = siteRows(top, voice);
    for (const r of rows) {
      const a = document.createElement('a');
      a.className = 'row';
      a.href = r.url;
      for (const [cls, text] of [['n', r.n], ['tile', r.tile], ['title', r.title], ['address', r.address]]) {
        const span = document.createElement('span');
        span.className = cls;
        span.textContent = text;
        a.append(span);
      }
      sites.append(a);
    }
    if (!rows.length) {
      const empty = document.createElement('div');
      empty.className = 'empty';
      empty.textContent = w.empty;
      sites.append(empty);
    }
  });

  q.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      const r = readQuery(q.value);
      if (!r) return;
      e.preventDefault();
      if (r.url) open(r.url);
      else chrome.search.query({ text: r.search, disposition: 'CURRENT_TAB' });
    } else if ((e.key === 'ArrowDown' || (e.key === 'Tab' && !e.shiftKey)) && rows.length) {
      e.preventDefault();
      rowEls()[0].focus();
    }
  });

  sites.addEventListener('keydown', (e) => {
    const els = rowEls();
    const i = els.indexOf(document.activeElement);
    if (e.key === 'ArrowDown' && i < els.length - 1) {
      e.preventDefault();
      els[i + 1].focus();
    } else if (e.key === 'ArrowUp' || e.key === 'Escape') {
      e.preventDefault();
      (i > 0 && e.key === 'ArrowUp' ? els[i - 1] : q).focus();
    } else if (e.key.length === 1 && !/[1-6]/.test(e.key) && !e.ctrlKey && !e.altKey && !e.metaKey) {
      // A letter typed on the list starts a search, so focus goes back to the field before the key lands.
      q.focus();
    }
  });

  // The digits open a site only while the field is empty; typed into a query they are part of it.
  document.addEventListener('keydown', (e) => {
    if (e.ctrlKey || e.altKey || e.metaKey) return;
    const i = digitSite(e.key, q.value, rows.length);
    if (i < 0) return;
    e.preventDefault();
    open(rows[i].url);
  });
}
