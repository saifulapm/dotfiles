chrome.commands.onCommand.addListener((command) => {
  if (command === 'copy-url') {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const currentTab = tabs[0];
      chrome.scripting.executeScript({
        target: { tabId: currentTab.id },
        func: () => {
          navigator.clipboard.writeText(window.location.href);
        }
      }).then(() => {
        chrome.notifications.create({
          type: 'basic',
          iconUrl: 'icon.png',
          title: 'URL copied to clipboard',
          message: ''
        });
      });
    });
  }
});
