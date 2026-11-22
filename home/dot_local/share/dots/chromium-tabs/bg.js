// The Playwright Extension keeps a session's tabs in a group named "Playwright · <client>" and turns the group grey once the session ends; the CLI cannot close them itself, since it reopens a blank tab whenever it has none, so the tabs of a grey group close here.
const ended = (group) => group.color === 'grey' && (group.title ?? '').startsWith('Playwright');

async function closeTabs(group) {
  if (!ended(group)) return;
  const tabs = await chrome.tabs.query({ groupId: group.id });
  await chrome.tabs.remove(tabs.map((tab) => tab.id)).catch(() => {});
}

chrome.tabGroups.onUpdated.addListener(closeTabs);
// Groups a crashed or restarted browser left grey.
const sweep = async () => (await chrome.tabGroups.query({ color: 'grey' })).forEach(closeTabs);
chrome.runtime.onStartup.addListener(sweep);
chrome.runtime.onInstalled.addListener(sweep);
