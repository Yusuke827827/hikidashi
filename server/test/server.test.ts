// テスト用に「Apple 風」の証明書の鎖をその場で作り、購読の証明の確認と中継の動きを確かめる。

import "reflect-metadata";
import * as x509 from "@peculiar/x509";
import * as jose from "jose";
import { beforeAll, describe, expect, it } from "vitest";
import { handle, sanitize, type Env } from "../src/index";
import { OID_INTERMEDIATE, OID_LEAF, verifyTransaction } from "../src/verify";

x509.cryptoProvider.set(crypto);

const alg = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" } as const;
const NOW = new Date("2026-10-19T12:00:00Z");
const DAY = 86400_000;

interface Chain {
  x5c: string[];
  leafKey: CryptoKey;
  rootSha256: string;
}

async function keys() {
  return (await crypto.subtle.generateKey(alg, true, ["sign", "verify"])) as CryptoKeyPair;
}

const b64 = (c: x509.X509Certificate) => Buffer.from(c.rawData).toString("base64");
const marker = (oid: string) => new x509.Extension(oid, false, new Uint8Array([0x05, 0x00]));

/** root → intermediate → leaf。印（OID）を付けるかどうかを選べる */
async function makeChain(opts: { leafOid?: boolean; interOid?: boolean; leafExpired?: boolean } = {}): Promise<Chain> {
  const { leafOid = true, interOid = true, leafExpired = false } = opts;
  const rootKeys = await keys();
  const interKeys = await keys();
  const leafKeys = await keys();
  const notBefore = new Date(NOW.getTime() - 365 * DAY);
  const notAfter = new Date(NOW.getTime() + 365 * DAY);
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01", name: "CN=Test Root CA", notBefore, notAfter, keys: rootKeys, signingAlgorithm: alg,
    extensions: [new x509.BasicConstraintsExtension(true, undefined, true)],
  });
  const inter = await x509.X509CertificateGenerator.create({
    serialNumber: "02", subject: "CN=Test WWDR", issuer: root.subject, notBefore, notAfter,
    publicKey: interKeys.publicKey, signingKey: rootKeys.privateKey, signingAlgorithm: alg,
    extensions: [new x509.BasicConstraintsExtension(true, 0, true), ...(interOid ? [marker(OID_INTERMEDIATE)] : [])],
  });
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03", subject: "CN=Test App Store Signing", issuer: inter.subject, notBefore,
    notAfter: leafExpired ? new Date(NOW.getTime() - DAY) : notAfter,
    publicKey: leafKeys.publicKey, signingKey: interKeys.privateKey, signingAlgorithm: alg,
    extensions: leafOid ? [marker(OID_LEAF)] : [],
  });
  const thumb = new Uint8Array(await root.getThumbprint("SHA-256"));
  return {
    x5c: [b64(leaf), b64(inter), b64(root)],
    leafKey: leafKeys.privateKey,
    rootSha256: [...thumb].map((b) => b.toString(16).padStart(2, "0")).join(""),
  };
}

async function sign(chain: Chain, payload: Record<string, unknown>): Promise<string> {
  return new jose.CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
    .setProtectedHeader({ alg: "ES256", x5c: chain.x5c })
    .sign(chain.leafKey);
}

const goodPayload = {
  transactionId: "2000000001",
  originalTransactionId: "2000000000",
  bundleId: "app.mindrawer",
  productId: "app.mindrawer.plus.monthly",
  type: "Auto-Renewable Subscription",
  expiresDate: NOW.getTime() + 20 * DAY,
};
const verifyOpts = (c: Chain) => ({ bundleId: "app.mindrawer", productIds: ["app.mindrawer.plus.monthly"], now: NOW, rootSha256: c.rootSha256 });

let chain: Chain;
beforeAll(async () => {
  chain = await makeChain();
});

