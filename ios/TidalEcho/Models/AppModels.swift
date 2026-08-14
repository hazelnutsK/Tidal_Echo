import Foundation

enum MessageAuthor: String, Codable, Hashable {
    case human
    case ai
}

enum DeliveryState: Hashable {
    case sending
    case sent
    case failed
}

enum EchoBubbleStyle: String, Codable, CaseIterable, Identifiable {
    case classic
    case frosted
    case liquid

    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: return "经典"
        case .frosted: return "磨砂"
        case .liquid: return "液态玻璃"
        }
    }
}

enum EchoBubbleShapeStyle: String, Codable, CaseIterable, Identifiable {
    case standard
    case telegram

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "默认"
        case .telegram: return "仿 TG"
        }
    }
}

struct LiquidGlassSettings: Hashable {
    let strength: Double
    let dispersion: Double
    let rimWidth: Double
    let magnify: Double
    let blur: Double
    let size: Double
}

struct MessageTimer: Codable, Hashable {
    var label: String
    var minutes: Int
    var endsAt: String
    var status: String
    var doneAt: String?

    enum CodingKeys: String, CodingKey {
        case label, minutes, status
        case endsAt = "ends_at"
        case doneAt = "done_at"
    }
}

struct ToolStep: Decodable, Hashable {
    var tool: String?
    var cmd: String?
    var result: String?
}

private struct ActMeta: Decodable {
    var glyph: String?
    var steps: [ToolStep]?
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
    var isAudio: Bool { voice == true || kind == "audio" || mime?.hasPrefix("audio/") == true }
}

struct MessageAskAnswer: Decodable, Hashable {
    let kind: String
    let index: Int?
    let text: String
}

struct MessageAsk: Decodable, Hashable {
    let question: String
    let options: [String]
    var answer: MessageAskAnswer?
    var answeredAt: String?

    enum CodingKeys: String, CodingKey {
        case question, options, answer
        case answeredAt = "answered_at"
    }
}

struct MessageMeta: Decodable, Hashable {
    var attachments: [Attachment]
    var reactions: [String: String]
    var hidden: Bool
    var apiSession: String?
    var streamID: String?
    var sortAfter: Int?
    var starred: String?
    var timer: MessageTimer?
    var ask: MessageAsk?
    var edited: Bool
    var glyph: String?
    var steps: [ToolStep]
    var bookRef: BookRef?
    var callStatus: String?

    enum CodingKeys: String, CodingKey {
        case attachments
        case reactions
        case hidden
        case apiSession = "api_session"
        case streamID = "stream_id"
        case sortAfter = "sort_after"
        case bookRef = "book_ref"
        case callStatus = "call_status"
        case starred, timer, ask, edited, glyph, steps, act
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
        self.starred = nil
        self.timer = nil
        self.ask = nil
        self.edited = false
        self.glyph = nil
        self.steps = []
        self.bookRef = nil
        self.callStatus = nil
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        attachments = try values.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        reactions = try values.decodeIfPresent([String: String].self, forKey: .reactions) ?? [:]
        hidden = try values.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        apiSession = try values.decodeIfPresent(String.self, forKey: .apiSession)
        streamID = try values.decodeIfPresent(String.self, forKey: .streamID)
        sortAfter = try values.decodeIfPresent(Int.self, forKey: .sortAfter)
        starred = try values.decodeIfPresent(String.self, forKey: .starred)
        timer = try values.decodeIfPresent(MessageTimer.self, forKey: .timer)
        ask = try values.decodeIfPresent(MessageAsk.self, forKey: .ask)
        edited = try values.decodeIfPresent(Bool.self, forKey: .edited) ?? false
        bookRef = try values.decodeIfPresent(BookRef.self, forKey: .bookRef)
        callStatus = try values.decodeIfPresent(String.self, forKey: .callStatus)
        let nestedAct = try values.decodeIfPresent(ActMeta.self, forKey: .act)
        glyph = try values.decodeIfPresent(String.self, forKey: .glyph) ?? nestedAct?.glyph
        steps = try values.decodeIfPresent([ToolStep].self, forKey: .steps) ?? nestedAct?.steps ?? []
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

struct APISession: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    let sinceID: Int
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case sinceID = "since_id"
        case createdAt = "created_at"
    }
}

struct SessionsResponse: Decodable {
    let activeSession: String?
    let sessions: [APISession]
    let created: APISession?

    enum CodingKeys: String, CodingKey {
        case sessions, created
        case activeSession = "active_session"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        activeSession = try values.decodeIfPresent(String.self, forKey: .activeSession)
        sessions = try values.decodeIfPresent([APISession].self, forKey: .sessions) ?? []
        created = try values.decodeIfPresent(APISession.self, forKey: .created)
    }
}

struct SearchResponse: Decodable {
    let results: [ChatMessage]
}

struct ReactionResponse: Decodable {
    let reactions: [String: String]
}

struct TimerResponse: Decodable {
    let timer: MessageTimer
}

struct AskResponse: Decodable {
    let ask: MessageAsk
}

struct MessageNavigationRequest: Equatable {
    let token = UUID()
    let messageID: Int
}

struct SendResponse: Decodable {
    let id: Int
}

