import Foundation

enum MessageAuthor: String, Decodable, Hashable {
    case human
    case ai
}

enum DeliveryState: Hashable {
    case sending
    case sent
    case failed
}

struct Attachment: Codable, Hashable, Identifiable {
    var url: String
    var name: String
    var size: Int?
    var mime: String?
    var kind: String?
    var width: Double?
    var height: Double?
    var voice: Bool?

    var id: String { "\(url)#\(name)" }
    var isImage: Bool { kind == "image" || mime?.hasPrefix("image/") == true }
}

struct MessageMeta: Decodable, Hashable {
    var attachments: [Attachment]
    var reactions: [String: String]
    var hidden: Bool
    var apiSession: String?
    var streamID: String?
    var sortAfter: Int?

    enum CodingKeys: String, CodingKey {
        case attachments
        case reactions
        case hidden
        case apiSession = "api_session"
        case streamID = "stream_id"
        case sortAfter = "sort_after"
    }

    init(
        attachments: [Attachment] = [],
        reactions: [String: String] = [:],
        hidden: Bool = false,
        apiSession: String? = nil,
        streamID: String? = nil,
        sortAfter: Int? = nil
    ) {
        self.attachments = attachments
        self.reactions = reactions
        self.hidden = hidden
        self.apiSession = apiSession
        self.streamID = streamID
        self.sortAfter = sortAfter
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        attachments = try values.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        reactions = try values.decodeIfPresent([String: String].self, forKey: .reactions) ?? [:]
        hidden = try values.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        apiSession = try values.decodeIfPresent(String.self, forKey: .apiSession)
        streamID = try values.decodeIfPresent(String.self, forKey: .streamID)
        sortAfter = try values.decodeIfPresent(Int.self, forKey: .sortAfter)
    }
}

struct ChatMessage: Decodable, Hashable, Identifiable {
    var id: Int
    var timestamp: String
    var author: MessageAuthor
    var kind: String
    var text: String
    var meta: MessageMeta
    var delivery: DeliveryState

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp = "ts"
        case author = "from"
        case kind
        case text
        case meta
    }

    init(
        id: Int,
        timestamp: String,
        author: MessageAuthor,
        kind: String,
        text: String,
        meta: MessageMeta = MessageMeta(),
        delivery: DeliveryState = .sent
    ) {
        self.id = id
        self.timestamp = timestamp
        self.author = author
        self.kind = kind
        self.text = text
        self.meta = meta
        self.delivery = delivery
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        timestamp = try values.decode(String.self, forKey: .timestamp)
        author = try values.decode(MessageAuthor.self, forKey: .author)
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? "reply"
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        meta = try values.decodeIfPresent(MessageMeta.self, forKey: .meta) ?? MessageMeta()
        delivery = .sent
    }
}

struct HistoryResponse: Decodable {
    let messages: [ChatMessage]
}

struct SendResponse: Decodable {
    let id: Int
}

struct StreamEnvelope: Decodable {
    let type: String?
    let active: Bool?
    let id: Int?
    let reactions: [String: String]?
    let streamID: String?
    let text: String?
    let done: Bool?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case type, active, id, reactions, text, done
        case streamID = "stream_id"
        case timestamp = "ts"
    }
}

