# プライバシーポリシー / Privacy Policy

最終更新日: 2026 年 10 月 27 日 / Last updated: October 27, 2026

## 日本語

Mindrawer（以下「本アプリ」）は、利用者のメモを利用者の端末の中に保存します。開発者が利用者の情報を集めることはありません。

### 保存する情報
- 利用者が保存したメモ、スクショ、設定は、利用者の iPhone の中（本アプリと共有シートの拡張機能が使う保存領域）にだけ保存されます。
- Anthropic の API キーは、利用者の端末のキーチェーンにだけ保存されます。

### 外部に送る情報
- 利用者が API キーを設定した場合に限り、メモの整理と取り出しのために、メモの本文・タイトル・タグなどと、添付したスクショを Anthropic, PBC の Claude API に送ります。送信には利用者自身の API キーを使います。送られた情報の扱いは Anthropic のプライバシーポリシーと商用利用規約に従います（https://www.anthropic.com/legal/privacy）。
- Mindrawer Plus（月額の購読）を利用している場合は、同じ内容を本アプリの中継サーバー（Cloudflare 上）を経由して Claude API に送ります。中継サーバーは購読の確認と月の利用回数・利用料金を数えるためだけに使い、メモの内容は保存しません。利用回数は App Store の購読番号（original transaction ID）ごとに数え、約 40 日で消えます。
- API キーも購読も使わない場合、本アプリは外部と通信しません。対応する iPhone では、Apple Intelligence の端末内の AI でメモを整理します。この処理は端末の中だけで行われ、内容はどこにも送られません。

### 端末の機能を使うもの（どれも端末の中だけで使い、開発者には届きません）
- リンク先の取り込み: URL 付きでメモを保存すると、そのページのタイトルと説明を端末から直接読みに行き、メモに足します。
- カレンダー（設定でオンにしたときだけ）: 3 日先までの予定の名前を読み、関係するメモがあれば通知します。予定はどこにも送りません。
- 位置情報（メモに場所を付けたときだけ）: その場所に着いたら iOS が通知します。現在地はアプリに記録されず、送られません。
- iCloud（設定でオンにしたときだけ）: メモを利用者自身の iCloud の非公開領域に置き、同じ Apple ID の端末でそろえます。開発者は中身を見られません。
- Siri・ショートカット・iPhone の検索・ウィジェット: メモのタイトルなどを iOS に渡して表示します。

### 集めない情報
- 開発者は、分析、広告、追跡のための情報を一切集めません。アカウント登録もありません。

### 許可を求める機能
- マイクと音声認識: 声でメモを入力するときだけ使います。認識は Apple の音声認識機能で行われます。
- 写真: 選んだスクショだけを読み込みます。
- 通知: リマインド日・予定の前・場所の通知を端末の中で予約するために使います。
- カレンダー: 予定の前にメモを知らせるときだけ使います。
- 位置情報（使用中のみ）: 場所で知らせるときだけ使います。

### データの削除
- アプリ内でメモを削除するか、本アプリを削除すると、端末内のデータは消えます。

### お問い合わせ
GitHub の Issues（https://github.com/Yusuke827827/hikidashi/issues）からご連絡ください。

## English

Mindrawer ("the app") keeps your notes on your device. The developer does not collect any of your information.

### What is stored
- Notes, screenshots and settings you save stay on your iPhone, in storage shared only by the app and its share extension.
- Your Anthropic API key is stored only in your device's keychain.

### What is sent
- Only if you set an API key, the app sends note text, titles, tags and attached screenshots to Anthropic, PBC's Claude API to file and recall your notes, using your own key. Anthropic handles that data under its privacy policy and commercial terms (https://www.anthropic.com/legal/privacy).
- If you subscribe to Mindrawer Plus, the same content is sent to the Claude API through the app's relay server (on Cloudflare). The relay only checks your subscription and counts monthly usage and cost; it does not store your notes. Usage is counted per App Store original transaction ID and expires after about 40 days.
- Without an API key or a subscription, the app does not connect to any server. On supported iPhones, notes are filed by Apple Intelligence's on-device model; this happens entirely on the device and nothing is sent anywhere.

### Device features (all used on the device; nothing reaches the developer)
- Link previews: when you save a note with a URL, the app reads that page's title and description directly from your device and adds them to the note.
- Calendar (only if you turn it on): event titles for the next 3 days are read to remind you of related notes. Events are never sent anywhere.
- Location (only for notes you attach a place to): iOS notifies you when you arrive. Your location isn't recorded or sent by the app.
- iCloud (only if you turn it on): notes are stored in your own private iCloud space to sync across devices with your Apple ID. The developer can't see them.
- Siri, Shortcuts, Spotlight and widgets: note titles and summaries are handed to iOS to show them.

### What is not collected
- The developer collects no analytics, advertising or tracking data. There are no accounts.

### Permissions
- Microphone and speech recognition: used only while you dictate a note, through Apple's speech recognition.
- Photos: only the screenshot you pick is read.
- Notifications: used to schedule reminders (dates, events and places) on the device.
- Calendars: used only for hints before events.
- Location (while using): used only for place reminders.

### Deleting data
- Deleting a note in the app, or deleting the app, removes the data from your device.

### Contact
Please open an issue at https://github.com/Yusuke827827/hikidashi/issues.
