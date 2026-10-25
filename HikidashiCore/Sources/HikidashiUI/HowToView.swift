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
                 body: L("上の欄に Tips やメモを書いて「しまう」を押します。出典の URL やスクショも付けられます。声で入れたいときは、キーボードのマイクを押してください。",
                         "Type a tip or note in the box at the top and tap Save. You can add a source link or a screenshot. To dictate, tap the mic on the keyboard.")),
            Step(icon: "square.and.arrow.up",
                 title: L("共有シートから保存", "Save from the share sheet"),
                 body: L("X・Safari・写真などで共有ボタンを押し、「Mindrawer」を選びます。ひとこと書き足すこともできます。出てこないときは、アプリの列の右端「その他」から追加してください。",
                         "In X, Safari, Photos and more, tap Share and pick Mindrawer. You can add a short note. If it isn't listed, add it from More at the end of the app row.")),
            Step(icon: "sparkles",
                 title: L("AI が整理", "AI files it"),
                 body: L("しまったメモに、タイトル・要約・フォルダ・タグ・「役立つ場面」を AI が付けます。本文に日付があれば、その日の朝 9 時に通知します。",
                         "AI adds a title, summary, folder, tags and the moments it will help. If the note mentions a date, you get a reminder at 9 AM that day.")),
            Step(icon: "magnifyingglass",
                 title: L("ひきだす", "Recall"),
                 body: L("「ひきだす」に切り替えて、これからすることや困りごとを書きます。例:「これから洗濯する」「プレゼン前で緊張する」「節約になるやつ」。言葉が一致していなくても、役立つメモと短い助言が出ます。",
                         "Switch to Recall and describe what you're about to do or what's bothering you, e.g. \"About to do laundry\" or \"Nervous before a talk\". You get the notes that help, plus short advice, even without matching words.")),
            Step(icon: "sun.max",
                 title: L("今日のひとつ", "Today's pick"),
                 body: L("しまったままのメモを毎日 1 件見せます。「役立った」を押したメモは、取り出しで優先されます。",
                         "One stored note resurfaces each day. Notes you mark Helpful come first when you recall.")),
            Step(icon: "ellipsis.circle",
                 title: L("メモの操作", "Working with notes"),
                 body: L("メモの「…」から、編集・AI で再整理・出典の共有・削除ができます。ピン留めしたメモは上に出ます。一覧は「分類」と「日付」で切り替えられます。",
                         "Use … on a note to edit, re-file with AI, share the source or delete. Pinned notes stay on top. Switch the list between Topic and Date.")),
            Step(icon: "cpu",
                 title: L("AI の種類", "Which AI"),
                 body: L("画面右上に今の AI が出ます。\n・Claude: Mindrawer Plus か自分の API キーで使う高性能な AI。スクショの文字も読みます\n・iPhone の AI: Apple Intelligence 対応の iPhone なら無料で使えます。メモは端末の外に出ません\n・簡易整理: AI なしで、キーワードで整理と検索をします",
                         "The top right shows the AI in use.\n• Claude: a top model, via Mindrawer Plus or your own API key. Also reads screenshots\n• On-device AI: free on Apple Intelligence iPhones; notes never leave the phone\n• Basic: keyword filing and search, no AI")),
            Step(icon: "lock.shield",
                 title: L("データ", "Your data"),
                 body: L("メモはこの iPhone の中にだけ保存されます。機種変更のときは「データ」の「書き出す」で保存し、新しい端末で「読み込む」を使ってください。Web 版とも同じファイルでやり取りできます。",
                         "Notes stay on this iPhone. To move them, use Export under Data, then Import on the new device. The same file works with the web version.")),
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
