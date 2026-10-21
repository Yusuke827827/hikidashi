# Mindrawer の中継サーバー（Cloudflare Workers）

Mindrawer Plus（月額の購読）の利用者が、自分の API キーなしで AI を使うためのサーバー。

1. アプリが App Store の購読の証明（StoreKit 2 の signed transaction）を `x-mindrawer-transaction` に付けて、Messages API と同じ形で送る
2. サーバーが証明を確かめる（Apple Root CA - G3 につながる鎖、App Store 署名用の印、署名、アプリ ID・商品 ID・期限・取り消し）
3. 月の利用回数と料金を数え（上限は下の「料金の目安」）、運営側の API キーで Claude を呼んで結果を返す。メモの内容は保存しない

送れるモデルは `claude-opus-5-5` だけ、`max_tokens` は 8000 まで、本文は 8MB まで。

## テスト

```sh
cd server && npm install && npm test        # テスト用の証明書の鎖をその場で作って確かめる
npm run typecheck
```

## 公開の手順（ブラウザだけでできる）

`main` に push すると GitHub Actions（`.github/workflows/server.yml`）がテストし、Cloudflare に公開する。保存場所（KV）の作成、API キーの登録、`/health` の確認まで自動で行う。必要なのは、次の 3 つの値を GitHub に登録することだけ。

1. **Cloudflare**（無料）
   - https://dash.cloudflare.com/sign-up でアカウントを作る
   - 左のメニューの「Workers & Pages」を一度開く（`workers.dev` の名前を決める画面が出たら決める）
   - 右上の人のアイコン →「My Profile」→「API Tokens」→「Create Token」→ テンプレート「Edit Cloudflare Workers」→「Use template」。Account Resources は自分のアカウント、Zone Resources は「All zones」のままで「Continue to summary」→「Create Token」。出てきたトークンを控える
   - 「Workers & Pages」の画面の右側にある「Account ID」を控える
2. **Anthropic**: https://console.anthropic.com/settings/keys で、サーバー用の API キーを作って控える（自分用とは別にしておくと、使用量を分けて見られる）
3. **GitHub**: このリポジトリの「Settings」→「Secrets and variables」→「Actions」→「New repository secret」で、次の 3 つを登録する

   | Name | 値 |
   |---|---|
   | `CLOUDFLARE_API_TOKEN` | 1 のトークン |
   | `CLOUDFLARE_ACCOUNT_ID` | 1 の Account ID |
   | `ANTHROPIC_API_KEY` | 2 の API キー |

4. 「Actions」→「Server」→「Run workflow」を押す（以後は `server/` を変えて push するたびに自動で公開される）
5. 終わると、実行結果のページに 3 つの URL が出る
   - `https://mindrawer-server.<名前>.workers.dev` → `App/project.yml` の `SERVER_URL`
   - `…/privacy` → `PRIVACY_URL` と、App Store Connect の「プライバシーポリシー URL」
   - `…/support` → App Store Connect の「サポート URL」

`wrangler.toml` の `BUNDLE_ID` と `PRODUCT_IDS` は、Apple Developer で決めた Bundle ID と App Store Connect の商品 ID に合わせる。

### 手元のパソコンから公開する場合

```sh
cd server && npm install && npx wrangler login
npx wrangler kv namespace create mindrawer-usage   # 出てきた id を wrangler.toml に書く
npx wrangler secret put ANTHROPIC_API_KEY
npm run deploy
```

## プライバシーポリシーとサポートのページ

`/privacy` と `/support` は、`docs/privacy-policy.md` と `docs/support.md` から作る（`node scripts/build-pages.mjs` で `src/pages.generated.ts` を作り直す。`npm test` は作り直し忘れを見つける）。

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
