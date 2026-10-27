// iPhone の検索（Spotlight）にメモを載せる。検索結果を押すとそのメモを開く。
// あわせて、ウィジェットや Siri からアプリを開いたときの行き先（AppRouter）もここに置く。

#if os(iOS)
import CoreSpotlight
import Foundation
import HikidashiKit
import UniformTypeIdentifiers
import WidgetKit

@MainActor
enum Spotlight {
    static let domain = "notes"

    /// 載せ直す（メモが変わるたび）
    static func index(_ notes: [Note]) {
        let items = notes.filter { !$0.example }.prefix(500).map { n -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = n.title
            a.contentDescription = n.summary.isEmpty ? String(n.text.prefix(200)) : n.summary
            a.keywords = n.tags + n.situations + [n.category]
            return CSSearchableItem(uniqueIdentifier: n.id, domainIdentifier: domain, attributeSet: a)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(Array(items)) { _ in }
        }
    }

    /// 検索結果から開いたメモの id
    static func noteID(from activity: NSUserActivity) -> String? {
        activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    }
}

/// ウィジェット・Siri・ショートカット・Spotlight からアプリを開いたときの行き先
public enum AppRouter {
    /// 「ひきだす」を、この問いで行う
    @MainActor public static func recall(_ query: String) {
        NotificationRouter.shared.recallQuery = query
    }

    /// このメモを開く
    @MainActor public static func open(noteID: String) {
        NotificationRouter.shared.openNoteID = noteID
    }

    /// mindrawer://note/<id> と mindrawer://recall?q=<問い>
    @MainActor public static func handle(_ url: URL) {
        guard url.scheme == "mindrawer" else { return }
        switch url.host {
        case "note":
            let id = url.lastPathComponent
            if !id.isEmpty, id != "/" { open(noteID: id) }
        case "recall":
            if let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value, !q.isEmpty {
                recall(q)
            }
        default:
            break
        }
    }

    /// ウィジェットを描き直す
    @MainActor static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
