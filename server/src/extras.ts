// 公開リンクと受け取り箱。
//   公開リンク（/p）: メモ 1 枚を、アプリを持っていない人もブラウザで見られるページにする。消すための鍵はハッシュで保存
//   受け取り箱（/inbox）: メール・LINE から送ったメモをためておき、アプリが取りに来たら渡して消す。
//     メール: Cloudflare の Email Routing で <受け取り箱の id>@自分のドメイン をこの Worker に回す（email()）
//     LINE: LINE の公式アカウント（Messaging API）の Webhook を /line に向ける。「連携 <id>」と送るとつながる
// 保存先は利用回数と同じ KV（pub: / inbox: / line: で始まる鍵）。

import { randomToken, sha256 } from "./share";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
  "access-control-allow-headers": "content-type, x-delete-key, x-inbox-key",
  "access-control-max-age": "86400",
};
const MAX_BODY = 256 * 1024;
const INBOX_LIMIT = 200;
const INBOX_TTL = 60 * 60 * 24 * 60; // 60 日

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...CORS } });
}

async function readJSON(request: Request): Promise<Record<string, unknown> | null> {
  const t = await request.text();
  if (t.length > MAX_BODY) return null;
  try {
    const j = JSON.parse(t || "{}");
    return j && typeof j === "object" ? j : null;
  } catch {
    return null;
  }
}

export const escapeHTML = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

/** 公開ページの HTML。本文の URL はリンクにする（中身はすべてエスケープしてから） */
export function publicPage(n: { title: string; text: string; url?: string; category?: string; createdAt?: number }): string {
  const linkify = (s: string) => escapeHTML(s).replace(/https?:\/\/[^\s<&]+/g, (u) => `<a href="${u}" rel="noopener nofollow">${u}</a>`);
  const src = n.url && /^https?:\/\//.test(n.url) ? `<p class="src">出典: <a href="${escapeHTML(n.url)}" rel="noopener nofollow">${escapeHTML(n.url)}</a></p>` : "";
  return `<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${escapeHTML(n.title)} · Mindrawer</title>
<style>:root{--bg:#f6f5f2;--ink:#1c1c1e;--muted:#6b6a66;--accent:#c8553d;--card:#fff}
@media (prefers-color-scheme:dark){:root{--bg:#17181b;--ink:#ecebe7;--muted:#9b9a95;--accent:#e0745a;--card:#212226}}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.7 -apple-system,"Hiragino Sans","Noto Sans JP",sans-serif;padding:24px 16px}
main{max-width:640px;margin:0 auto;background:var(--card);border-radius:16px;padding:22px 22px 18px;box-shadow:0 1px 2px rgba(0,0,0,.06),0 4px 16px rgba(0,0,0,.05)}
small{color:var(--accent);font-weight:700}h1{font-size:22px;margin:4px 0 12px}p{white-space:pre-wrap;margin:0 0 12px;overflow-wrap:anywhere}
a{color:var(--accent)}.src{font-size:13px;color:var(--muted)}footer{max-width:640px;margin:14px auto 0;font-size:12.5px;color:var(--muted);text-align:center}</style></head>
<body><main><small>${escapeHTML(n.category || "")}</small><h1>${escapeHTML(n.title)}</h1><p>${linkify(n.text)}</p>${src}</main>
<footer>Mindrawer でしまったメモ</footer></body></html>`;
}

export interface InboxItem {
  text: string;
  url?: string;
  from: "email" | "line" | "web";
  at: number;
}

async function pushInbox(kv: KVNamespace, id: string, item: InboxItem): Promise<void> {
  const raw = await kv.get("inbox:" + id);
  if (!raw) return;
  const box = JSON.parse(raw) as { keyHash: string; items: InboxItem[] };
  box.items = [...box.items, item].slice(-INBOX_LIMIT);
  await kv.put("inbox:" + id, JSON.stringify(box), { expirationTtl: INBOX_TTL });
}

