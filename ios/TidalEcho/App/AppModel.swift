import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case signedOut
        case connecting
        case connected
    }

    @Published var phase: Phase = .signedOut
    @Published var messages: [ChatMessage] = []
    @Published var draftText = ""
    @Published var pendingAttachments: [Attachment] = []
    @Published var isTyping = false
    @Published var streamingThinking = ""
    @Published var streamingReply = ""
    @Published var isStreamConnected = false
    @Published var isLoadingHistory = false
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var theme: EchoTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    private var client: APIClient?
    private let stream = SSEClient()
    private var heartbeatTask: Task<Void, Never>?
    private var temporaryID = -1
    private var didBootstrap = false

    private enum Keys {
        static let relayURL = "tidalEcho.relayURL"
        static let relaySecret = "relaySecret"
        static let theme = "tidalEcho.theme"
    }

    init() {
        let rawTheme = UserDefaults.standard.string(forKey: Keys.theme) ?? EchoTheme.mist.rawValue
        theme = EchoTheme(rawValue: rawTheme) ?? .mist
    }

    var savedServerAddress: String {
        UserDefaults.standard.string(forKey: Keys.relayURL) ?? ""
    }

    var connectionText: String {
        if isTyping { return "小克正在输入…" }
        return isStreamConnected ? "online" : "connecting…"
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        guard let secret = KeychainStore.read(account: Keys.relaySecret),
              !secret.isEmpty,
              let url = try? Self.normalizedRelayURL(savedServerAddress) else {
            phase = .signedOut
            return
        }
        await connect(url: url, secret: secret, persist: false)
    }

    func login(serverAddress: String, secret: String) async {
        do {
            let url = try Self.normalizedRelayURL(serverAddress)
            let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSecret.isEmpty else { throw APIError.unauthorized }
            await connect(url: url, secret: trimmedSecret, persist: true)
        } catch {
            phase = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        stream.stop()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        client = nil
        messages = []
        pendingAttachments = []
        streamingThinking = ""
        streamingReply = ""
        isStreamConnected = false
        KeychainStore.delete(account: Keys.relaySecret)
        phase = .signedOut
    }

    func refresh() async {
        guard client != nil else { return }
        await loadHistory()
    }

    func sendCurrentMessage() async {
        guard let client else { return }
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }

        temporaryID -= 1
        let tempID = temporaryID
        let optimistic = ChatMessage(
            id: tempID,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            author: .human,
            kind: "user",
            text: text,
            meta: MessageMeta(attachments: attachments),
            delivery: .sending
        )
        messages.append(optimistic)
        draftText = ""
        pendingAttachments = []

        do {
            let response = try await client.send(text: text, attachments: attachments)
            if let realIndex = messages.firstIndex(where: { $0.id == response.id }) {
                messages[realIndex].delivery = .sent
                messages.removeAll { $0.id == tempID }
            } else if let tempIndex = messages.firstIndex(where: { $0.id == tempID }) {
                messages[tempIndex].id = response.id
                messages[tempIndex].delivery = .sent
            }
        } catch {
            if let index = messages.firstIndex(where: { $0.id == tempID }) {
                messages[index].delivery = .failed
            }
            errorMessage = "发送失败：\(error.localizedDescription)"
        }
    }

    func uploadImage(data: Data, name: String, mime: String) async {
        guard let client else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            pendingAttachments.append(try await client.upload(data: data, name: name, mime: mime))
        } catch {
            errorMessage = "图片上传失败：\(error.localizedDescription)"
        }
    }

    func removePendingAttachment(_ attachment: Attachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func attachmentRequest(for attachment: Attachment) -> URLRequest? {
        client?.attachmentRequest(path: attachment.url)
    }

    static func normalizedRelayURL(_ raw: String) throws -> URL {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw APIError.invalidURL }
        if !value.contains("://") { value = "https://" + value }
        while value.hasSuffix("/") { value.removeLast() }
        guard var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host != nil else { throw APIError.invalidURL }
        components.query = nil
        components.fragment = nil
        if components.path.isEmpty { components.path = "/relay" }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func connect(url: URL, secret: String, persist: Bool) async {
        phase = .connecting
        errorMessage = nil
        let nextClient = APIClient(baseURL: url, secret: secret)
        do {
            _ = try await nextClient.history(since: 0, limit: 1)
            client = nextClient
            if persist {
                UserDefaults.standard.set(url.absoluteString, forKey: Keys.relayURL)
                try KeychainStore.save(secret, account: Keys.relaySecret)
            }
            phase = .connected
            await loadHistory()
            startStream(using: nextClient)
            await waitForStreamConnection()
            await catchUp(using: nextClient)
            startHeartbeat()
        } catch {
            client = nil
            phase = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    private func loadHistory() async {
        guard let client else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            var cursor = 0
            var recent: [ChatMessage] = []
            for _ in 0..<200 {
                let batch = try await client.history(since: cursor, limit: 500)
                guard !batch.isEmpty else { break }
                recent.append(contentsOf: batch.filter { !$0.meta.hidden })
                if recent.count > 900 { recent.removeFirst(recent.count - 900) }
                guard let last = batch.last else { break }
                cursor = max(cursor, last.id)
                if batch.count < 500 { break }
            }
            messages = recent.sorted(by: Self.messageComesBefore)
        } catch {
            errorMessage = "聊天记录加载失败：\(error.localizedDescription)"
        }
    }

    private func startStream(using client: APIClient) {
        stream.start(
            request: client.streamRequest(),
            onEvent: { [weak self] data in
                await self?.receiveStreamEvent(data)
            },
            onConnection: { [weak self] connected in
                await self?.setStreamConnection(connected)
            }
        )
    }

    private func waitForStreamConnection() async {
        for _ in 0..<25 {
            if isStreamConnected { return }
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
        }
    }

    private func catchUp(using client: APIClient) async {
        var cursor = messages.map(\.id).filter { $0 > 0 }.max() ?? 0
        do {
            for _ in 0..<20 {
                let batch = try await client.history(since: cursor, limit: 500)
                guard !batch.isEmpty else { break }
                batch.filter { !$0.meta.hidden }.forEach(upsert)
                guard let last = batch.last else { break }
                cursor = max(cursor, last.id)
                if batch.count < 500 { break }
            }
        } catch {
            // SSE is already active; a transient catch-up failure can recover on refresh.
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let client = self.client { try? await client.ping() }
                do {
                    try await Task.sleep(nanoseconds: 25_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func setStreamConnection(_ connected: Bool) {
        isStreamConnected = connected
    }

    private func receiveStreamEvent(_ data: Data) {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(StreamEnvelope.self, from: data),
           let type = envelope.type {
            switch type {
            case "typing":
                isTyping = envelope.active ?? false
                return
            case "reaction":
                if let id = envelope.id,
                   let index = messages.firstIndex(where: { $0.id == id }) {
                    messages[index].meta.reactions = envelope.reactions ?? [:]
                }
                return
            case "thinking_delta":
                streamingThinking += envelope.text ?? ""
                return
            case "reply_delta":
                streamingReply += envelope.text ?? ""
                isTyping = true
                return
            default:
                break
            }
        }

        guard let message = try? decoder.decode(ChatMessage.self, from: data),
              !message.meta.hidden else { return }
        upsert(message)
        if message.author == .ai {
            if message.kind == "thinking" { streamingThinking = "" }
            if message.kind == "reply" {
                streamingReply = ""
                isTyping = false
            }
        }
    }

    private func upsert(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
            messages.sort(by: Self.messageComesBefore)
        }
    }

    private static func messageComesBefore(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        if lhs.id < 0 { return false }
        if rhs.id < 0 { return true }
        let leftAnchor = lhs.meta.sortAfter ?? lhs.id
        let rightAnchor = rhs.meta.sortAfter ?? rhs.id
        if leftAnchor == rightAnchor { return lhs.id < rhs.id }
        return leftAnchor < rightAnchor
    }
}
