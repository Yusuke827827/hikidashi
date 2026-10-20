// 画面写真用の見本モード。起動引数で切り替える（scripts/screenshots.sh から使う）。
//   -HikidashiDemo                 一時フォルダに見本のメモを入れて起動する（本物のメモには触れない）
//   -HikidashiDemoRecall <問い>     起動後に「ひきだす」を実行した状態にする（キーワード検索）
//   -HikidashiDemoSettings         起動後に設定画面を開く
//   -wallpaper <名前>              壁紙（UserDefaults の引数として渡る）

#if os(iOS)
import Foundation
import HikidashiKit

enum DemoMode {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isOn: Bool { arguments.contains("-HikidashiDemo") }
    static var opensSettings: Bool { arguments.contains("-HikidashiDemoSettings") }

    static var recallQuery: String? {
        guard let i = arguments.firstIndex(of: "-HikidashiDemoRecall"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    /// 見本モードの「ひきだす」で見せる、Claude の答えの見本（見本モードは API キーなしで動くため）
    static var recallAnswer: String {
        // 見本のポイントのメモのリマインド日（3 日後）に合わせる
        let c = Calendar.current.dateComponents([.month, .day], from: Date().addingTimeInterval(3 * 86400))
        let due = "\(c.month ?? 1)/\(c.day ?? 1)"
        return L("荷造りは、着る順に服を 1 日ずつ袋に分けておくと、朝に迷わずに済みます。出張の準備でも同じやり方が使えます。旅先でポイントを使う予定があれば、期限が \(due) なので先に使い切っておきましょう。",
                 "Pack one bag per day, in the order you'll wear things, so mornings are quick. It works for business trips too. Your reward points expire on \(due), so spend them before you go.")
    }

    @MainActor
    static func makeLibrarian() -> Librarian {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HikidashiDemo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let librarian = Librarian(store: NoteStore(root: root), credentialProvider: { nil })
        librarian.addExamples()
        for note in extraNotes() { librarian.store.add(note) }
        return librarian
    }

    static func extraNotes() -> [Note] {
        let day: TimeInterval = 86400
        let soon = Heuristics.dayFormatter.string(from: Date().addingTimeInterval(3 * day))
        if AppLanguage.current == .ja {
            return [
                Note(text: "楽天ポイントの期間限定分は月末で失効する。25日ごろにまとめて使う。", title: "期間限定ポイントは月末に失効", summary: "25日ごろに残高を確認して使い切る。",
                     category: "お金・節約", tags: ["ポイント"], situations: ["買い物の前", "月末"], remindAt: soon, createdAt: Date().addingTimeInterval(-2 * 3600), pinned: true, helpful: 3, filed: true),
                Note(text: "プレゼン前は、最初の 30 秒の台詞だけ丸暗記しておくと落ち着く。", title: "最初の 30 秒だけ暗記する", summary: "出だしが決まれば緊張がほどける。",
                     category: "仕事・勉強", tags: ["プレゼン", "緊張"], situations: ["プレゼン前", "面接の前"], createdAt: Date().addingTimeInterval(-26 * 3600), helpful: 1, filed: true),
                Note(text: "旅行の荷造りは、着る順に服を 1 日ずつ袋に分けると現地で迷わない。", title: "服は 1 日ずつ袋に分ける", summary: "着る順に分ければ朝に迷わない。",
                     category: "おでかけ・旅行", tags: ["荷造り"], situations: ["旅行の荷造り", "出張の準備"], createdAt: Date().addingTimeInterval(-5 * day), filed: true),
                Note(text: "共有シートから届いたばかりのメモ（まだ整理されていない）", title: "共有シートから届いたばかりのメモ", category: "その他",
                     createdAt: Date().addingTimeInterval(-60), filed: false),
            ]
        }
        return [
            Note(text: "Limited-time reward points expire at the end of the month. Spend them around the 25th.", title: "Reward points expire at month end", summary: "Check the balance around the 25th and use them up.",
                 category: "Money", tags: ["points"], situations: ["Before shopping", "End of month"], remindAt: soon, createdAt: Date().addingTimeInterval(-2 * 3600), pinned: true, helpful: 3, filed: true),
            Note(text: "Before a talk, memorize only your first 30 seconds word for word. The rest follows.", title: "Memorize only the first 30 seconds", summary: "A sure opening takes the edge off the nerves.",
                 category: "Work & Study", tags: ["presenting", "nerves"], situations: ["Before a presentation", "Before an interview"], createdAt: Date().addingTimeInterval(-26 * 3600), helpful: 1, filed: true),
            Note(text: "Pack one bag per day, in the order you'll wear things. No digging through the suitcase.", title: "Pack outfits one bag per day", summary: "Grab a bag each morning and go.",
                 category: "Travel", tags: ["packing"], situations: ["Packing for a trip", "Business travel"], createdAt: Date().addingTimeInterval(-5 * day), filed: true),
            Note(text: "Just arrived from the share sheet (not filed yet)", title: "Just arrived from the share sheet", category: "Other",
                 createdAt: Date().addingTimeInterval(-60), filed: false),
        ]
    }
}
#endif
