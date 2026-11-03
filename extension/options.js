chrome.storage.sync.get("app").then(({ app }) => { document.getElementById("app").value = app || ""; });
document.getElementById("save").onclick = async () => {
  await chrome.storage.sync.set({ app: document.getElementById("app").value.trim() });
  document.getElementById("ok").textContent = "保存しました";
};
