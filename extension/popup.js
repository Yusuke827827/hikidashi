// 押したときの小さな画面: 選んでいた文（あれば）とページの URL を入れて、しまう
(async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  document.getElementById("url").textContent = tab?.url || "";
  try {
    const [r] = await chrome.scripting?.executeScript?.({ target: { tabId: tab.id }, func: () => String(getSelection()) }) || [];
    if (r?.result) document.getElementById("text").value = r.result;
  } catch {}
  document.getElementById("save").onclick = async () => {
    const text = document.getElementById("text").value.trim() || tab?.title || "";
    await sendToMindrawer({ text, url: tab?.url || "" });
    window.close();
  };
})();
