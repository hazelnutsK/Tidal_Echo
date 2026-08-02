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

enum BrainTarget: String, Codable, CaseIterable, Identifiable {
    case desktop
    case loop

    var id: String { rawValue }
    var title: String { self == .desktop ? "Desktop" : "API" }
}

struct BrainResponse: Decodable {
    let target: BrainTarget
}

struct LoopRoute: Codable {
    var index: Int?
    var url: String?
    var model: String?
}

struct LoopConfigResponse: Decodable {
    let mainChain: [LoopRoute]
    let apiPresets: [APIPreset]

    enum CodingKeys: String, CodingKey {
        case mainChain = "main_chain"
        case apiPresets = "api_presets"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mainChain = try values.decodeIfPresent([LoopRoute].self, forKey: .mainChain) ?? []
        apiPresets = try values.decodeIfPresent([APIPreset].self, forKey: .apiPresets) ?? []
    }
}

struct APIPreset: Codable, Identifiable {
    let index: Int
    let name: String
    let url: String
    let model: String
    let keyMasked: String
    let active: Bool

    var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case index, name, url, model, active
        case keyMasked = "key_masked"
    }
}

struct APIPresetInput: Encodable {
    let name: String
    let url: String
    let key: String
    let model: String
}

enum ChatMode: String, Codable, CaseIterable, Identifiable {
    case long
    case short
    var id: String { rawValue }
    var title: String { self == .long ? "长聊" : "短聊" }
}

struct ChatModeResponse: Decodable {
    let mode: ChatMode
}

indirect enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let object = try? value.decode([String: JSONValue].self) { self = .object(object) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else { self = .null }
    }
}

struct QuotaResponse: Decodable {
    let raw: JSONValue
}

struct APIUsageNumbers: Decodable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let costUSD: Double?

    enum CodingKeys: String, CodingKey {
        case input, output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case costUSD = "cost_usd"
    }
}

struct APIKeepaliveStats: Decodable {
    let beats: Int
    let costUSD: Double
    let badCount: Int

    enum CodingKeys: String, CodingKey {
        case beats
        case costUSD = "cost_usd"
        case badCount = "bad_count"
    }
}

struct APIUsageEntry: Decodable, Identifiable {
    let id: Int
    let timestamp: String
    let model: String?
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let costUSD: Double

    enum CodingKeys: String, CodingKey {
        case id, model, input, output
        case timestamp = "ts"
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case costUSD = "cost_usd"
    }
}

struct APIUsageStats: Decodable {
    let messages: Int
    let total: APIUsageNumbers
    let totalCostUSD: Double
    let average: APIUsageNumbers
    let cacheHitRate: Double
    let keepalive: APIKeepaliveStats
    let cacheTTL: String
    let recent: [APIUsageEntry]

    enum CodingKeys: String, CodingKey {
        case messages, total, keepalive, recent
        case totalCostUSD = "total_cost_usd"
        case average = "avg_per_message"
        case cacheHitRate = "cache_hit_rate"
        case cacheTTL = "cache_ttl"
    }
}

struct DesktopModelResponse: Decodable {
    let model: String
    let applied: Bool?
    let note: String?
}

struct ContextPending: Decodable {
    let newSID: String

    enum CodingKeys: String, CodingKey {
        case newSID = "new_sid"
    }
}

struct ContextStatus: Decodable {
    let ok: Bool
    let usageTokens: Int
    let thresholdText: String
    let triggerK: Int
    let auto: Bool
    let activeSID: String
    let pending: ContextPending?

    enum CodingKeys: String, CodingKey {
        case ok, auto, pending
        case usageTokens = "usage_tokens"
        case thresholdText = "threshold_k"
        case triggerK = "trigger_k"
        case activeSID = "active_sid"
    }
}

struct ContextThresholdResponse: Decodable {
    let triggerK: Int
    let auto: Bool

    enum CodingKeys: String, CodingKey {
        case auto
        case triggerK = "trigger_k"
    }
}

struct ContextActionResponse: Decodable {
    let ok: Bool
    let action: String
}

