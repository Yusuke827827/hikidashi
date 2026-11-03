// Mindrawer の Web 版を開いて、#add=… で渡す（Web 版がそのまましまう）。開く場所は設定で変えられる。
const DEFAULT_APP = "https://yusuke827827.github.io/hikidashi/";

async function appURL() {
  const { app } = await chrome.storage.sync.get("app");
  return (app || DEFAULT_APP).replace(/#.*$/, "");
}

async function sendToMindrawer(data) {
  const url = (await appURL()) + "#add=" + encodeURIComponent(JSON.stringify(data));
  const base = await appURL();
  // 開いている Mindrawer のタブがあれば、そこで開き直す
  const tabs = await chrome.tabs.query({});
  const open = tabs.find((t) => t.url && t.url.startsWith(base));
  if (open) {
    await chrome.tabs.update(open.id, { url, active: true });
    await chrome.windows.update(open.windowId, { focused: true });
  } else {
    await chrome.tabs.create({ url });
  }
}
