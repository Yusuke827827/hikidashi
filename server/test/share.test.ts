// 共有フォルダの作成・読み書き・まとめ方を確かめる。
import { describe, expect, it } from "vitest";
import { handle, type Env } from "../src/index";
import { cleanNote, mergeShare, type ShareDoc } from "../src/share";

function memKV() {
  const m = new Map<string, string>();
  return { get: async (k: string) => m.get(k) ?? null, put: async (k: string, v: string) => void m.set(k, v), m } as unknown as KVNamespace & { m: Map<string, string> };
}

const env = (kv: KVNamespace) => ({ USAGE: kv, ANTHROPIC_API_KEY: "x", BUNDLE_ID: "b", PRODUCT_IDS: "p" }) as Env;
let clock = 1_800_000_000_000;
const deps = { fetch: (() => { throw new Error("no fetch"); }) as typeof fetch, now: () => new Date(clock) };
const req = (method: string, path: string, body?: unknown, key?: string) =>
  new Request("https://s.example" + path, { method, body: body ? JSON.stringify(body) : undefined, headers: key ? { "x-share-key": key } : {} });

describe("共有フォルダ", () => {
  it("作って、鍵がある人だけが読み書きでき、新しい方が残る", async () => {
    const kv = memKV();
    const r = await handle(req("POST", "/share", { name: "家事のコツ", notes: [{ id: "a", text: "シミは叩く", updatedAt: 1, imageFile: "x.jpg" }] }), env(kv), deps);
    expect(r.status).toBe(200);
    expect(r.headers.get("access-control-allow-origin")).toBe("*");
    const { id, key, notes } = await r.json() as { id: string; key: string; notes: Record<string, unknown>[] };
    expect(notes[0].imageFile).toBeUndefined();
    expect([...(kv as unknown as { m: Map<string, string> }).m.values()][0]).not.toContain(key);

    expect((await handle(req("GET", `/share/${id}`), env(kv), deps)).status).toBe(403);
    expect((await handle(req("GET", `/share/${id}`, undefined, "wrong"), env(kv), deps)).status).toBe(403);

    clock += 1000;
    const put = await handle(req("PUT", `/share/${id}`, { notes: [{ id: "a", text: "古い", updatedAt: 0 }, { id: "b", text: "新しいメモ", updatedAt: 5 }] }, key), env(kv), deps);
    const after = await put.json() as { notes: { id: string; text: string }[] };
    expect(after.notes.find((n) => n.id === "a")?.text).toBe("シミは叩く");
    expect(after.notes.map((n) => n.id).sort()).toEqual(["a", "b"]);

    const del = await handle(req("PUT", `/share/${id}`, { notes: [], deleted: ["a"] }, key), env(kv), deps);
    const d = await del.json() as { notes: { id: string }[]; deleted: string[] };
    expect(d.notes.map((n) => n.id)).toEqual(["b"]);
    expect(d.deleted).toContain("a");
    expect((await handle(req("OPTIONS", `/share/${id}`), env(kv), deps)).status).toBe(204);
  });

  it("消したメモは、消す前の内容を送られても戻らない", () => {
    const doc: ShareDoc = { name: "x", keyHash: "h", notes: [], deleted: { a: 100 }, updatedAt: 0 };
    expect(mergeShare(doc, [{ id: "a", updatedAt: 50, text: "" }], [], 200).notes).toHaveLength(0);
    expect(mergeShare(doc, [{ id: "a", updatedAt: 150, text: "" }], [], 200).notes).toHaveLength(1);
  });

  it("おかしなメモは捨て、長い本文は切る", () => {
    expect(cleanNote({ text: "no id" })).toBeNull();
    expect((cleanNote({ id: "a", text: "x".repeat(30_000) })!.text as string).length).toBe(20_000);
  });
});
