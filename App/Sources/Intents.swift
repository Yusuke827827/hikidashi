// Siri とショートカット。「Hey Siri、Mindrawer でひきだす」「Mindrawer にしまう」。

import AppIntents
import HikidashiKit
import HikidashiUI

struct SaveTipIntent: AppIntent {
    static let title: LocalizedStringResource = "Mindrawer にしまう"
    static let description = IntentDescription("Tips やメモを Mindrawer にしまいます。次にアプリを開いたときに整理します。")

    @Parameter(title: "しまう内容")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try Inbox.put(text: text, url: nil, comment: "", image: nil)
        return .result(dialog: "しまいました。")
    }
}

struct RecallIntent: AppIntent {
    static let title: LocalizedStringResource = "Mindrawer でひきだす"
    static let description = IntentDescription("これからすることや困りごとから、役立つメモを取り出します。")
    static let openAppWhenRun = true

    @Parameter(title: "これからすること・質問")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.recall(query)
        return .result()
    }
}

struct MindrawerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecallIntent(),
                    phrases: ["\(.applicationName)でひきだす", "\(.applicationName)で探す", "Recall in \(.applicationName)"],
                    shortTitle: "ひきだす",
                    systemImageName: "magnifyingglass")
        AppShortcut(intent: SaveTipIntent(),
                    phrases: ["\(.applicationName)にしまう", "Save to \(.applicationName)"],
                    shortTitle: "しまう",
                    systemImageName: "square.and.arrow.down")
    }
}
