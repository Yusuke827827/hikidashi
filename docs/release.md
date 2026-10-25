# Mac なしで App Store に出す手順

アプリのビルドと App Store Connect への送信は、GitHub の Mac（GitHub Actions）が行う。
自分でやるのはブラウザでの登録と、GitHub への値の登録だけ。パソコンが無くても、iPhone の Safari でできる。

## 1. Apple Developer に登録する（年 12,980 円）

- iPhone の「Apple Developer」アプリ（App Store で無料）を開き、「今すぐ登録」から個人で登録する。ブラウザなら https://developer.apple.com/programs/enroll/
- 承認まで 1〜2 日かかることがある
- 承認されたら https://developer.apple.com/account の「メンバーシップの詳細」で **チーム ID**（英数字 10 文字）を控える

## 2. Bundle ID を決める

アプリの世界で一つだけの名前。`com.自分の名前.mindrawer` のように、自分の名前を入れると他の人と重ならない（例: `com.yusuke827827.mindrawer`。英小文字・数字・点だけ）。

## 3. App Store Connect の API キーを作る

GitHub の Mac が、あなたの代わりに署名して送るための鍵。

1. https://appstoreconnect.apple.com →「ユーザとアクセス」→「統合」→「App Store Connect API」
2. 「チームキー」の「＋」で、名前は「GitHub」、アクセスは **Admin** で作る
3. 表示される **Issuer ID** と **キー ID** を控える
4. 「API キーをダウンロード」で `AuthKey_XXXX.p8` を保存する（**1 回しかダウンロードできない**）
5. そのファイルをメモ帳（iPhone なら「ファイル」アプリ）で開き、`-----BEGIN PRIVATE KEY-----` から `-----END PRIVATE KEY-----` までを全部コピーする

## 4. GitHub に登録する

このリポジトリの「Settings」→「Secrets and variables」→「Actions」。

**Secrets**（「Secrets」タブ →「New repository secret」）

| Name | 値 |
|---|---|
| `APPLE_TEAM_ID` | 1 のチーム ID |
| `ASC_ISSUER_ID` | 3 の Issuer ID |
| `ASC_KEY_ID` | 3 のキー ID |
| `ASC_KEY_P8` | 3 でコピーした中身（BEGIN から END まで全部） |

**Variables**（「Variables」タブ →「New repository variable」）

| Name | 値 |
|---|---|
| `BUNDLE_PREFIX` | 2 の Bundle ID |
| `SERVER_URL` | 中継サーバーの URL（`server/README.md` で公開したもの。まだなら後で） |
| `PRIVACY_URL` | 中継サーバーの URL の後ろに `/privacy` を付けたもの |

`BUNDLE_PREFIX` を入れたら、中継サーバーも一度公開し直す（「Actions」→「Server」→「Run workflow」）。サーバーが確かめる Bundle ID と商品 ID が、これに合わせて変わる。

## 5. 一度ビルドする（Bundle ID の登録）

「Actions」→「Release」→「Run workflow」で、「App Store Connect に送る」を**オフ**にして実行する。
これで Bundle ID と App Group（`group.` + Bundle ID）が Apple に自動で登録される。

## 6. App Store Connect でアプリを作る

https://appstoreconnect.apple.com →「アプリ」→「＋」→「新規アプリ」

- プラットフォーム: iOS / 名前: Mindrawer / 言語: 日本語
- バンドル ID: 5 で登録されたものを選ぶ / SKU: `mindrawer`（何でもよい）

## 7. 送る

「Actions」→「Release」→「Run workflow」（「送る」は**オン**のまま）。
10〜30 分で App Store Connect の「TestFlight」に出る。

**iPhone で試す**: App Store で「TestFlight」アプリを入れ、App Store Connect の「TestFlight」→「内部テスト」で自分を追加すると、iPhone に入れられる。

2 回目からは、直したいことがあれば push → 「Release」を実行、で新しいビルドが届く（ビルド番号は自動で増える）。

## 8. 審査に出す

`docs/app-store.md` の内容を App Store Connect に入れる。

- 画面写真: このリポジトリの `screenshots` ブランチの `store/ja` と `store/en`（6.9 インチ用）。GitHub の画面でファイルを開き「Download」
- 有料 App の契約と口座:「ビジネス」→「契約」で「有料 App」に同意し、銀行口座と税の情報を入れる（これが済まないと Plus を売れない）
- Mindrawer Plus の商品: `docs/app-store.md` の「Mindrawer Plus」。商品 ID は `Bundle ID.plus.monthly`
- App Store Small Business Program に申し込む（手数料が 30% → 15%）: https://developer.apple.com/app-store/small-business-program/

最後に「審査に提出」。審査は 1〜3 日ほど。

## うまくいかないとき

- **「No profiles for ... were found」「Cloud signing permission error」**: API キーのアクセスが Admin になっているか確かめる
- **「No suitable application records were found」**: 6 のアプリ作成がまだ。作ってから 7 をやり直す
- **「The bundle version must be higher」**: もう一度「Release」を実行する（番号が自動で増える）
- 実行結果のページの赤い行をそのまま貼ってもらえれば、直します
