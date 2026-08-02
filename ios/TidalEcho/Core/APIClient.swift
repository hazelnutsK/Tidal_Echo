import Foundation

struct APIClient {
    let baseURL: URL
    let secret: String

    func history(since: Int, limit: Int = 500) async throws -> [ChatMessage] {
        var components = URLComponents(url: endpoint("app/history"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else { throw APIError.invalidURL }
        let data = try await data(for: request(url: url))
        return try decoder.decode(HistoryResponse.self, from: data).messages
    }

    func send(text: String, attachments: [Attachment]) async throws -> SendResponse {
        var req = request(url: endpoint("app/send"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(SendPayload(text: text, attachments: attachments))
        let responseData = try await data(for: req)
        return try decoder.decode(SendResponse.self, from: responseData)
    }

    func upload(data: Data, name: String, mime: String) async throws -> Attachment {
        var components = URLComponents(url: endpoint("app/upload"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components?.url else { throw APIError.invalidURL }
        var req = request(url: url, method: "POST")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let responseData = try await self.data(for: req)
        return try decoder.decode(Attachment.self, from: responseData)
    }

    func ping() async throws {
        let req = request(url: endpoint("app/ping"), method: "POST")
        _ = try await data(for: req)
    }

    func brain() async throws -> BrainTarget {
        let responseData = try await data(for: request(url: endpoint("app/brain")))
        return try decoder.decode(BrainResponse.self, from: responseData).target
    }

    func setBrain(_ target: BrainTarget) async throws -> BrainTarget {
        var req = request(url: endpoint("app/brain"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(BrainPayload(target: target))
        let responseData = try await data(for: req)
        return try decoder.decode(BrainResponse.self, from: responseData).target
    }

    func loopConfig() async throws -> LoopConfigResponse {
        let responseData = try await data(for: request(url: endpoint("app/loop_config")))
        return try decoder.decode(LoopConfigResponse.self, from: responseData)
    }

    func setLoopModel(_ model: String, chainCount: Int) async throws -> LoopConfigResponse {
        var req = request(url: endpoint("app/loop_config"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let routes = (0..<max(1, chainCount)).map { index in
            LoopRoute(index: index, url: nil, model: index == 0 ? model : nil)
        }
        req.httpBody = try JSONEncoder().encode(LoopConfigPayload(mainChain: routes))
        let responseData = try await data(for: req)
        return try decoder.decode(LoopConfigResponse.self, from: responseData)
    }

    func activateAPIPreset(_ index: Int) async throws -> LoopConfigResponse {
        var req = request(url: endpoint("app/loop_config"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(LoopPresetPayload(activatePreset: index, apiPresets: nil))
        return try decoder.decode(LoopConfigResponse.self, from: try await data(for: req))
    }

    func replaceAPIPresets(_ presets: [APIPresetInput]) async throws -> LoopConfigResponse {
        var req = request(url: endpoint("app/loop_config"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(LoopPresetPayload(activatePreset: nil, apiPresets: presets))
        return try decoder.decode(LoopConfigResponse.self, from: try await data(for: req))
    }

    func chatMode() async throws -> ChatMode {
        let responseData = try await data(for: request(url: endpoint("app/chat_mode")))
        return try decoder.decode(ChatModeResponse.self, from: responseData).mode
    }

    func setChatMode(_ mode: ChatMode) async throws -> ChatMode {
        var req = request(url: endpoint("app/chat_mode"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ChatModePayload(mode: mode))
        return try decoder.decode(ChatModeResponse.self, from: try await data(for: req)).mode
    }

    func quota() async throws -> QuotaResponse {
        try decoder.decode(QuotaResponse.self, from: try await data(for: request(url: endpoint("app/quota"))))
    }

    func loopStats() async throws -> APIUsageStats {
        try decoder.decode(APIUsageStats.self, from: try await data(for: request(url: endpoint("app/loop_stats"))))
    }

    func desktopModel() async throws -> DesktopModelResponse {
        let responseData = try await data(for: request(url: endpoint("app/desktop_model")))
        return try decoder.decode(DesktopModelResponse.self, from: responseData)
    }

    func setDesktopModel(_ model: String) async throws -> DesktopModelResponse {
        var req = request(url: endpoint("app/desktop_model"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(DesktopModelPayload(model: model))
        let responseData = try await data(for: req)
        return try decoder.decode(DesktopModelResponse.self, from: responseData)
    }

    func contextStatus() async throws -> ContextStatus {
        let responseData = try await data(for: request(url: endpoint("app/context_status")))
        return try decoder.decode(ContextStatus.self, from: responseData)
    }

    func updateContextThreshold(triggerK: Int? = nil, auto: Bool? = nil) async throws -> ContextThresholdResponse {
        var req = request(url: endpoint("app/context_threshold"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ContextThresholdPayload(triggerK: triggerK, auto: auto))
        let responseData = try await data(for: req)
        return try decoder.decode(ContextThresholdResponse.self, from: responseData)
    }

    func performContextAction(_ action: String, sid: String? = nil) async throws -> ContextActionResponse {
        var req = request(url: endpoint("app/context_action"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ContextActionPayload(action: action, sid: sid))
        let responseData = try await data(for: req)
        return try decoder.decode(ContextActionResponse.self, from: responseData)
    }

    func streamRequest() -> URLRequest {
        var req = request(url: endpoint("app/stream"))
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // Avoid an intermediary compressing and buffering the event stream.
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        req.timeoutInterval = 60 * 60
        return req
    }

    func attachmentRequest(path: String) -> URLRequest? {
        let url: URL?
        if let absolute = URL(string: path), absolute.scheme != nil {
            url = absolute
        } else {
            url = URL(string: path, relativeTo: baseURL)?.absoluteURL
        }
        guard let url else { return nil }
        return request(url: url)
    }

    private var decoder: JSONDecoder { JSONDecoder() }

    private func endpoint(_ path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    private func request(url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.setValue("TidalEcho-iOS/0.1", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data).detail) ?? "HTTP \(http.statusCode)"
            throw APIError.server(detail)
        }
        return data
    }
}

private struct SendPayload: Encodable {
    let text: String
    let attachments: [Attachment]
}

private struct BrainPayload: Encodable { let target: BrainTarget }

private struct LoopConfigPayload: Encodable {
    let mainChain: [LoopRoute]
    enum CodingKeys: String, CodingKey { case mainChain = "main_chain" }
}

private struct LoopPresetPayload: Encodable {
    let activatePreset: Int?
    let apiPresets: [APIPresetInput]?
    enum CodingKeys: String, CodingKey {
        case activatePreset = "activate_preset"
        case apiPresets = "api_presets"
    }
}

private struct ChatModePayload: Encodable { let mode: ChatMode }

private struct DesktopModelPayload: Encodable { let model: String }

private struct ContextThresholdPayload: Encodable {
    let triggerK: Int?
    let auto: Bool?
    enum CodingKeys: String, CodingKey {
        case auto
        case triggerK = "trigger_k"
    }
}

private struct ContextActionPayload: Encodable {
    let action: String
    let sid: String?
}

private struct ErrorResponse: Decodable {
    let detail: String
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "服务地址不正确"
        case .invalidResponse: return "服务器返回了无法识别的响应"
        case .unauthorized: return "连接密钥不正确"
        case .server(let detail): return detail
        }
    }
}
