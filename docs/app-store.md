# App Store の掲載情報（下書き）

App Store Connect に入力する文の下書き。文字数は App Store の上限に収めてある。

## 基本

| 項目 | 内容 |
|---|---|
| アプリ名 | Mindrawer |
| カテゴリ | 仕事効率化（Productivity）／サブ: ライフスタイル |
| 年齢区分 | 4+ |
| 価格 | 無料（アプリ内課金: Mindrawer Plus 月額。自分の API キーを入れれば Plus なしでも AI が使える） |
| プライバシーポリシー URL | docs/privacy-policy.md を公開した URL（例: GitHub Pages） |
| App のプライバシー（栄養ラベル） | 「データの収集なし」。Plus のときはメモが中継サーバーを通るが、その場で Claude に渡すだけで保存しない（Apple の定義ではリアルタイムの処理のみの送信は「収集」に当たらない）。自分の API キーのときは開発者を通らない |

## 日本語

**サブタイトル**（30 文字以内）
しまっておけば、必要なときに出てくる

**プロモーションテキスト**（170 文字以内）
X で見つけた Tips、スクショ、自分用の備忘録。共有ボタンから「Mindrawer」に送るだけで、AI がフォルダ分けし、使う場面とリマインド日を付けます。「これから洗濯する」と書けば、役立つメモが出てきます。

**説明**
Mindrawer（マインドロワー、「頭の引き出し」）は、日々見つけた Tips や備忘録をしまっておき、必要なときに取り出すためのメモ帳です。

● 共有シートから一発で保存
X、Safari、写真などの共有ボタンから「Mindrawer」を選ぶだけ。ひとこと書き足すこともできます。スクショを送れば、AI が画像の文字を読み取ります。

● AI が自動で整理
タイトル、要約、フォルダ、タグ、そして「このメモが役立つ場面」を Claude が付けます。本文に日付があれば、リマインドにも入ります。

● 行動や質問から取り出す
「これから洗濯する」「プレゼン前に緊張する」「節約になるやつ」。行動や困りごとを書くと、言葉が一致していなくても役立つメモを選び、短い助言と一緒に出します。

● 忘れていたメモにまた出会える
「今日のひとつ」で、しまったままのメモを毎日 1 件表示。リマインド日の朝には通知が届きます。

● 自分好みに
和紙・羊皮紙・夜空・オーロラ・桜・海など 11 種類の壁紙。編集、ピン留め、「役立った」、関連メモ、声での入力にも対応。

● プライバシー
メモは端末の中にだけ保存されます。AI で整理するときだけ Claude に送られ、Mindrawer のサーバーには保存されません。AI なしでも、キーワードでの整理と検索で使えます。

● Mindrawer Plus（月額）
AI での整理と取り出しが、設定なしですぐ使えます。初回は 1 週間無料。Anthropic の API キーをお持ちなら、Plus なしでもそのキーで AI を使えます。

お支払いは Apple ID に請求されます。期間が終わる 24 時間前までに解約しない限り、自動で更新されます。解約は App Store の設定からいつでもできます。
利用規約: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
プライバシーポリシー: （公開した URL）

**キーワード**（100 バイト以内、カンマ区切り）
メモ,Tips,備忘録,ブックマーク,スクショ,整理,AI,リマインド,共有

## English

**Subtitle** (30 chars)
Tips back when you need them

**Promotional text** (170 chars)
Share tips, screenshots and notes to Mindrawer. Claude files them and sets reminders. Type "about to do laundry" and the right tip appears.

**Description**
Mindrawer is a drawer in your mind for the tips and notes you pick up every day, built to hand them back the moment you need them.

• Save from the share sheet
Tap Share in X, Safari, Photos and more, then pick Mindrawer. Add a quick note if you like. Share a screenshot and Claude reads the text from it.

• Filed for you
Claude adds a title, a summary, a folder, tags and the moments when the note will help. Dates in the note become reminders.

• Recall by what you're doing
"About to do laundry." "Nervous before a talk." "Ways to save money." Describe what you're doing or need, and Mindrawer picks the notes that help, even without matching words, with a short piece of advice.

• Meet forgotten notes again
Today's Pick resurfaces one stored note each day, and reminders arrive on the morning they're due.

• Make it yours
Eleven wallpapers including washi, parchment, night sky, aurora, sakura and sea. Edit anything, pin, mark as helpful, see related notes, or dictate.

• Private by design
Notes stay on your device. They're sent to Claude only for filing and recall, and never stored on Mindrawer's server. Without AI, Mindrawer still files and searches by keyword.

• Mindrawer Plus (monthly)
AI filing and recall, no setup needed. Try it free for one week. Have an Anthropic API key? Use it instead, no subscription required.

Payment is charged to your Apple ID. The subscription renews automatically unless canceled at least 24 hours before the end of the period. Cancel anytime in App Store settings.
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: (your published URL)

**Keywords** (100 bytes)
notes,tips,bookmarks,screenshot,organize,AI,reminder,share,lifehack,memo

## 提出前のチェック

- [ ] `App/project.yml` の `BUNDLE_PREFIX` と `APP_GROUP` を自分のものに変える
- [ ] プライバシーポリシーを公開して URL を用意する
- [ ] ストア用の画面写真（6.9 インチ）を用意する。`scripts/screenshots.sh` の写真を元にできる
- [ ] App Store Connect で自動更新サブスクリプションを作る（下の「Mindrawer Plus」）
- [ ] `App/project.yml` の `SERVER_URL` と `PRIVACY_URL` を入れる
- [ ] 審査メモに「AI 機能は Mindrawer Plus（購読）か、利用者自身の Anthropic API キーで動く。どちらも無くてもキーワード検索で使える。購読はサンドボックスのアカウントで試せる」と書く

## Mindrawer Plus（App Store Connect に入れる内容）

| 項目 | 内容 |
|---|---|
| 種類 | 自動更新サブスクリプション |
| サブスクリプショングループ | Mindrawer Plus |
| 商品 ID | `app.mindrawer.plus.monthly`（`BUNDLE_PREFIX` に合わせる） |
| 期間 | 1 か月 |
| 値段（おすすめ） | 980 円 / 6.99 ドル。根拠は `server/README.md` の「料金の目安」 |
| お試し（導入オファー） | 1 週間無料 |
| 表示名 | Mindrawer Plus |
| 説明（45 文字以内） | AI がメモを整理し、必要なときに取り出す / AI files your notes and brings them back |
| 審査用の画面写真 | 設定画面の「Mindrawer Plus」の部分（`screenshots` ブランチの 09-settings） |

Xcode で実行すると `App/Mindrawer.storekit` の内容で購読を試せる（App Store Connect に登録する前でも動く。ただし `SERVER_URL` が空だと購読の項目は出ない）。
