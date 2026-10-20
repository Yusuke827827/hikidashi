// Mindrawer Plus（月額の購読）。購読中は、API キーなしで AI を使える（中継サーバー server/ を通す）。
// 中継サーバーの URL と商品 ID は Info.plist（project.yml の SERVER_URL・PLUS_PRODUCT_ID）から読む。
// SERVER_URL が空なら購読の機能は出さない（自分の API キーだけで動く）。

#if os(iOS)
import Foundation
import HikidashiKit
import Observation
import StoreKit

@MainActor
@Observable
final class Subscription {
    static let shared = Subscription()

    static var serverURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "MindrawerServerURL") as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    static var productID: String {
        (Bundle.main.object(forInfoDictionaryKey: "MindrawerPlusProductID") as? String) ?? "app.mindrawer.plus.monthly"
    }

    /// 購読の機能を使える設定か
    static var isAvailable: Bool { serverURL != nil }

    private(set) var product: Product?
    /// 有効な購読の証明（App Store が署名したもの）。購読していなければ nil
    private(set) var transactionJWS: String?
    private(set) var expires: Date?
    private(set) var purchasing = false
    var message: String?

    private var started = false

    var isActive: Bool { transactionJWS != nil }

    /// 起動時に一度だけ呼ぶ。商品を読み込み、購読の状態を確かめ、更新を待ち受ける
    func start() async {
        guard Self.isAvailable, !started else { return }
        started = true
        Task { [weak self] in
            for await update in Transaction.updates {
                if case let .verified(t) = update { await t.finish() }
                await self?.refresh()
            }
        }
        product = try? await Product.products(for: [Self.productID]).first
        await refresh()
    }

    func refresh() async {
        for await result in Transaction.currentEntitlements {
            guard case let .verified(t) = result, t.productID == Self.productID, t.revocationDate == nil else { continue }
            if let e = t.expirationDate, e < Date() { continue }
            transactionJWS = result.jwsRepresentation
            expires = t.expirationDate
            return
        }
        transactionJWS = nil
        expires = nil
    }

    func purchase() async {
        guard let product else {
            message = L("App Store に接続できません。少し待ってからお試しください。", "Can't reach the App Store. Try again shortly.")
            return
        }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(verification):
                if case let .verified(t) = verification {
                    await t.finish()
                    message = L("購読しました。AI が使えます。", "Subscribed. AI is on.")
                } else {
                    message = L("購入を確認できませんでした。", "Couldn't verify the purchase.")
                }
            case .pending:
                message = L("承認待ちです。承認されると使えるようになります。", "Waiting for approval.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = L("購入できませんでした。", "The purchase didn't go through.")
        }
        await refresh()
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            message = L("復元できませんでした。", "Couldn't restore purchases.")
        }
        await refresh()
        if isActive { message = L("購読を復元しました。", "Subscription restored.") }
    }

    /// Claude の呼び方。自分の API キーがあればそれを優先し、無ければ購読を使う
    static func credential() -> ClaudeClient.Credential? {
        if let key = Librarian.apiKeyCredential() { return key }
        if let url = serverURL, let jws = shared.transactionJWS { return .subscription(server: url, transaction: jws) }
        return nil
    }
}
#endif
