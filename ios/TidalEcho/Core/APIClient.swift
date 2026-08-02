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

    func streamRequest() -> URLRequest {
        var req = request(url: endpoint("app/stream"))
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
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