/** メールの本文から、メモにする文を取り出す（引用や署名の区切りから後ろは捨てる） */
export function emailText(subject: string, raw: string): string {
  const sep = raw.search(/\r?\n\r?\n/);
  let body = sep >= 0 ? raw.slice(sep).trim() : raw;
  const boundary = raw.match(/boundary="?([^";\r\n]+)"?/i)?.[1];
  const head = sep >= 0 ? raw.slice(0, sep) : "";
  if (!boundary && /content-transfer-encoding:\s*base64/i.test(head)) {
    try { body = new TextDecoder().decode(Uint8Array.from(atob(body.replace(/\s+/g, "")), (c) => c.charCodeAt(0))); } catch {}
  } else if (!boundary && /content-transfer-encoding:\s*quoted-printable/i.test(head)) {
    body = decodeQP(body);
  }
  if (boundary) {
    const parts = body.split("--" + boundary);
    const plain = parts.find((p) => /content-type:\s*text\/plain/i.test(p));
    if (plain) {
      const i = plain.search(/\r?\n\r?\n/);
      body = i >= 0 ? plain.slice(i).trim() : plain;
      if (/content-transfer-encoding:\s*base64/i.test(plain)) {
        try { body = new TextDecoder().decode(Uint8Array.from(atob(body.replace(/\s+/g, "")), (c) => c.charCodeAt(0))); } catch {}
      } else if (/content-transfer-encoding:\s*quoted-printable/i.test(plain)) {
        body = decodeQP(body);
      }
    }
  }
  body = body.split(/\r?\n(?:-- ?\r?\n|>.*\n|On .+ wrote:|.*\d{4}\/\d{1,2}\/\d{1,2}.*:$)/)[0].trim();
  return [subject.trim(), body].filter(Boolean).join("\n\n").slice(0, 20_000);
}

/** 件名の =?UTF-8?B?…?= / =?UTF-8?Q?…?= を読む */
export function decodeMimeWords(s: string): string {
  return s.replace(/=\?([^?]+)\?([BbQq])\?([^?]*)\?=/g, (_m, charset: string, enc: string, data: string) => {
    try {
      const bytes = enc.toUpperCase() === "B"
        ? Uint8Array.from(atob(data), (c) => c.charCodeAt(0))
        : new TextEncoder().encode(decodeQP(data.replace(/_/g, " ")));
      return new TextDecoder(charset.toLowerCase() === "iso-2022-jp" ? "iso-2022-jp" : charset).decode(bytes);
    } catch {
      return data;
    }
  }).replace(/\?=\s+=\?/g, "");
}

function decodeQP(s: string): string {
  const bytes: number[] = [];
  const t = s.replace(/=\r?\n/g, "");
  for (let i = 0; i < t.length; i++) {
    if (t[i] === "=" && /^[0-9A-F]{2}$/i.test(t.slice(i + 1, i + 3))) { bytes.push(parseInt(t.slice(i + 1, i + 3), 16)); i += 2; }
    else bytes.push(...new TextEncoder().encode(t[i]));
  }
  return new TextDecoder().decode(new Uint8Array(bytes));
}

/** LINE の署名を確かめる */
async function lineSignatureOK(secret: string, body: string, sig: string | null): Promise<boolean> {
  if (!secret || !sig) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
  return btoa(String.fromCharCode(...mac)) === sig;
}

async function lineReply(token: string | undefined, replyToken: string, text: string, fetcher: typeof fetch) {
  if (!token || !replyToken) return;
  await fetcher("https://api.line.me/v2/bot/message/reply", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: "Bearer " + token },
    body: JSON.stringify({ replyToken, messages: [{ type: "text", text }] }),
  }).catch(() => {});
}

export interface ExtrasEnv {
  USAGE: KVNamespace;
  LINE_CHANNEL_SECRET?: string;
  LINE_CHANNEL_TOKEN?: string;
  /** メールで送る宛先のドメイン（Email Routing を設定したもの）。空ならメールの宛先は出さない */
  INBOX_EMAIL_DOMAIN?: string;
}

