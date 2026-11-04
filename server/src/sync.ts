// 自分の端末どうしの同期（Web 版・iPhone・Mac）。
// 同期コードを知っている端末だけが読み書きできる。中身は端末の中で同期コードから作った鍵で暗号にしてから送るので、
// サーバーは暗号文しか持たない（id も同期コードから作ったハッシュ）。
//   GET /sync/<id>        → { ver, data }（まだ無ければ ver: 0, data: null）
//   PUT /sync/<id>        ← { ver, data }。ver が今の版と同じときだけ置き換える（違えば 409 と今の内容）
// 保存先は KV（sync: で始まる鍵）。1 年使わなければ消える。

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, PUT, OPTIONS",
  "access-control-allow-headers": "content-type",
  "access-control-max-age": "86400",
};
export const SYNC_MAX = 10 * 1024 * 1024;
const TTL = 60 * 60 * 24 * 365;

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...CORS } });
}

interface Stored { ver: number; data: string; at: number }

export async function handleSync(request: Request, kv: KVNamespace, now: number): Promise<Response | null> {
  const url = new URL(request.url);
  const m = url.pathname.match(/^\/sync\/([0-9a-f]{64})$/);
  if (!m && !url.pathname.startsWith("/sync")) return null;
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (!m) return reply(404, { error: "not_found" });
  const key = "sync:" + m[1];
  const cur = JSON.parse((await kv.get(key)) || "null") as Stored | null;
  if (request.method === "GET") return reply(200, { ver: cur?.ver ?? 0, data: cur?.data ?? null, at: cur?.at ?? null });
  if (request.method !== "PUT") return reply(405, { error: "method_not_allowed" });
  const len = Number(request.headers.get("content-length") ?? "0");
  if (len > SYNC_MAX) return reply(413, { error: "too_large" });
  const text = await request.text();
  if (text.length > SYNC_MAX) return reply(413, { error: "too_large" });
  let b: { ver?: unknown; data?: unknown };
  try { b = JSON.parse(text); } catch { return reply(400, { error: "bad_request" }); }
  if (typeof b.data !== "string" || !b.data || typeof b.ver !== "number") return reply(400, { error: "bad_request" });
  const have = cur?.ver ?? 0;
  if (b.ver !== have) return reply(409, { ver: have, data: cur?.data ?? null });
  const next: Stored = { ver: have + 1, data: b.data, at: now };
  await kv.put(key, JSON.stringify(next), { expirationTtl: TTL });
  return reply(200, { ver: next.ver });
}
