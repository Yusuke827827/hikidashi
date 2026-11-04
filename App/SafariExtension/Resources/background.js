// ポップアップから届いた内容を、アプリ（SafariWebExtensionHandler）に渡す
browser.runtime.onMessage.addListener((msg) => {
  if (!msg || msg.type !== "save") return;
  return browser.runtime.sendNativeMessage("app.mindrawer", { text: msg.text || "", url: msg.url || "", title: msg.title || "" })
    .catch(() => ({ ok: false }));
});
