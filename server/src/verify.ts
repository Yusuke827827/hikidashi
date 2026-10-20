// App Store が署名した購読の証明（StoreKit 2 の signed transaction, JWS）を確かめる。
// Apple 公式ライブラリ（app-store-server-library）と同じ点を見る:
//   1. x5c の証明書の鎖が「葉 → 中間 → Apple Root CA - G3」とつながり、どれも有効期限内
//   2. 葉と中間に、App Store の署名用証明書だけが持つ印（OID）がある
//      （これが無いと、Apple から開発者証明書をもらった人なら誰でも偽造できてしまう）
//   3. 葉の公開鍵で JWS の署名が正しい
// そのうえで、購読の中身（アプリ ID・商品 ID・期限・取り消し）を確かめる。

import "reflect-metadata"; // @peculiar/x509 が使う
import * as x509 from "@peculiar/x509";
import * as jose from "jose";

x509.cryptoProvider.set(crypto);

/** Apple Root CA - G3 の SHA-256 指紋（https://www.apple.com/certificateauthority/） */
export const APPLE_ROOT_CA_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
/** App Store の署名用（葉）証明書の印 */
export const OID_LEAF = "1.2.840.113635.100.6.11.1";
/** Apple WWDR 中間証明書の印 */
export const OID_INTERMEDIATE = "1.2.840.113635.100.6.2.1";

export interface TransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  type?: string;
  expiresDate?: number;
  revocationDate?: number;
  environment?: string;
}

export interface VerifyOptions {
  bundleId: string;
  productIds: string[];
  now?: Date;
  /** テスト用に差し替えられる（本番は Apple の値） */
  rootSha256?: string;
}

export class VerificationError extends Error {}

function hex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function verifyTransaction(jws: string, opts: VerifyOptions): Promise<TransactionPayload> {
  const now = opts.now ?? new Date();
  let header: jose.ProtectedHeaderParameters;
  try {
    header = jose.decodeProtectedHeader(jws);
  } catch {
    throw new VerificationError("malformed token");
  }
  if (header.alg !== "ES256") throw new VerificationError("unexpected algorithm");
  const chain = header.x5c ?? [];
  if (chain.length !== 3) throw new VerificationError("unexpected certificate chain");

  const certs = chain.map((b64) => new x509.X509Certificate(b64));
  for (const c of certs) {
    if (now < c.notBefore || now > c.notAfter) throw new VerificationError("certificate expired");
  }
  for (let i = 0; i < certs.length - 1; i++) {
    const ok = certs[i].issuer === certs[i + 1].subject && (await certs[i].verify({ publicKey: certs[i + 1].publicKey, signatureOnly: true }));
    if (!ok) throw new VerificationError("broken certificate chain");
  }
  const rootPrint = hex(await certs[2].getThumbprint("SHA-256"));
  if (rootPrint !== (opts.rootSha256 ?? APPLE_ROOT_CA_G3_SHA256)) throw new VerificationError("untrusted root");
  if (!certs[0].getExtension(OID_LEAF)) throw new VerificationError("not an App Store signing certificate");
  if (!certs[1].getExtension(OID_INTERMEDIATE)) throw new VerificationError("not an Apple intermediate certificate");

  const key = await jose.importX509(certs[0].toString("pem"), "ES256");
  let payload: TransactionPayload;
  try {
    const { payload: raw } = await jose.compactVerify(jws, key);
    payload = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    throw new VerificationError("bad signature");
  }

  if (payload.bundleId !== opts.bundleId) throw new VerificationError("wrong app");
  if (!opts.productIds.includes(payload.productId)) throw new VerificationError("wrong product");
  if (payload.revocationDate) throw new VerificationError("revoked");
  if (!payload.expiresDate || payload.expiresDate < now.getTime()) throw new VerificationError("subscription expired");
  return payload;
}
