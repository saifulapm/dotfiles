// Chromium starts on its own new-tab page even with this extension installed; only later tabs take the override. So at each start the worker sends any tab still on that page to this one.
async function themeStartTab() {
  for (const t of await chrome.tabs.query({})) {
    if (/^chrome:\/\/(newtab|new-tab-page)\//.test(t.pendingUrl || t.url || '')) chrome.tabs.update(t.id, { url: chrome.runtime.getURL('newtab.html') });
  }
}
// --load-extension installs the extension afresh at each start, so onInstalled fires every time and onStartup never does.
chrome.runtime.onInstalled.addListener(themeStartTab);
