// Claude API（Messages API）を利用者自身の API キーで直接呼ぶ。Swift の公式 SDK は無いため HTTP で送る。
//   - 返事は output_config.format の JSON スキーマで形を決め、そのまま Decodable で読む
//   - 安全のための判定で断られたときは、サーバー側で別のモデルに回す（fallbacks: "default"）
//   - 画像は base64 で本文と一緒に送る（スクショからの読み取り）

import Foundation

public enum ClaudeError: Error, Equatable, LocalizedError {
    case noKey
    case invalidKey
    case subscriptionInvalid
    case monthlyLimit
    case busy
    case refused
    case truncated
    case http(Int, String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .noKey: return L("API キーが設定されていません。", "No API key is set.")
        case .invalidKey: return L("API キーが正しくないようです。設定を確認してください。", "The API key was rejected. Check it in Settings.")
        case .subscriptionInvalid: return L("購読を確認できませんでした。設定の「購入を復元」をお試しください。", "Couldn't confirm your subscription. Try Restore Purchases in Settings.")
        case .monthlyLimit: return L("今月の AI の利用回数の上限に達しました。来月にまた使えます。", "You've reached this month's AI limit. It resets next month.")
        case .busy: return L("Claude が混み合っています。少し待ってからもう一度お試しください。", "Claude is busy. Try again in a moment.")
        case .refused: return L("このメモは整理できませんでした。", "Claude declined to process this note.")
        case .truncated: return L("返事が途中で切れました。もう一度お試しください。", "The reply was cut off. Try again.")
        case let .http(code, message): return "HTTP \(code): \(message)"
        case .badResponse: return L("返事を読み取れませんでした。", "Couldn't read the reply.")
        }
    }
}

public struct ClaudeClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let defaultModel = "claude-opus-5-5"

    public enum Effort: String, Sendable { case low, medium, high }

    public struct Image: Sendable {
        public var data: Data
        public var mediaType: String
        public init(data: Data, mediaType: String = "image/jpeg") {
            self.data = data
            self.mediaType = mediaType
        }
    }

    /// 呼び方。自分の API キーで直接呼ぶか、購読者として中継サーバー（server/）を通すか
    public enum Credential: Sendable, Equatable {
        case apiKey(String)
        /// server: 中継サーバーの URL。transaction: App Store の購読の証明（signed transaction）
        case subscription(server: URL, transaction: String)
    }

    public var credential: Credential
    public var model: String

    public init(credential: Credential, model: String = ClaudeClient.defaultModel) {
        self.credential = credential
        self.model = model
    }

    public init(apiKey: String, model: String = ClaudeClient.defaultModel) {
        self.init(credential: .apiKey(apiKey), model: model)
    }

    var isSubscription: Bool {
        if case .subscription = credential { return true }
        return false
    }

    /// 送る内容を組み立てる（通信はしない。テストで中身を確かめられるよう分けている）
    public func request(prompt: String, schema: [String: Any], images: [Image] = [], effort: Effort, maxTokens: Int) throws -> URLRequest {
        var content: [[String: Any]] = images.map { img -> [String: Any] in
            ["type": "image", "source": ["type": "base64", "media_type": img.mediaType, "data": img.data.base64EncodedString()]]
        }
        content.append(["type": "text", "text": prompt])
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "fallbacks": "default",
            "output_config": [
                "effort": effort.rawValue,
                "format": ["type": "json_schema", "schema": schema],
            ],
            "messages": [["role": "user", "content": content]],
        ]
        var req: URLRequest
        switch credential {
        case let .apiKey(key):
            req = URLRequest(url: Self.endpoint)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
        case let .subscription(server, transaction):
            req = URLRequest(url: server.appendingPathComponent("v1/messages"))
            req.setValue(transaction, forHTTPHeaderField: "x-mindrawer-transaction")
        }
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 返ってきた内容を読む
    public static func parse<T: Decodable>(_ type: T.Type, data: Data, status: Int, subscription: Bool = false) throws -> T {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            let message = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? ""
            switch status {
            case 401, 403: throw subscription ? ClaudeError.subscriptionInvalid : ClaudeError.invalidKey
            case 429 where subscription && message.contains("Monthly limit"): throw ClaudeError.monthlyLimit
            case 429, 529: throw ClaudeError.busy
            default: throw ClaudeError.http(status, message)
            }
        }
        guard let obj else { throw ClaudeError.badResponse }
        switch obj["stop_reason"] as? String {
        case "refusal": throw ClaudeError.refused
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let json = text.data(using: .utf8)
        else { throw ClaudeError.badResponse }
        do {
            return try JSONDecoder().decode(T.self, from: json)
        } catch {
            throw ClaudeError.badResponse
        }
    }

    public func json<T: Decodable>(_ type: T.Type, prompt: String, schema: [String: Any], images: [Image] = [], effort: Effort, maxTokens: Int = 8000) async throws -> T {
        if case let .apiKey(key) = credential, key.isEmpty { throw ClaudeError.noKey }
        let req = try request(prompt: prompt, schema: schema, images: images, effort: effort, maxTokens: maxTokens)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parse(T.self, data: data, status: status, subscription: isSubscription)
    }
}
