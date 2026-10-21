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

Claude（claude-opus-5-5）の料金は、100 万トークンあたり入力 4 ドル・出力 20 ドル。1 回あたりのおおよその額は次のとおり。

| 使い方 | 1 回の料金 |
|---|---|
| メモ 1 件の整理 | 約 0.02 ドル（約 3 円） |
| スクショ付きのメモの整理 | 約 0.03 ドル |
| 取り出し（メモ 100 件のとき） | 約 0.06 ドル（約 9 円） |
| 取り出し（メモ 300 件のとき） | 約 0.15 ドル |

取り出しは、しまってあるメモ全体を Claude に見せるので、メモが増えるほど高くなる。

1 人が使いすぎても赤字にならないよう、上限を 2 つ設けている。どちらかに達すると、その月はアプリに「今月の上限に達しました」と出る（自分の API キーを入れれば引き続き使える）。

- `MONTHLY_BUDGET_USD`（既定 3 ドル）: 1 人あたり月の Claude の料金の上限。応答に含まれるトークン数から計算する
- `MONTHLY_LIMIT`（既定 1500 回）: 回数の上限（念のため）

おすすめの値段は **月 980 円 / 6.99 ドル**。Apple の手数料（小規模事業者は 15%）を引くと約 5.9 ドルが残り、上限 3 ドルまで使われても赤字にならない。3 ドルあれば、メモ 60 件の整理と 30 回の取り出しくらいに足りる。値段を下げるなら、`MONTHLY_BUDGET_USD` も手取りより小さくなるよう下げること。
