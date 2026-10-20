# Mindrawer の中継サーバー（Cloudflare Workers）

Mindrawer Plus（月額の購読）の利用者が、自分の API キーなしで AI を使うためのサーバー。

1. アプリが App Store の購読の証明（StoreKit 2 の signed transaction）を `x-mindrawer-transaction` に付けて、Messages API と同じ形で送る
2. サーバーが証明を確かめる（Apple Root CA - G3 につながる鎖、App Store 署名用の印、署名、アプリ ID・商品 ID・期限・取り消し）
3. 月の利用回数（既定 1500 回）を数え、運営側の API キーで Claude を呼んで結果を返す。メモの内容は保存しない

送れるモデルは `claude-opus-5-5` だけ、`max_tokens` は 8000 まで、本文は 8MB まで。

## テスト

```sh
cd server && npm install && npm test        # テスト用の証明書の鎖をその場で作って確かめる
npm run typecheck
```

## 公開の手順

1. Cloudflare のアカウントを作り、`npx wrangler login`
2. 利用回数を数える保存場所を作る: `npx wrangler kv namespace create USAGE`。出てきた id を `wrangler.toml` の `REPLACE_WITH_KV_NAMESPACE_ID` に書く
3. 運営側の Anthropic API キーを登録: `npx wrangler secret put ANTHROPIC_API_KEY`
4. `wrangler.toml` の `BUNDLE_ID` と `PRODUCT_IDS` を、App Store Connect で登録したものに合わせる
5. `npm run deploy`。表示された URL（`https://mindrawer-server.<名前>.workers.dev`）を `App/project.yml` の `SERVER_URL` に書く

App Store Connect では、自動更新サブスクリプション `app.mindrawer.plus.monthly`（`BUNDLE_PREFIX` に合わせる）を作る。

## 料金の目安

利用 1 回（整理または取り出し）あたりの Claude の料金は、メモの長さとスクショの有無で変わる。上限の 1500 回を毎月使う人がいても赤字にならない価格と上限にすること。`MONTHLY_LIMIT` で上限を変えられる。
