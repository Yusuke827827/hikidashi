// 右クリックのメニュー: 選んだ文・このページ・このリンク・この画像の場所を Mindrawer にしまう
importScripts("common.js");

chrome.runtime.onInstalled.addListener(() => {
  const ja = chrome.i18n.getUILanguage().startsWith("ja");
  chrome.contextMenus.create({ id: "selection", title: ja ? "選んだ文を Mindrawer にしまう" : "Save selection to Mindrawer", contexts: ["selection"] });
  chrome.contextMenus.create({ id: "page", title: ja ? "このページを Mindrawer にしまう" : "Save this page to Mindrawer", contexts: ["page"] });
  chrome.contextMenus.create({ id: "link", title: ja ? "このリンクを Mindrawer にしまう" : "Save this link to Mindrawer", contexts: ["link"] });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const page = tab?.url || "", title = tab?.title || "";
  if (info.menuItemId === "selection") sendToMindrawer({ text: info.selectionText || "", url: page });
  if (info.menuItemId === "page") sendToMindrawer({ text: title, url: page });
  if (info.menuItemId === "link") sendToMindrawer({ text: info.selectionText || info.linkUrl, url: info.linkUrl });
});
