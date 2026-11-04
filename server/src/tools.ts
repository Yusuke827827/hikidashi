// Web 版のための読み取り（ブラウザからは他のサイトを直接読めないため、ここで読んで文字だけ返す）。
//   GET /page?url=…  → { title, text, kind }。ふつうのページは本文の文字、YouTube は字幕（無ければ説明文）
// 読むのは http(s) の公開ページだけ。中身は保存しない。

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-max-age": "86400",
};
const MAX_TEXT = 40_000;

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "public, max-age=600", ...CORS } });
}

const decode = (s: string) => s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;|&#x27;/g, "'").replace(/&nbsp;/g, " ")
  .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)));

/** HTML から本文らしい文字を取り出す（スクリプト・飾りを除き、段落ごとに改行） */
export function htmlToText(html: string): { title: string; text: string } {
  const title = decode((html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']*)/i)?.[1]) || (html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || "")).trim();
  let body = html.match(/<article[\s\S]*?<\/article>/i)?.[0] || html.match(/<main[\s\S]*?<\/main>/i)?.[0] || html.match(/<body[\s\S]*?<\/body>/i)?.[0] || html;
  body = body.replace(/<(script|style|noscript|svg|nav|header|footer|aside|form|iframe)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n").replace(/<\/(p|div|li|h[1-6]|tr|section|blockquote|pre)>/gi, "\n").replace(/<li[^>]*>/gi, "・").replace(/<[^>]+>/g, " ");
  const text = decode(body).split("\n").map((l) => l.replace(/[ \t ]+/g, " ").trim()).filter((l) => l.length > 1).join("\n").replace(/\n{3,}/g, "\n\n");
  return { title, text: text.slice(0, MAX_TEXT) };
}

/** YouTube の動画 id（youtu.be・watch?v=・shorts） */
export function youtubeId(u: string): string | null {
  try {
    const x = new URL(u);
    if (/(^|\.)youtu\.be$/.test(x.hostname)) return x.pathname.slice(1, 12) || null;
    if (/(^|\.)youtube\.com$/.test(x.hostname)) return x.searchParams.get("v") || x.pathname.match(/\/(?:shorts|embed|live)\/([\w-]{11})/)?.[1] || null;
  } catch {}
  return null;
}

/** 動画ページから、字幕（あれば日本語→英語→最初のもの）と説明文を読む */
export async function youtubeText(id: string, fetcher: typeof fetch): Promise<{ title: string; text: string; kind: string }> {
  const res = await fetcher(`https://www.youtube.com/watch?v=${id}&hl=ja`, { headers: { "accept-language": "ja,en;q=0.8", "user-agent": "Mozilla/5.0 (compatible; Mindrawer)" } });
  const html = await res.text();
  const title = decode(html.match(/<meta name="title" content="([^"]*)"/)?.[1] || html.match(/<title>([\s\S]*?)<\/title>/)?.[1]?.replace(/ - YouTube$/, "") || "");
  const desc = (() => { const m = html.match(/"shortDescription":"((?:[^"\\]|\\.)*)"/); try { return m ? JSON.parse(`"${m[1]}"`) : ""; } catch { return ""; } })();
  const tracksRaw = html.match(/"captionTracks":(\[.*?\])/)?.[1];
  if (tracksRaw) {
    try {
      const tracks = JSON.parse(tracksRaw) as { baseUrl: string; languageCode: string }[];
      const pick = tracks.find((t) => t.languageCode === "ja") || tracks.find((t) => t.languageCode.startsWith("en")) || tracks[0];
      if (pick?.baseUrl) {
        const xml = await (await fetcher(pick.baseUrl)).text();
        const lines = [...xml.matchAll(/<text[^>]*>([\s\S]*?)<\/text>/g)].map((m) => decode(decode(m[1])).replace(/\s+/g, " ").trim()).filter(Boolean);
        if (lines.length) return { title, text: lines.join(" ").slice(0, MAX_TEXT), kind: "transcript" };
      }
    } catch {}
  }
  return { title, text: String(desc).slice(0, MAX_TEXT), kind: "description" };
}

export async function handleTools(request: Request, fetcher: typeof fetch): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== "/page") return null;
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (request.method !== "GET") return reply(405, { error: "method_not_allowed" });
  const target = url.searchParams.get("url") || "";
  let u: URL;
  try { u = new URL(target); } catch { return reply(400, { error: "bad_url" }); }
  if (!/^https?:$/.test(u.protocol) || /^(localhost|127\.|10\.|192\.168\.|169\.254\.|\[)/.test(u.hostname)) return reply(400, { error: "bad_url" });
  try {
    const yt = youtubeId(u.href);
    if (yt) return reply(200, await youtubeText(yt, fetcher));
    const res = await fetcher(u.href, { headers: { "user-agent": "Mozilla/5.0 (compatible; Mindrawer)", accept: "text/html,*/*;q=0.5" }, redirect: "follow" });
    if (!res.ok) return reply(502, { error: "fetch_failed", status: res.status });
    const type = res.headers.get("content-type") || "";
    if (!/html|text\/plain/.test(type)) return reply(415, { error: "not_html" });
    const raw = (await res.text()).slice(0, 2_000_000);
    const out = /text\/plain/.test(type) ? { title: "", text: raw.slice(0, MAX_TEXT) } : htmlToText(raw);
    return reply(200, { ...out, kind: "page" });
  } catch {
    return reply(502, { error: "fetch_failed" });
  }
}
