import Foundation

struct APIClient {
    let baseURL: URL
    let secret: String

    func history(since: Int, limit: Int = 500, sessionID: String? = nil) async throws -> [ChatMessage] {
        var components = URLComponents(url: endpoint("app/history"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let sessionID, !sessionID.isEmpty {
            queryItems.append(URLQueryItem(name: "session_id", value: sessionID))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw APIError.invalidURL }
        let data = try await data(for: request(url: url))
        return try decoder.decode(HistoryResponse.self, from: data).messages
    }

    func send(text: String, attachments: [Attachment], sessionID: String? = nil) async throws -> SendResponse {
        var req = request(url: endpoint("app/send"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(SendPayload(text: text, attachments: attachments, apiSession: sessionID))
        let responseData = try await data(for: req)
        return try decoder.decode(SendResponse.self, from: responseData)
    }

    func search(_ query: String, limit: Int = 80) async throws -> [ChatMessage] {
        var components = URLComponents(url: endpoint("app/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else { throw APIError.invalidURL }
        return try decoder.decode(SearchResponse.self, from: try await data(for: request(url: url))).results
    }

    func sessions() async throws -> SessionsResponse {
        try decoder.decode(SessionsResponse.self, from: try await data(for: request(url: endpoint("app/sessions"))))
    }

    func createSession(title: String) async throws -> SessionsResponse {
        var req = request(url: endpoint("app/sessions"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(SessionCreatePayload(title: title, activate: true))
        return try decoder.decode(SessionsResponse.self, from: try await data(for: req))
    }

    func updateSession(id: String, title: String? = nil, active: Bool? = nil) async throws -> SessionsResponse {
        var req = request(url: endpoint("app/sessions/\(id)"), method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(SessionUpdatePayload(title: title, active: active))
        return try decoder.decode(SessionsResponse.self, from: try await data(for: req))
    }

    func deleteSession(id: String) async throws -> SessionsResponse {
        try decoder.decode(
            SessionsResponse.self,
            from: try await data(for: request(url: endpoint("app/sessions/\(id)"), method: "DELETE"))
        )
    }

    func editMessage(id: Int, text: String) async throws -> ChatMessage {
        var req = request(url: endpoint("app/message/\(id)/edit"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(MessageEditPayload(text: text))
        return try decoder.decode(ChatMessage.self, from: try await data(for: req))
    }

    func regenerateMessage(id: Int) async throws {
        _ = try await data(for: request(url: endpoint("app/message/\(id)/regen"), method: "POST"))
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

    func sendVoiceAudio(data: Data, name: String, mime: String, callID: String? = nil) async throws -> VoiceResponse {
        var components = URLComponents(url: endpoint("app/voice"), resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "name", value: name)]
        if let callID, !callID.isEmpty { query.append(URLQueryItem(name: "call_id", value: callID)) }
        components?.queryItems = query
        guard let url = components?.url else { throw APIError.invalidURL }
        var req = request(url: url, method: "POST")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        return try decoder.decode(VoiceResponse.self, from: try await self.data(for: req))
    }

    func sendVoiceText(_ text: String, source: String = "ios_speech", callID: String? = nil) async throws -> VoiceResponse {
        var req = request(url: endpoint("app/voice"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(VoiceTextPayload(text: text, source: source, callID: callID))
        return try decoder.decode(VoiceResponse.self, from: try await data(for: req))
    }

    func callEvent(_ action: String, callID: String) async throws -> SendResponse {
        var req = request(url: endpoint("app/call"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(CallPayload(action: action, callID: callID))
        return try decoder.decode(SendResponse.self, from: try await data(for: req))
    }

    func tts(text: String, messageID: Int? = nil, persist: Bool = false) async throws -> Data {
        var req = request(url: endpoint("app/tts"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(TTSPayload(text: text, messageID: messageID, persist: persist))
        return try await data(for: req)
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

    func stars() async throws -> [ChatMessage] {
        let responseData = try await data(for: request(url: endpoint("app/stars")))
        return try decoder.decode(StarsResponse.self, from: responseData).stars
    }

    func setStar(messageID: Int, on: Bool) async throws -> String? {
        var req = request(url: endpoint("app/star/\(messageID)"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(StarPayload(on: on))
        return try decoder.decode(StarResponse.self, from: try await data(for: req)).starred
    }

    func album() async throws -> [AlbumPhoto] {
        let responseData = try await data(for: request(url: endpoint("app/album")))
        return try decoder.decode(AlbumResponse.self, from: responseData).photos
    }

    func giftPages() async throws -> [GiftPage] {
        let responseData = try await data(for: request(url: endpoint("app/pages")))
        return try decoder.decode(GiftPagesResponse.self, from: responseData).pages
    }

    func giftPageURL(file: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/chat/pages/\(file)"
        components.query = nil
        return components.url
    }

    func moments(kind: MomentKind, before: Int? = nil, limit: Int = 20) async throws -> MomentsResponse {
        var components = URLComponents(url: endpoint("app/posts"), resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let before { items.append(URLQueryItem(name: "before", value: String(before))) }
        components?.queryItems = items
        guard let url = components?.url else { throw APIError.invalidURL }
        return try decoder.decode(MomentsResponse.self, from: try await data(for: request(url: url)))
    }

    func createMoment(kind: MomentKind, text: String, attachments: [Attachment]) async throws -> MomentPost {
        var req = request(url: endpoint("app/posts"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(MomentCreatePayload(author: .human, kind: kind, text: text, attachments: attachments))
        return try decoder.decode(MomentPostResponse.self, from: try await data(for: req)).post
    }

    func likeMoment(id: Int, on: Bool) async throws -> [String: String] {
        var req = request(url: endpoint("app/posts/\(id)/like"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(MomentLikePayload(author: .human, on: on))
        return try decoder.decode(MomentLikeResponse.self, from: try await data(for: req)).likes
    }

    func commentMoment(id: Int, text: String, replyTo: MessageAuthor? = nil) async throws -> MomentComment {
        var req = request(url: endpoint("app/posts/\(id)/comment"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(MomentCommentPayload(author: .human, text: text, replyTo: replyTo))
        return try decoder.decode(MomentCommentResponse.self, from: try await data(for: req)).comment
    }

    func deleteMoment(id: Int) async throws {
        var components = URLComponents(url: endpoint("app/posts/\(id)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "author", value: "human")]
        guard let url = components?.url else { throw APIError.invalidURL }
        _ = try await data(for: request(url: url, method: "DELETE"))
    }

    func calendar(year: Int, month: Int) async throws -> CalendarMonthResponse {
        var components = URLComponents(url: endpoint("app/calendar"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "year", value: String(year)),
            URLQueryItem(name: "month", value: String(month))
        ]
        guard let url = components?.url else { throw APIError.invalidURL }
        return try decoder.decode(CalendarMonthResponse.self, from: try await data(for: request(url: url)))
    }

    func createCalendarEvent(_ payload: CalendarCreatePayload) async throws -> CalendarEvent {
        var req = request(url: endpoint("app/calendar"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)
        return try decoder.decode(CalendarEvent.self, from: try await data(for: req))
    }

    func deleteCalendarEvent(id: Int) async throws {
        _ = try await data(for: request(url: endpoint("app/calendar/\(id)"), method: "DELETE"))
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
    let apiSession: String?

    enum CodingKeys: String, CodingKey {
        case text, attachments
        case apiSession = "api_session"
    }
}

private struct SessionCreatePayload: Encodable {
    let title: String
    let activate: Bool
}

private struct SessionUpdatePayload: Encodable {
    let title: String?
    let active: Bool?
}

private struct MessageEditPayload: Encodable { let text: String }

private struct VoiceTextPayload: Encodable {
    let text: String
    let source: String
    let callID: String?

    enum CodingKeys: String, CodingKey {
        case text, source
        case callID = "call_id"
    }
}

private struct CallPayload: Encodable {
    let action: String
    let callID: String

    enum CodingKeys: String, CodingKey {
        case action
        case callID = "call_id"
    }
}

private struct TTSPayload: Encodable {
    let text: String
    let messageID: Int?
    let persist: Bool

    enum CodingKeys: String, CodingKey {
        case text, persist
        case messageID = "message_id"
    }
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

private struct StarPayload: Encodable { let on: Bool }

private struct MomentCreatePayload: Encodable {
    let author: MessageAuthor
    let kind: MomentKind
    let text: String
    let attachments: [Attachment]
}

private struct MomentLikePayload: Encodable {
    let author: MessageAuthor
    let on: Bool
}

private struct MomentCommentPayload: Encodable {
    let author: MessageAuthor
    let text: String
    let replyTo: MessageAuthor?
    enum CodingKeys: String, CodingKey {
        case author, text
        case replyTo = "reply_to"
    }
}

struct CalendarCreatePayload: Encodable {
    let date: String
    let time: String
    let title: String
    let kind: String
    let visible: Bool
    let remind: Bool
}

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