export async function handleExtras(request: Request, env: ExtrasEnv, now: number, fetcher: typeof fetch): Promise<Response | null> {
  const url = new URL(request.url);
  const p = url.pathname;
  if (!/^\/(p|inbox|line)(\/|$)/.test(p)) return null;
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  const kv = env.USAGE;

  // ---- 公開リンク ----
  if (p === "/p" && request.method === "POST") {
    const b = await readJSON(request);
    const text = typeof b?.text === "string" ? b.text.slice(0, 20_000) : "";
    if (!b || !text.trim()) return reply(400, { error: "bad_request" });
    const id = randomToken(10), key = randomToken(24);
    const note = {
      title: String(b.title || text.split("\n")[0]).slice(0, 120), text,
      url: typeof b.url === "string" ? b.url.slice(0, 500) : undefined,
      category: typeof b.category === "string" ? b.category.slice(0, 40) : undefined, createdAt: now,
    };
    await kv.put("pub:" + id, JSON.stringify({ note, keyHash: await sha256(key) }));
    return reply(200, { id, key, url: `${url.origin}/p/${id}` });
  }
  const pm = p.match(/^\/p\/([A-Za-z0-9]{6,40})$/);
  if (pm) {
    const raw = await kv.get("pub:" + pm[1]);
    if (request.method === "GET") {
      if (!raw) return new Response("見つかりませんでした（公開をやめたのかもしれません）。", { status: 404, headers: { "content-type": "text/plain; charset=utf-8" } });
      return new Response(publicPage(JSON.parse(raw).note), { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=60", "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'" } });
    }
    if (request.method === "DELETE") {
      if (!raw) return reply(200, { ok: true });
      const ok = (await sha256(request.headers.get("x-delete-key") || "")) === JSON.parse(raw).keyHash;
      if (!ok) return reply(403, { error: "forbidden" });
      await kv.delete("pub:" + pm[1]);
      return reply(200, { ok: true });
    }
  }

  // ---- 受け取り箱 ----
  if (p === "/inbox" && request.method === "POST") {
    const id = randomToken(10).toLowerCase(), key = randomToken(24);
    await kv.put("inbox:" + id, JSON.stringify({ keyHash: await sha256(key), items: [] }), { expirationTtl: INBOX_TTL });
    return reply(200, { id, key, email: env.INBOX_EMAIL_DOMAIN ? `${id}@${env.INBOX_EMAIL_DOMAIN}` : null, line: !!env.LINE_CHANNEL_SECRET });
  }
  const im = p.match(/^\/inbox\/([a-z0-9]{6,40})$/);
  if (im) {
    const raw = await kv.get("inbox:" + im[1]);
    if (!raw) return reply(404, { error: "not_found" });
    const box = JSON.parse(raw) as { keyHash: string; items: InboxItem[] };
    if ((await sha256(request.headers.get("x-inbox-key") || "")) !== box.keyHash) return reply(403, { error: "forbidden" });
    // 取りに来たら渡して空にする
    if (request.method === "GET" || request.method === "POST") {
      await kv.put("inbox:" + im[1], JSON.stringify({ ...box, items: [] }), { expirationTtl: INBOX_TTL });
      return reply(200, { items: box.items });
    }
    if (request.method === "DELETE") { await kv.delete("inbox:" + im[1]); return reply(200, { ok: true }); }
  }

  // ---- LINE ----
  if (p === "/line" && request.method === "POST") {
    const body = await request.text();
    if (!(await lineSignatureOK(env.LINE_CHANNEL_SECRET || "", body, request.headers.get("x-line-signature")))) return reply(403, { error: "forbidden" });
    const events = (JSON.parse(body || "{}").events || []) as { type: string; replyToken?: string; source?: { userId?: string }; message?: { type: string; text?: string } }[];
    for (const e of events) {
      const uid = e.source?.userId;
      if (e.type !== "message" || e.message?.type !== "text" || !uid) continue;
      const text = (e.message.text || "").trim();
      const link = text.match(/^(?:連携|link)\s+([a-z0-9]{6,40})$/i);
      if (link) {
        const ok = !!(await kv.get("inbox:" + link[1].toLowerCase()));
        if (ok) await kv.put("line:" + uid, link[1].toLowerCase());
        await lineReply(env.LINE_CHANNEL_TOKEN, e.replyToken || "", ok ? "Mindrawer とつながりました。送ったメッセージがメモになります。" : "受け取り箱が見つかりませんでした。アプリの設定でもう一度コードを確かめてください。", fetcher);
        continue;
      }
      const box = await kv.get("line:" + uid);
      if (!box) {
        await lineReply(env.LINE_CHANNEL_TOKEN, e.replyToken || "", "まだ Mindrawer とつながっていません。アプリの設定「メール・LINE で送る」に出る「連携 …」をそのまま送ってください。", fetcher);
        continue;
      }
      const u = text.match(/https?:\/\/\S+/)?.[0];
      await pushInbox(kv, box, { text: text.slice(0, 20_000), url: u, from: "line", at: now });
      await lineReply(env.LINE_CHANNEL_TOKEN, e.replyToken || "", "しまいました ✓", fetcher);
    }
    return reply(200, { ok: true });
  }
  return reply(404, { error: "not_found" });
}

/** Email Routing から届いたメール（宛先の @ の前が受け取り箱の id） */
export async function handleEmail(message: { to: string; headers: Headers; raw: ReadableStream; rawSize: number }, env: ExtrasEnv, now: number): Promise<void> {
  const id = message.to.split("@")[0].toLowerCase().replace(/\+.*$/, "");
  if (!/^[a-z0-9]{6,40}$/.test(id) || message.rawSize > 2_000_000) return;
  const raw = await new Response(message.raw).text();
  const subject = decodeMimeWords(message.headers.get("subject") || "");
  const text = emailText(subject, raw);
  if (!text.trim()) return;
  await pushInbox(env.USAGE, id, { text, url: text.match(/https?:\/\/\S+/)?.[0], from: "email", at: now });
}
