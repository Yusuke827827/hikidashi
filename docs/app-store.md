# App Store の掲載情報（下書き）

App Store Connect に入力する文の下書き。文字数は App Store の上限に収めてある。

## 基本

| 項目 | 内容 |
|---|---|
| アプリ名 | Mindrawer |
| カテゴリ | 仕事効率化（Productivity）／サブ: ライフスタイル |
| 年齢区分 | 4+ |
| 価格 | 無料（API キーは利用者が用意する。販売時はサーバー経由の月額に切り替える予定） |
| プライバシーポリシー URL | docs/privacy-policy.md を公開した URL（例: GitHub Pages） |
| App のプライバシー（栄養ラベル） | 「データの収集なし」。Claude に送る内容は利用者の API キーで利用者自身が送るもので、開発者は受け取らない |

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
メモは端末の中にだけ保存されます。AI を使うときは、あなた自身の Anthropic API キーで Claude に送ります。開発者があなたのデータを受け取ることはありません。API キーが無くても、キーワードでの整理と検索で使えます。

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
Notes stay on your device. When Claude is used, your notes are sent with your own Anthropic API key; the developer never receives your data. Without a key, Mindrawer still files and searches by keyword.

**Keywords** (100 bytes)
notes,tips,bookmarks,screenshot,organize,AI,reminder,share,lifehack,memo

## 提出前のチェック

- [ ] `App/project.yml` の `BUNDLE_PREFIX` と `APP_GROUP` を自分のものに変える
- [ ] プライバシーポリシーを公開して URL を用意する
- [ ] ストア用の画面写真（6.9 インチ）を用意する。`scripts/screenshots.sh` の写真を元にできる
- [ ] 審査メモに「AI 機能は利用者自身の Anthropic API キーで動く。キーなしでもキーワード検索で使える」と書く
