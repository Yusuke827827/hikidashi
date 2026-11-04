// 見ているページの題名・URL と、選んでいる文を読み、「しまう」でアプリに渡す
(async () => {
  const $ = (id) => document.getElementById(id);
  let tab = null;
  try { [tab] = await browser.tabs.query({ active: true, currentWindow: true }); } catch {}
  $("src").textContent = tab ? `${tab.title || ""}\n${tab.url || ""}` : "";
  try {
    const [r] = await browser.scripting.executeScript({ target: { tabId: tab.id }, func: () => String(getSelection() || "").trim() });
    if (r && r.result) $("text").value = r.result;
  } catch {}
  $("save").onclick = async () => {
    $("save").disabled = true;
    const res = await browser.runtime.sendMessage({ type: "save", text: $("text").value.trim(), url: tab?.url || "", title: tab?.title || "" }).catch(() => null);
    if (res && res.ok) {
      $("msg").textContent = "しまいました。次に Mindrawer を開くと整理されます。";
      setTimeout(() => window.close(), 1400);
    } else {
      $("msg").textContent = "しまえませんでした。Mindrawer のアプリを一度開いてから、もう一度試してください。";
      $("save").disabled = false;
    }
  };
})();
