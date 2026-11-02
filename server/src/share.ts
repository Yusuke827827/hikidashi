// 共有フォルダ。家族や友だちと 1 つのフォルダのメモを一緒に使う。
// 共有コード（id と鍵）を知っている人だけが読み書きできる。鍵はハッシュにして保存する。
// 各端末は自分のフォルダのメモを送り、サーバーはメモごとに新しい方（updatedAt）を残して全員分を返す。
// 消したメモは「消した印」を 90 日残し、ほかの端末でも消えるようにする。保存先は利用回数と同じ KV（share: で始まる鍵）。

export interface SharedNote {
  id: string;
  updatedAt: number;
  [k: string]: unknown;
}

export interface ShareDoc {
  name: string;
  keyHash: string;
  notes: SharedNote[];
  /** 消したメモの id と日時 */
  deleted: Record<string, number>;
  updatedAt: number;
}

export const SHARE_LIMITS = { notes: 500, textChars: 20_000, bodyBytes: 2 * 1024 * 1024, tombstoneDays: 90 };

/** 端末にしか無いもの（画像・ファイル）は共有しない。本文は長すぎれば切る */
const DROP_FIELDS = ["imageFile", "file", "place", "folderChosen", "review", "checkedAt", "linkBroken", "plannedDay", "lastSeen"];

export function cleanNote(n: unknown): SharedNote | null {
  if (!n || typeof n !== "object") return null;
  const x = { ...(n as Record<string, unknown>) };
  if (typeof x.id !== "string" || !x.id || x.id.length > 80) return null;
  if (typeof x.text !== "string") return null;
  for (const f of DROP_FIELDS) delete x[f];
  x.text = (x.text as string).slice(0, SHARE_LIMITS.textChars);
  for (const f of ["title", "summary", "category", "url", "fileTitle", "original"]) {
    if (x[f] != null && typeof x[f] !== "string") delete x[f];
    if (typeof x[f] === "string") x[f] = (x[f] as string).slice(0, f === "original" ? SHARE_LIMITS.textChars : 500);
  }
  x.updatedAt = Number(x.updatedAt) || Number(x.createdAt) || 0;
  return x as SharedNote;
}

/** 送られたメモと消した印を、保存しているものにまとめる（メモごとに新しい方を残す） */
export function mergeShare(doc: ShareDoc, incoming: SharedNote[], deleted: string[], now: number): ShareDoc {
  const byId = new Map(doc.notes.map((n) => [n.id, n]));
  const tomb = { ...doc.deleted };
  for (const id of deleted) {
    if (typeof id !== "string") continue;
    tomb[id] = now;
    byId.delete(id);
  }
  for (const n of incoming) {
    const t = tomb[n.id];
    if (t && n.updatedAt <= t) continue; // 消したあとに直したものでなければ戻さない
    if (t) delete tomb[n.id];
    const cur = byId.get(n.id);
    if (!cur || n.updatedAt >= cur.updatedAt) byId.set(n.id, n);
  }
  const cut = now - SHARE_LIMITS.tombstoneDays * 86400_000;
  for (const [id, t] of Object.entries(tomb)) if (t < cut) delete tomb[id];
  const notes = [...byId.values()].sort((a, b) => b.updatedAt - a.updatedAt).slice(0, SHARE_LIMITS.notes);
  return { ...doc, notes, deleted: tomb, updatedAt: now };
}

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, PUT, OPTIONS",
  "access-control-allow-headers": "content-type, x-share-key",
  "access-control-max-age": "86400",
};

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...CORS } });
}

const ALPHA = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
export function randomToken(len: number): string {
  const b = crypto.getRandomValues(new Uint8Array(len));
  return [...b].map((x) => ALPHA[x % ALPHA.length]).join("");
}

export async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function sameHash(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  const len = Number(request.headers.get("content-length") || 0);
  if (len > SHARE_LIMITS.bodyBytes) return null;
  const text = await request.text();
  if (text.length > SHARE_LIMITS.bodyBytes) return null;
  try {
    const j = JSON.parse(text || "{}");
    return j && typeof j === "object" ? j : null;
  } catch {
    return null;
  }
}

const notesOf = (b: Record<string, unknown>) => (Array.isArray(b.notes) ? b.notes : []).map(cleanNote).filter((n): n is SharedNote => !!n);
const view = (d: ShareDoc) => ({ name: d.name, notes: d.notes, deleted: Object.keys(d.deleted), updatedAt: d.updatedAt });

/** /share で始まる道を受け持つ。当てはまらなければ null */
export async function handleShare(request: Request, kv: KVNamespace, now: number): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/share")) return null;
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  // 新しく共有する
  if (url.pathname === "/share" && request.method === "POST") {
    const body = await readBody(request);
    if (!body) return reply(400, { error: "bad_request" });
    const name = String(body.name || "").trim().slice(0, 40);
    if (!name) return reply(400, { error: "name_required" });
    const id = randomToken(12), key = randomToken(24);
    const doc = mergeShare({ name, keyHash: await sha256(key), notes: [], deleted: {}, updatedAt: now }, notesOf(body), [], now);
    await kv.put("share:" + id, JSON.stringify(doc));
    return reply(200, { id, key, ...view(doc) });
  }

  const m = url.pathname.match(/^\/share\/([A-Za-z0-9]{6,40})$/);
  if (!m) return reply(404, { error: "not_found" });
  const raw = await kv.get("share:" + m[1]);
  if (!raw) return reply(404, { error: "not_found" });
  const doc = JSON.parse(raw) as ShareDoc;
  const key = request.headers.get("x-share-key") || "";
  if (!key || !sameHash(await sha256(key), doc.keyHash)) return reply(403, { error: "forbidden" });

  if (request.method === "GET") return reply(200, view(doc));
  if (request.method === "PUT") {
    const body = await readBody(request);
    if (!body) return reply(400, { error: "bad_request" });
    const deleted = Array.isArray(body.deleted) ? (body.deleted as unknown[]).filter((x): x is string => typeof x === "string").slice(0, 1000) : [];
    let next = mergeShare(doc, notesOf(body), deleted, now);
    if (typeof body.name === "string" && body.name.trim()) next = { ...next, name: body.name.trim().slice(0, 40) };
    await kv.put("share:" + m[1], JSON.stringify(next));
    return reply(200, view(next));
  }
  return reply(405, { error: "method_not_allowed" });
}