describe("verifyTransaction", () => {
  it("accepts a valid subscription", async () => {
    const tx = await verifyTransaction(await sign(chain, goodPayload), verifyOpts(chain));
    expect(tx.originalTransactionId).toBe("2000000000");
  });

  it("rejects a chain to a different root", async () => {
    const other = await makeChain();
    await expect(verifyTransaction(await sign(other, goodPayload), verifyOpts(chain))).rejects.toThrow("untrusted root");
  });

  it("rejects a certificate without the App Store signing marker (e.g. a developer certificate)", async () => {
    const dev = await makeChain({ leafOid: false });
    await expect(verifyTransaction(await sign(dev, goodPayload), verifyOpts(dev))).rejects.toThrow("not an App Store signing certificate");
  });

  it("rejects an intermediate without the WWDR marker", async () => {
    const c = await makeChain({ interOid: false });
    await expect(verifyTransaction(await sign(c, goodPayload), verifyOpts(c))).rejects.toThrow("not an Apple intermediate certificate");
  });

  it("rejects an expired certificate", async () => {
    const c = await makeChain({ leafExpired: true });
    await expect(verifyTransaction(await sign(c, goodPayload), verifyOpts(c))).rejects.toThrow("certificate expired");
  });

  it("rejects a tampered payload", async () => {
    const jws = await sign(chain, goodPayload);
    const [h, , s] = jws.split(".");
    const forged = Buffer.from(JSON.stringify({ ...goodPayload, expiresDate: NOW.getTime() + 999 * DAY })).toString("base64url");
    await expect(verifyTransaction(`${h}.${forged}.${s}`, verifyOpts(chain))).rejects.toThrow("bad signature");
  });

  it("checks app, product, expiry and revocation", async () => {
    const o = verifyOpts(chain);
    await expect(verifyTransaction(await sign(chain, { ...goodPayload, bundleId: "com.other" }), o)).rejects.toThrow("wrong app");
    await expect(verifyTransaction(await sign(chain, { ...goodPayload, productId: "x" }), o)).rejects.toThrow("wrong product");
    await expect(verifyTransaction(await sign(chain, { ...goodPayload, expiresDate: NOW.getTime() - 1 }), o)).rejects.toThrow("subscription expired");
    await expect(verifyTransaction(await sign(chain, { ...goodPayload, revocationDate: NOW.getTime() }), o)).rejects.toThrow("revoked");
  });
});

describe("sanitize", () => {
  it("keeps only allowed fields and caps max_tokens", () => {
    const out = sanitize({ model: "claude-opus-5-5", max_tokens: 99999, messages: [{ role: "user", content: "hi" }], tools: [{}], system: "x", fallbacks: "default" });
    expect(out).toEqual({ model: "claude-opus-5-5", max_tokens: 8000, messages: [{ role: "user", content: "hi" }], fallbacks: "default" });
  });
  it("rejects other models", () => {
    expect(sanitize({ model: "claude-fable-5-1", max_tokens: 10, messages: [{ role: "user", content: "hi" }] })).toBeNull();
  });
});

describe("handle", () => {
  function memoryKV(): KVNamespace {
    const m = new Map<string, string>();
    return { get: async (k: string) => m.get(k) ?? null, put: async (k: string, v: string) => void m.set(k, v) } as unknown as KVNamespace;
  }
  const env = (): Env => ({ ANTHROPIC_API_KEY: "sk-server", BUNDLE_ID: "app.mindrawer", PRODUCT_IDS: "app.mindrawer.plus.monthly", MONTHLY_LIMIT: "2", USAGE: memoryKV() });
  const body = JSON.stringify({ model: "claude-opus-5-5", max_tokens: 100, messages: [{ role: "user", content: "hi" }] });

  it("forwards a subscriber's request with the server key and counts usage", async () => {
    const sent: { url: string; init: RequestInit }[] = [];
    const deps = {
      now: () => NOW,
      rootSha256: chain.rootSha256,
      fetch: (async (url: string, init: RequestInit) => {
        sent.push({ url, init });
        return new Response(JSON.stringify({ stop_reason: "end_turn", content: [] }), { status: 200 });
      }) as unknown as typeof fetch,
    };
    const e = env();
    const req = () => new Request("https://w.example/v1/messages", { method: "POST", body, headers: { "x-mindrawer-transaction": "", "anthropic-beta": "server-side-fallback-2026-07-01" } });
    const jws = await sign(chain, goodPayload);
    const withTx = () => { const r = req(); r.headers.set("x-mindrawer-transaction", jws); return r; };

    expect((await handle(withTx(), e, deps)).status).toBe(200);
    expect(sent[0].url).toBe("https://api.anthropic.com/v1/messages");
    const h = sent[0].init.headers as Record<string, string>;
    expect(h["x-api-key"]).toBe("sk-server");
    expect(h["anthropic-beta"]).toBe("server-side-fallback-2026-07-01");

    expect((await handle(withTx(), e, deps)).status).toBe(200);
    expect((await handle(withTx(), e, deps)).status).toBe(429); // 月 2 回の上限
    expect(sent.length).toBe(2);
  });

  it("refuses requests without a valid subscription", async () => {
    const deps = { now: () => NOW, rootSha256: chain.rootSha256, fetch: (async () => { throw new Error("must not call"); }) as unknown as typeof fetch };
    const noTx = new Request("https://w.example/v1/messages", { method: "POST", body });
    expect((await handle(noTx, env(), deps)).status).toBe(401);
    const expired = await sign(chain, { ...goodPayload, expiresDate: NOW.getTime() - 1 });
    const bad = new Request("https://w.example/v1/messages", { method: "POST", body, headers: { "x-mindrawer-transaction": expired } });
    expect((await handle(bad, env(), deps)).status).toBe(403);
  });
});
