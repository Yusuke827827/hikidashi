// 同期（暗号文の置き場所）と、Web 版のためのページ・動画の読み取りを確かめる。
import { describe, expect, it } from "vitest";
import { handle, type Env } from "../src/index";
import { htmlToText, youtubeId } from "../src/tools";

function memKV() {
  const m = new Map<string, string>();
  return { get: async (k: string) => m.get(k) ?? null, put: async (k: string, v: string) => void m.set(k, v), delete: async (k: string) => void m.delete(k) } as unknown as KVNamespace;
}
const env = (kv: KVNamespace) => ({ USAGE: kv, ANTHROPIC_API_KEY: "x", BUNDLE_ID: "b", PRODUCT_IDS: "p" }) as Env;
const req = (method: string, path: string, body?: unknown) =>
  new Request("https://s.example" + path, { method, body: body === undefined ? undefined : JSON.stringify(body) });
const id = "a".repeat(64);

describe("同期", () => {
  it("版がそろっているときだけ置き換え、違えば 409 で今の内容を返す", async () => {
    const kv = memKV(), d = { fetch, now: () => new Date(1_800_000_000_000) };
    const g0 = await (await handle(req("GET", `/sync/${id}`), env(kv), d)).json() as { ver: number; data: string | null };
    expect(g0).toMatchObject({ ver: 0, data: null });
    expect((await handle(req("PUT", `/sync/${id}`, { ver: 0, data: "AAA" }), env(kv), d)).status).toBe(200);
    const stale = await handle(req("PUT", `/sync/${id}`, { ver: 0, data: "BBB" }), env(kv), d);
    expect(stale.status).toBe(409);
    expect(await stale.json()).toMatchObject({ ver: 1, data: "AAA" });
    expect((await handle(req("PUT", `/sync/${id}`, { ver: 1, data: "CCC" }), env(kv), d)).status).toBe(200);
    expect(await (await handle(req("GET", `/sync/${id}`), env(kv), d)).json()).toMatchObject({ ver: 2, data: "CCC" });
    expect((await handle(req("GET", `/sync/short`), env(kv), d)).status).toBe(404);
  });
});

describe("ページの読み取り", () => {
  it("本文の文字だけを取り出す", () => {
    const r = htmlToText(`<html><head><title>T &amp; X</title><script>bad()</script></head><body><nav>menu</nav><article><h1>見出し</h1><p>一つ目</p><p>二つ目 &lt;ok&gt;</p></article></body></html>`);
    expect(r.title).toBe("T & X");
    expect(r.text).toBe("見出し\n一つ目\n二つ目 <ok>");
  });
  it("YouTube の id", () => {
    expect(youtubeId("https://youtu.be/abcdefghijk")).toBe("abcdefghijk");
    expect(youtubeId("https://www.youtube.com/watch?v=abcdefghijk&t=1")).toBe("abcdefghijk");
    expect(youtubeId("https://www.youtube.com/shorts/abcdefghijk")).toBe("abcdefghijk");
    expect(youtubeId("https://example.com/watch?v=x")).toBe(null);
  });
  it("内側のアドレスは読まない・ページを読んで返す", async () => {
    const kv = memKV();
    const d = { fetch: (async () => new Response("<body><p>こんにちは</p></body>", { headers: { "content-type": "text/html" } })) as unknown as typeof fetch, now: () => new Date() };
    expect((await handle(req("GET", "/page?url=" + encodeURIComponent("http://127.0.0.1/x")), env(kv), d)).status).toBe(400);
    const r = await (await handle(req("GET", "/page?url=" + encodeURIComponent("https://e.com/a")), env(kv), d)).json() as { text: string; kind: string };
    expect(r).toMatchObject({ text: "こんにちは", kind: "page" });
  });
});
