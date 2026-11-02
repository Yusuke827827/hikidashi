// 公開リンクと受け取り箱（メール・LINE）を確かめる。
import { describe, expect, it } from "vitest";
import { handle, type Env } from "../src/index";
import { emailText, handleEmail, publicPage } from "../src/extras";

function memKV() {
  const m = new Map<string, string>();
  return { get: async (k: string) => m.get(k) ?? null, put: async (k: string, v: string) => void m.set(k, v), delete: async (k: string) => void m.delete(k) } as unknown as KVNamespace;
}
const env = (kv: KVNamespace, extra: Partial<Env> = {}) => ({ USAGE: kv, ANTHROPIC_API_KEY: "x", BUNDLE_ID: "b", PRODUCT_IDS: "p", ...extra }) as Env;
const sent: unknown[] = [];
const deps = { fetch: (async (_u: string, init: RequestInit) => { sent.push(JSON.parse(String(init.body))); return new Response("{}"); }) as unknown as typeof fetch, now: () => new Date(1_800_000_000_000) };
const req = (method: string, path: string, body?: unknown, headers: Record<string, string> = {}) =>
  new Request("https://s.example" + path, { method, body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body), headers });

async function sign(secret: string, body: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)))));
}

describe("公開リンク", () => {
  it("作って見られ、鍵で消せる。中身はエスケープする", async () => {
    const kv = memKV();
    const r = await handle(req("POST", "/p", { title: "<b>シミ</b>", text: "叩く https://e.com/a" }), env(kv), deps);
    const { id, key, url } = await r.json() as { id: string; key: string; url: string };
    expect(url).toBe(`https://s.example/p/${id}`);
    const page = await (await handle(req("GET", `/p/${id}`), env(kv), deps)).text();
    expect(page).toContain("&lt;b&gt;シミ&lt;/b&gt;");
    expect(page).toContain('<a href="https://e.com/a"');
    expect((await handle(req("DELETE", `/p/${id}`, undefined, { "x-delete-key": "bad" }), env(kv), deps)).status).toBe(403);
    expect((await handle(req("DELETE", `/p/${id}`, undefined, { "x-delete-key": key }), env(kv), deps)).status).toBe(200);
    expect((await handle(req("GET", `/p/${id}`), env(kv), deps)).status).toBe(404);
  });
  it("javascript: の出典はリンクにしない", () => {
    expect(publicPage({ title: "t", text: "x", url: "javascript:alert(1)" })).not.toContain("javascript:");
  });
});

describe("受け取り箱", () => {
  it("メールと LINE から入り、取りに来たら空になる", async () => {
    const kv = memKV();
    const e = env(kv, { LINE_CHANNEL_SECRET: "sec", LINE_CHANNEL_TOKEN: "tok", INBOX_EMAIL_DOMAIN: "in.example" });
    const box = await (await handle(req("POST", "/inbox"), e, deps)).json() as { id: string; key: string; email: string; line: boolean };
    expect(box.email).toBe(`${box.id}@in.example`);
    expect(box.line).toBe(true);

    const raw = "Subject: x\r\nContent-Type: text/plain\r\n\r\n洗剤は詰め替えが安い\r\n-- \r\n署名";
    await handleEmail({ to: `${box.id}@in.example`, headers: new Headers({ subject: "=?UTF-8?B?" + Buffer.from("洗剤メモ").toString("base64") + "?=" }), raw: new Response(raw).body!, rawSize: raw.length }, e, 1);

    const link = JSON.stringify({ events: [{ type: "message", replyToken: "r", source: { userId: "U1" }, message: { type: "text", text: `連携 ${box.id}` } }] });
    expect((await handle(req("POST", "/line", link, { "x-line-signature": "bad" }), e, deps)).status).toBe(403);
    await handle(req("POST", "/line", link, { "x-line-signature": await sign("sec", link) }), e, deps);
    const msg = JSON.stringify({ events: [{ type: "message", replyToken: "r", source: { userId: "U1" }, message: { type: "text", text: "このお店よかった https://shop.example" } }] });
    await handle(req("POST", "/line", msg, { "x-line-signature": await sign("sec", msg) }), e, deps);
    expect(JSON.stringify(sent)).toContain("つながりました");

    expect((await handle(req("GET", `/inbox/${box.id}`), e, deps)).status).toBe(403);
    const got = await (await handle(req("GET", `/inbox/${box.id}`, undefined, { "x-inbox-key": box.key }), e, deps)).json() as { items: { text: string; from: string; url?: string }[] };
    expect(got.items.map((i) => i.from)).toEqual(["email", "line"]);
    expect(got.items[0].text).toBe("洗剤メモ\n\n洗剤は詰め替えが安い");
    expect(got.items[1].url).toBe("https://shop.example");
    const again = await (await handle(req("GET", `/inbox/${box.id}`, undefined, { "x-inbox-key": box.key }), e, deps)).json() as { items: unknown[] };
    expect(again.items).toHaveLength(0);
  });
  it("マルチパートのメールは text/plain を読む", () => {
    const raw = 'Content-Type: multipart/alternative; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n' + Buffer.from("本文です").toString("base64") + "\r\n--b1\r\nContent-Type: text/html\r\n\r\n<p>x</p>\r\n--b1--";
    expect(emailText("件名", raw)).toBe("件名\n\n本文です");
  });
});
