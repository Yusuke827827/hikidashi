// docs/privacy-policy.md と docs/support.md を HTML にして src/pages.generated.ts に書き出す。
// App Store に載せるプライバシーポリシーとサポートの URL を、中継サーバーの /privacy と /support で出すため。
//   node scripts/build-pages.mjs          書き出す
//   node scripts/build-pages.mjs --check  最新でなければ失敗する（テスト用）

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const docs = join(here, "..", "..", "docs");
const out = join(here, "..", "src", "pages.generated.ts");

const escape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** 太字と URL だけを扱う */
function inline(s) {
  return escape(s)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/https:\/\/[^\s）)、。]+/g, (u) => `<a href="${u}">${u}</a>`);
}

/** 見出し・箇条書き・段落だけの小さな Markdown の変換 */
export function markdown(md) {
  const html = [];
  let list = false;
  for (const line of md.split("\n")) {
    const t = line.trim();
    if (t.startsWith("- ")) {
      if (!list) { html.push("<ul>"); list = true; }
      html.push(`<li>${inline(t.slice(2))}</li>`);
      continue;
    }
    if (list) { html.push("</ul>"); list = false; }
    if (!t) continue;
    const h = /^(#{1,3}) (.*)$/.exec(t);
    if (h) html.push(`<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`);
    else html.push(`<p>${inline(t)}</p>`);
  }
  if (list) html.push("</ul>");
  return html.join("\n");
}

function page(title, md) {
  return `<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
<style>
:root { color-scheme: light dark; --bg: #f7f2ea; --fg: #2b2622; --muted: #6f6359; --accent: #c4552f; }
@media (prefers-color-scheme: dark) { :root { --bg: #1d1a17; --fg: #ece5dc; --muted: #a89c90; --accent: #e7845f; } }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.75 -apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif; }
main { max-width: 720px; margin: 0 auto; padding: 32px 16px 64px; }
h1 { font-size: 1.6rem; line-height: 1.3; } h2 { margin-top: 2.5rem; font-size: 1.3rem; border-bottom: 1px solid var(--muted); padding-bottom: .3rem; }
h3 { font-size: 1.05rem; margin-top: 1.6rem; } a { color: var(--accent); overflow-wrap: anywhere; } p, li { color: var(--fg); } ul { padding-left: 1.3rem; }
</style>
</head>
<body><main>
${markdown(md)}
</main></body>
</html>
`;
}

export function build() {
  const privacy = page("Mindrawer プライバシーポリシー / Privacy Policy", readFileSync(join(docs, "privacy-policy.md"), "utf8"));
  const support = page("Mindrawer サポート / Support", readFileSync(join(docs, "support.md"), "utf8"));
  return `// scripts/build-pages.mjs が docs/ から作るファイル。手で直さない。\n\nexport const PRIVACY_HTML = ${JSON.stringify(privacy)};\n\nexport const SUPPORT_HTML = ${JSON.stringify(support)};\n`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const text = build();
  if (process.argv.includes("--check")) {
    let current = "";
    try { current = readFileSync(out, "utf8"); } catch {}
    if (current !== text) { console.error("src/pages.generated.ts is out of date. Run: node scripts/build-pages.mjs"); process.exit(1); }
  } else {
    writeFileSync(out, text);
  }
}
