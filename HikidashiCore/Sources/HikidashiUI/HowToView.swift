// 設定から開く「使い方」。しまう・ひきだす・共有シート・AI の種類などを短く説明する。

#if os(iOS)
import HikidashiKit
import SwiftUI

struct HowToView: View {
    struct Step: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    static var steps: [Step] {
        [
            Step(icon: "square.and.arrow.down",
                 title: L("しまう", "Save"),
                 body: L("上の欄に Tips やメモを書いて「しまう」を押します。出典の URL、写真・スクショ（🖼）、PDF などのファイル（📎）、紙の書類のスキャン（📄）も付けられ、中の文字を iPhone の中で読み取って整理します。声で入れたいときは、キーボードのマイクを押してください。",
                         "Type a tip or note in the box at the top and tap Save. You can attach a link, a photo or screenshot, a file such as a PDF, or scan a paper document; the text inside is read on your iPhone and filed. To dictate, tap the mic on the keyboard.")),
            Step(icon: "square.and.arrow.up",
                 title: L("共有シートから保存", "Save from the share sheet"),
                 body: L("X・Safari・写真などで共有ボタンを押し、「Mindrawer」を選びます。ひとこと書き足すこともできます。出てこないときは、アプリの列の右端「その他」から追加してください。",
                         "In X, Safari, Photos and more, tap Share and pick Mindrawer. You can add a short note. If it isn't listed, add it from More at the end of the app row.")),
            Step(icon: "list.bullet.rectangle",
                 title: L("メモ風にまとめる", "Condense into a memo"),
                 body: L("入力欄か設定で「長い文はメモ風にまとめる」をオンにすると、コピペした長い文章を AI が箇条書きの短いメモに整えます。「しまう」を押すと、まとめた結果が出るので、直してから保存できます。元の文は「原文と関連」から見られ、戻せます。",
                         "Turn on Condense long text in the input box or Settings, and AI rewrites pasted long text as a short bulleted memo. Tap Save to review and edit it first. The original is kept under More and can be restored.")),
            Step(icon: "sparkles",
                 title: L("AI が整理", "AI files it"),
                 body: L("しまったメモに、タイトル・要約・フォルダ・タグ・「役立つ場面」を AI が付けます。本文に日付があれば、その日の朝 9 時に通知します。",
                         "AI adds a title, summary, folder, tags and the moments it will help. If the note mentions a date, you get a reminder at 9 AM that day.")),
            Step(icon: "folder.badge.gearshape",
                 title: L("フォルダとお気に入り", "Folders and favorites"),
                 body: L("フォルダの横の歯車から、フォルダを作る・名前を変える・まとめる・消すができます。★ を付けたフォルダは先頭に出ます。似たフォルダができると「まとめますか？」と提案します。メモの ★ でお気に入りにすると、「★ お気に入り」にまとまります。",
                         "Use the gear next to Folders to create, rename, merge or delete folders. Starred folders come first. When similar folders appear, Mindrawer suggests merging them. Star a note to add it to ★ Favorites.")),
            Step(icon: "magnifyingglass",
                 title: L("ひきだす", "Recall"),
                 body: L("「ひきだす」に切り替えて、これからすることや困りごとを書きます。例:「これから洗濯する」「プレゼン前で緊張する」「節約になるやつ」。言葉が一致していなくても、役立つメモと短い助言が出ます。",
                         "Switch to Recall and describe what you're about to do or what's bothering you, e.g. \"About to do laundry\" or \"Nervous before a talk\". You get the notes that help, plus short advice, even without matching words.")),
            Step(icon: "sun.max",
                 title: L("今日のひとつ", "Today's pick"),
                 body: L("しまったままのメモを毎日 1 件見せます。「役立った」を押したメモは、取り出しで優先されます。",
                         "One stored note resurfaces each day. Notes you mark Helpful come first when you recall.")),
            Step(icon: "checklist",
                 title: L("通知と今日の確認リスト", "Notifications and today's checklist"),
                 body: L("メモの編集の「通知する」で、日時・毎日・何日おき・曜日・毎月を選べます（音は鳴らず、通知に出るだけ）。その日のメモはホームの「今日の確認リスト」に並び、○ を押すとチェックが付きます。メモの「…」→「今日のリストに入れる」でも足せます。言葉を決めておくと、その言葉を入力したときにメモを出します。",
                         "In a note's editor, Notify me lets you pick a date, daily, every N days, weekdays or monthly (silent, shown as a notification). Those notes line up in Today's checklist on the home screen; tap ○ to check them off. Add any note with … → Add to today's list. Set words to see the note when you type them.")),
            Step(icon: "calendar.badge.clock",
                 title: L("予定・場所で知らせる", "Hints by event and place"),
                 body: L("設定で「予定の前にメモを知らせる」をオンにすると、予定に合うメモを前の日の夜 8 時に通知します（例: 出張 → 荷造りのコツ）。メモの編集で「場所を選ぶ」と、その場所に着いたときに知らせます。",
                         "Turn on Hints before events in Settings to get matching notes at 8 PM the day before (e.g. a trip → packing tips). In a note's editor, Choose a place to be reminded when you arrive.")),
            Step(icon: "rectangle.on.rectangle",
                 title: L("ウィジェット・Siri・検索", "Widget, Siri and Search"),
                 body: L("ホーム画面を長押し →「＋」→ Mindrawer で、今日のひとつを置けます。「Hey Siri、Mindrawer でひきだす」「Mindrawer にしまう」も使えます。しまったメモは iPhone の検索にも出ます。",
                         "Long-press the Home Screen → + → Mindrawer to add Today's pick. Say \"Hey Siri, recall in Mindrawer\" or \"Save to Mindrawer\". Notes also show up in iPhone Search.")),
            Step(icon: "ellipsis.circle",
                 title: L("メモの操作", "Working with notes"),
                 body: L("メモの「…」から、編集・AI で再整理・画像で共有・出典の共有・削除ができます。ピン留めしたメモは上に出ます。一覧は「分類」と「日付」で切り替えられます。",
                         "Use … on a note to edit, re-file with AI, share it as an image, share the source or delete. Pinned notes stay on top. Switch the list between Topic and Date.")),
            Step(icon: "bubble.left.and.text.bubble.right",
                 title: L("メモに聞く・まとめノート", "Ask your notes, combined notes"),
                 body: L("右上の吹き出しから、しまったメモについて会話で聞けます。「ひきだす」の結果からは「まとめノートを作る」で、関係するメモを AI が 1 枚（手順・チェックリスト）にまとめます。日曜と月曜には、今週のふりかえりが出ます。",
                         "Tap the speech bubbles at the top to ask about your notes. From Recall results, Combine these into one note turns related notes into one guide or checklist. On Sundays and Mondays you get a weekly review.")),
            Step(icon: "line.3.horizontal.decrease.circle",
                 title: L("絞り込みとすぐしまうボタン", "Filters and quick save"),
                 body: L("一覧の横のボタンで、期間・タグ・お気に入り・添付・通知付きで絞り込めます。iOS 18 以降は、コントロールセンターやアクションボタンに「Mindrawer にしまう」を置けます。",
                         "Use the button next to the list to filter by period, tags, favorites, attachments or notifications. On iOS 18 or later, add Save to Mindrawer to Control Center or the Action button.")),
            Step(icon: "lock.shield",
                 title: L("ロック・バックアップ・ゴミ箱", "Lock, backup and trash"),
                 body: L("設定の「安心」で、Face ID のロック、毎週の自動バックアップ（ファイル App の Mindrawer → Backups）、ゴミ箱（30 日は戻せる）を使えます。",
                         "Under Safety in Settings: Face ID lock, weekly auto-backup (Files app → Mindrawer → Backups), and a trash that keeps notes for 30 days.")),
            Step(icon: "cpu",
                 title: L("AI の種類", "Which AI"),
                 body: L("画面右上に今の AI が出ます。\n・Claude: Mindrawer Plus か自分の API キーで使う高性能な AI。スクショの文字も読みます\n・iPhone の AI: Apple Intelligence 対応の iPhone なら無料で使えます。メモは端末の外に出ません\n・簡易整理: AI なしで、キーワードで整理と検索をします",
                         "The top right shows the AI in use.\n• Claude: a top model, via Mindrawer Plus or your own API key. Also reads screenshots\n• On-device AI: free on Apple Intelligence iPhones; notes never leave the phone\n• Basic: keyword filing and search, no AI")),
            Step(icon: "lock.shield",
                 title: L("データ", "Your data"),
                 body: L("メモはこの iPhone の中にだけ保存されます。設定で「iCloud で同期」をオンにすると、同じ Apple ID の iPhone・iPad でそろいます。機種変更のときは「データ」の「書き出す」で保存し、新しい端末で「読み込む」を使ってください。Web 版とも同じファイルでやり取りできます。",
                         "Notes stay on this iPhone. Turn on Sync with iCloud to keep your iPhone and iPad in step. To move them, use Export under Data, then Import on the new device. The same file works with the web version.")),
        ]
    }

    var body: some View {
        List(Self.steps) { s in
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: s.icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.title).font(.headline)
                    Text(s.body).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
        }
        .navigationTitle(L("使い方", "How to use"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
