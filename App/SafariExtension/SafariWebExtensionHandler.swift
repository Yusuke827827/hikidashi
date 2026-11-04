// iPhone・iPad の Safari の拡張機能。ページで選んだ文やページを、アプリの受け取り箱（App Group）に置く。
// 次にアプリを開いたときに、ほかの共有と同じく整理してしまう。

import Foundation
import HikidashiKit
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        var reply: [String: Any] = ["ok": false]
        let text = (message["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let url = (message["url"] as? String).flatMap { $0.hasPrefix("http") ? $0 : nil }
        let title = (message["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty || url != nil {
            // 選んだ文が無ければ、ページの題名をメモにする（本文はアプリがリンク先から読む）
            let body = text.isEmpty ? title : text
            if (try? Inbox.put(text: body, url: url, comment: "", image: nil)) != nil { reply["ok"] = true }
        }
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