struct VoiceResponse: Decodable {
    let id: Int
    let text: String?
    let attachment: Attachment?
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
    let starred: String?
    let apiSession: String?
    let timer: MessageTimer?
    let ask: MessageAsk?
    let post: MomentPost?
    let bookID: Int?
    let annotation: BookAnnotation?

    enum CodingKeys: String, CodingKey {
        case type, active, id, reactions, text, done, starred, timer, ask, post, annotation
        case streamID = "stream_id"
        case timestamp = "ts"
        case apiSession = "api_session"
        case bookID = "book_id"
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

struct StarsResponse: Decodable { let stars: [ChatMessage] }

struct StarResponse: Decodable {
    let starred: String?
}

struct AlbumPhoto: Decodable, Identifiable {
    let url: String
    let timestamp: String
    let author: MessageAuthor
    var id: String { "\(timestamp)#\(url)" }

    enum CodingKeys: String, CodingKey {
        case url
        case timestamp = "ts"
        case author = "from"
    }
}

struct AlbumResponse: Decodable { let photos: [AlbumPhoto] }

struct GiftPage: Decodable, Identifiable {
    let file: String
    let title: String
    let modified: String
    var id: String { file }

    enum CodingKeys: String, CodingKey {
        case file, title
        case modified = "mtime"
    }
}

struct GiftPagesResponse: Decodable { let pages: [GiftPage] }

struct GreetingPool: Codable {
    let slots: [String: [String]]
}

struct DesireThought: Decodable, Identifiable {
    let text: String
    let drive: String
    let kind: String
    let strength: Double
    let bornAt: Double?

    var id: String { "\(kind)#\(drive)#\(text)" }

    enum CodingKeys: String, CodingKey {
        case text, drive, kind, strength
        case bornAt = "born_at"
    }
}

struct DesireIntent: Decodable {
    let wantAction: String?
    let driveKey: String?
    let reason: String
    let score: Double?

    enum CodingKeys: String, CodingKey {
        case reason, score
        case wantAction = "want_action"
        case driveKey = "drive_key"
    }
}

struct DesireActivity: Decodable {
    let enabled: Bool
    let libidoMultiplier: Double
    let cooldownLeftSeconds: Int
    let today: Int
    let dailyCap: Int
    let bodyTarget: String
    let bodyOnline: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, today
        case libidoMultiplier = "libido_mult"
        case cooldownLeftSeconds = "cooldown_left_sec"
        case dailyCap = "daily_cap"
        case bodyTarget = "body_target"
        case bodyOnline = "body_online"
    }
}

struct DesireState: Decodable {
    let drive: [String: Double]
    let intent: DesireIntent
    let thoughts: [DesireThought]
    let activity: DesireActivity

    enum CodingKeys: String, CodingKey {
        case drive, intent, thoughts
        case activity = "act"
    }
}

enum MomentKind: String, Codable, CaseIterable, Identifiable {
    case moment
    case journal
    var id: String { rawValue }
    var title: String { self == .moment ? "动态" : "日志" }
}

struct MomentComment: Codable, Identifiable, Hashable {
    let id: Int
    let timestamp: String
    let author: MessageAuthor
    let text: String
    let replyTo: MessageAuthor?

    enum CodingKeys: String, CodingKey {
        case id, author, text
        case timestamp = "ts"
        case replyTo = "reply_to"
    }
}

struct MomentMeta: Decodable, Hashable {
    let attachments: [Attachment]
    var likes: [String: String]
    var comments: [MomentComment]

    enum CodingKeys: String, CodingKey { case attachments, likes, comments }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        attachments = try values.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        likes = try values.decodeIfPresent([String: String].self, forKey: .likes) ?? [:]
        comments = try values.decodeIfPresent([MomentComment].self, forKey: .comments) ?? []
    }
}

struct MomentPost: Decodable, Identifiable, Hashable {
    let id: Int
    let timestamp: String
    let author: MessageAuthor
    let kind: MomentKind
    let text: String
    var meta: MomentMeta

    enum CodingKeys: String, CodingKey {
        case id, author, kind, text, meta
        case timestamp = "ts"
    }
}

struct MomentsResponse: Decodable {
    let posts: [MomentPost]
    let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case posts
        case hasMore = "has_more"
    }
}

struct MomentPostResponse: Decodable { let post: MomentPost }
struct MomentLikeResponse: Decodable { let likes: [String: String] }
struct MomentCommentResponse: Decodable { let comment: MomentComment }

struct CalendarEvent: Decodable, Identifiable, Hashable {
    let id: Int
    let date: String
    let time: String
    let title: String
    let kind: String
    let visible: Bool
    let author: MessageAuthor
    let recurrence: String
    let remind: Bool
    let daysSince: Int?
    let years: Int?

    enum CodingKeys: String, CodingKey {
        case id, date, time, title, kind, visible, author, remind, years
        case recurrence = "recur"
        case daysSince = "days_since"
    }
}

struct CalendarMonthResponse: Decodable {
    let year: Int
    let month: Int
    let today: String
    let events: [CalendarEvent]
    let holidays: [String: String]
}

struct AnniversarySummary: Decodable, Hashable {
    let id: Int
    let title: String
    let startDate: String
    let daysSince: Int

    enum CodingKeys: String, CodingKey {
        case id, title
        case startDate = "start_date"
        case daysSince = "days_since"
    }
}

struct AnniversaryResponse: Decodable {
    let anniversary: AnniversarySummary?
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

