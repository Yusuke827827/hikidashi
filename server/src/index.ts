// Mindrawer の購読者向け AI 中継サーバー（Cloudflare Workers）。
// アプリは購読の証明（x-mindrawer-transaction）を付けて Messages API と同じ形で送る。
// ここで証明を確かめ、月の利用回数を数え、運営側の API キーで Claude を呼んで結果をそのまま返す。
// 送ってよい内容は絞る（モデル・max_tokens・本文の大きさ）。メモの中身は保存しない。

import { PRIVACY_HTML, SUPPORT_HTML } from "./pages.generated";
import { VerificationError, verifyTransaction } from "./verify";

export interface Env {
  ANTHROPIC_API_KEY: string;
  /** アプリの Bundle ID（例: app.mindrawer） */
  BUNDLE_ID: string;
  /** 購読の商品 ID（カンマ区切り） */
  PRODUCT_IDS: string;
  /** 1 人あたり月の上限回数 */
  MONTHLY_LIMIT?: string;
  /** 1 人あたり月の Claude の料金の上限（米ドル）。売上から Apple の手数料を引いた額より小さくする */
  MONTHLY_BUDGET_USD?: string;
  USAGE: KVNamespace;
}

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ALLOWED_MODELS = ["claude-opus-5-5"];
const ALLOWED_BETAS = ["server-side-fallback-2026-07-01"];
const MAX_TOKENS = 8000;
const MAX_BODY_BYTES = 8 * 1024 * 1024;
/** claude-opus-5-5 の料金（100 万トークンあたりの米ドル） */
const PRICE_PER_MTOK = { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 };

/** 応答の usage から料金（米ドル）を出す */
export function costUSD(usage: unknown): number {
  if (!usage || typeof usage !== "object") return 0;
  const u = usage as Record<string, unknown>;
  const n = (k: string) => (typeof u[k] === "number" ? (u[k] as number) : 0);
  return (
    n("input_tokens") * PRICE_PER_MTOK.input +
    n("output_tokens") * PRICE_PER_MTOK.output +
    n("cache_read_input_tokens") * PRICE_PER_MTOK.cacheRead +
    n("cache_creation_input_tokens") * PRICE_PER_MTOK.cacheWrite
  ) / 1_000_000;
}

export interface Deps {
  fetch: typeof fetch;
  now: () => Date;
  rootSha256?: string;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function error(status: number, type: string, message: string): Response {
  return json(status, { type: "error", error: { type, message } });
}

/** 送ってよい内容だけを残した本文を返す。だめなら null */
export function sanitize(body: unknown): Record<string, unknown> | null {
  if (!body || typeof body !== "object") return null;
  const b = body as Record<string, unknown>;
  if (typeof b.model !== "string" || !ALLOWED_MODELS.includes(b.model)) return null;
  if (!Array.isArray(b.messages) || b.messages.length === 0) return null;
  const out: Record<string, unknown> = {
    model: b.model,
    max_tokens: Math.min(Number(b.max_tokens) || MAX_TOKENS, MAX_TOKENS),
    messages: b.messages,
  };
  if (b.output_config && typeof b.output_config === "object") out.output_config = b.output_config;
  if (b.fallbacks === "default") out.fallbacks = "default";
  return out;
}

export async function handle(request: Request, env: Env, deps: Deps): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/health") return json(200, { ok: true });
  // App Store に載せるプライバシーポリシーとサポートのページ
  if (request.method === "GET" && (url.pathname === "/privacy" || url.pathname === "/support")) {
    const html = url.pathname === "/privacy" ? PRIVACY_HTML : SUPPORT_HTML;
    return new Response(html, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=3600" } });
  }
  if (request.method !== "POST" || url.pathname !== "/v1/messages") return error(404, "not_found_error", "Not found");

  const jws = request.headers.get("x-mindrawer-transaction");
  if (!jws) return error(401, "authentication_error", "Missing subscription");
  let originalId: string;
  try {
    const tx = await verifyTransaction(jws, {
      bundleId: env.BUNDLE_ID,
      productIds: env.PRODUCT_IDS.split(",").map((s) => s.trim()).filter(Boolean),
      now: deps.now(),
      rootSha256: deps.rootSha256,
    });
    originalId = tx.originalTransactionId;
  } catch (e) {
    if (e instanceof VerificationError) return error(403, "permission_error", `Subscription not valid: ${e.message}`);
    throw e;
  }

  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > MAX_BODY_BYTES) return error(413, "request_too_large", "Request too large");
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) return error(413, "request_too_large", "Request too large");
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return error(400, "invalid_request_error", "Body must be JSON");
  }
  const body = sanitize(parsed);
  if (!body) return error(400, "invalid_request_error", "Request not allowed");

  // 月の利用回数と料金（KV は厳密ではないが、使いすぎ防止には足りる）
  const month = deps.now().toISOString().slice(0, 7);
  const usageKey = `usage:${originalId}:${month}`;
  const costKey = `cost:${originalId}:${month}`;
  const ttl = { expirationTtl: 60 * 60 * 24 * 40 };
  const used = Number((await env.USAGE.get(usageKey)) ?? "0");
  const spent = Number((await env.USAGE.get(costKey)) ?? "0");
  const limit = Number(env.MONTHLY_LIMIT ?? "1500");
  const budget = Number(env.MONTHLY_BUDGET_USD ?? "3");
  if (used >= limit || spent >= budget) return error(429, "rate_limit_error", "Monthly limit reached");
  await env.USAGE.put(usageKey, String(used + 1), ttl);

  const beta = request.headers.get("anthropic-beta");
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-api-key": env.ANTHROPIC_API_KEY,
    "anthropic-version": "2023-06-01",
  };
  if (beta && ALLOWED_BETAS.includes(beta)) headers["anthropic-beta"] = beta;
  const upstream = await deps.fetch(ANTHROPIC_URL, { method: "POST", headers, body: JSON.stringify(body) });
  const result = await upstream.text();
  let cost = 0;
  try {
    cost = costUSD((JSON.parse(result) as { usage?: unknown }).usage);
  } catch {
    // JSON でない応答（障害時など）は料金なしとして扱う
  }
  if (cost > 0) await env.USAGE.put(costKey, String(spent + cost), ttl);
  return new Response(result, { status: upstream.status, headers: { "content-type": "application/json" } });
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env, { fetch: (...a) => fetch(...a), now: () => new Date() });
  },
};
