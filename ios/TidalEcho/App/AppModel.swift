import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case signedOut
        case connecting
        case connected
    }

    @Published var phase: Phase = .signedOut
    @Published var messages: [ChatMessage] = []
    @Published var pendingAttachments: [Attachment] = []
    @Published var isTyping = false
    @Published var streamingThinking = ""
    @Published var streamingReply = ""
    @Published var isStreamConnected = false
    @Published var isLoadingHistory = false
    @Published var isLoadingOlderHistory = false
    @Published var canLoadOlderHistory = false
    @Published var sessions: [APISession] = []
    @Published var activeSessionID = AppModel.legacySessionID
    @Published var isLoadingSessions = false
    @Published var navigationRequest: MessageNavigationRequest?
    @Published var isUploading = false
    @Published var isUploadingVoice = false
    @Published var isSynthesizingMessageID: Int?
    @Published var errorMessage: String?
    @Published private(set) var giftUnreadCount = 0
    @Published private(set) var momentsUnreadCount = 0
    /// 小克在书页边留了一句话：正开着那一章的阅读页会当场把它长出来。
    @Published var incomingBookAnnotation: BookAnnotationEvent?
    @Published var theme: EchoTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var chatFont: EchoChatFont {
        didSet { UserDefaults.standard.set(chatFont.rawValue, forKey: Keys.chatFont) }
    }
    @Published var fontScale: Double {
        didSet { UserDefaults.standard.set(fontScale, forKey: Keys.fontScale) }
    }
    @Published var showsAIAvatar: Bool {
        didSet { UserDefaults.standard.set(showsAIAvatar, forKey: Keys.showsAIAvatar) }
    }
    @Published var bubbleOpacity: Double {
        didSet { UserDefaults.standard.set(bubbleOpacity, forKey: Keys.bubbleOpacity) }
    }
    @Published var bubbleRadius: Double {
        didSet { UserDefaults.standard.set(bubbleRadius, forKey: Keys.bubbleRadius) }
    }
    @Published var chatWeight: Double {
        didSet { UserDefaults.standard.set(chatWeight, forKey: Keys.chatWeight) }
    }
    @Published var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: Keys.backgroundOpacity) }
    }
    @Published var backgroundBlur: Double {
        didSet { UserDefaults.standard.set(backgroundBlur, forKey: Keys.backgroundBlur) }
    }
    @Published var showsAIBubble: Bool {
        didSet { UserDefaults.standard.set(showsAIBubble, forKey: Keys.showsAIBubble) }
    }
    @Published var showsHumanAvatar: Bool {
        didSet { UserDefaults.standard.set(showsHumanAvatar, forKey: Keys.showsHumanAvatar) }
    }
    @Published var bubbleWidthScale: Double {
        didSet { UserDefaults.standard.set(bubbleWidthScale, forKey: Keys.bubbleWidthScale) }
    }
    @Published var bubbleBorderWidth: Double {
        didSet { UserDefaults.standard.set(bubbleBorderWidth, forKey: Keys.bubbleBorderWidth) }
    }
    @Published var bubbleStyle: EchoBubbleStyle {
        didSet { UserDefaults.standard.set(bubbleStyle.rawValue, forKey: Keys.bubbleStyle) }
    }
    @Published var bubbleShapeStyle: EchoBubbleShapeStyle {
        didSet { UserDefaults.standard.set(bubbleShapeStyle.rawValue, forKey: Keys.bubbleShapeStyle) }
    }
    @Published var liquidGlassStrength: Double {
        didSet { UserDefaults.standard.set(liquidGlassStrength, forKey: Keys.liquidGlassStrength) }
    }
    @Published var liquidGlassDispersion: Double {
        didSet { UserDefaults.standard.set(liquidGlassDispersion, forKey: Keys.liquidGlassDispersion) }
    }
    @Published var liquidGlassRimWidth: Double {
        didSet { UserDefaults.standard.set(liquidGlassRimWidth, forKey: Keys.liquidGlassRimWidth) }
    }
    @Published var liquidGlassMagnify: Double {
        didSet { UserDefaults.standard.set(liquidGlassMagnify, forKey: Keys.liquidGlassMagnify) }
    }
    @Published var liquidGlassBlur: Double {
        didSet { UserDefaults.standard.set(liquidGlassBlur, forKey: Keys.liquidGlassBlur) }
    }
    @Published var liquidGlassSize: Double {
        didSet { UserDefaults.standard.set(liquidGlassSize, forKey: Keys.liquidGlassSize) }
    }
    @Published var peerRemark: String {
        didSet { UserDefaults.standard.set(peerRemark, forKey: Keys.peerRemark) }
    }
    @Published var aiBubbleColorHex: String {
        didSet { UserDefaults.standard.set(aiBubbleColorHex, forKey: Keys.aiBubbleColor) }
    }
    @Published var humanBubbleColorHex: String {
        didSet { UserDefaults.standard.set(humanBubbleColorHex, forKey: Keys.humanBubbleColor) }
    }
    @Published var aiBubbleTextColorHex: String {
        didSet { UserDefaults.standard.set(aiBubbleTextColorHex, forKey: Keys.aiBubbleTextColor) }
    }
    @Published var humanBubbleTextColorHex: String {
        didSet { UserDefaults.standard.set(humanBubbleTextColorHex, forKey: Keys.humanBubbleTextColor) }
    }
    @Published var backgroundImage: UIImage?
    @Published var aiAvatarImage: UIImage?
    @Published var humanAvatarImage: UIImage?

    private var client: APIClient?
    private let stream = SSEClient()
    private var heartbeatTask: Task<Void, Never>?
    private var incrementalSyncTask: Task<Void, Never>?
    private var typingTimeoutTask: Task<Void, Never>?
    private var typingSuppressedUntil = Date.distantPast
    private var isCatchingUp = false
    private var temporaryID = -1
    private var didBootstrap = false
    private var historyArchive: [ChatMessage] = []
    private var locallyHiddenMessageIDs: Set<Int> = []
    private var missedCallMessageIDs: Set<Int> = []
    private var pendingMissedCallMessageIDs: Set<Int> = []
    private var currentGiftTokens: Set<String> = []
    private var currentAIPostIDs: Set<Int> = []

    private static let initialHistoryWindow = 120
    private static let olderHistoryPageSize = 80
    static let legacySessionID = "__legacy__"

    private enum Keys {
        static let relayURL = "tidalEcho.relayURL"
        static let relaySecret = "relaySecret"
        static let theme = "tidalEcho.theme"
        static let chatFont = "tidalEcho.chatFont"
        static let fontScale = "tidalEcho.fontScale"
        static let showsAIAvatar = "tidalEcho.showsAIAvatar"
        static let bubbleOpacity = "tidalEcho.bubbleOpacity"
        static let bubbleRadius = "tidalEcho.bubbleRadius"
        static let chatWeight = "tidalEcho.chatWeight"
        static let backgroundOpacity = "tidalEcho.backgroundOpacity"
        static let backgroundBlur = "tidalEcho.backgroundBlur"
        static let showsAIBubble = "tidalEcho.showsAIBubble"
        static let showsHumanAvatar = "tidalEcho.showsHumanAvatar"
        static let bubbleWidthScale = "tidalEcho.bubbleWidthScale"
        static let bubbleBorderWidth = "tidalEcho.bubbleBorderWidth"
        static let bubbleStyle = "tidalEcho.bubbleStyle"
        static let bubbleShapeStyle = "tidalEcho.bubbleShapeStyle"
        static let liquidGlassStrength = "tidalEcho.liquidGlassStrength"
        static let liquidGlassDispersion = "tidalEcho.liquidGlassDispersion"
        static let liquidGlassRimWidth = "tidalEcho.liquidGlassRimWidth"
        static let liquidGlassMagnify = "tidalEcho.liquidGlassMagnify"
        static let liquidGlassBlur = "tidalEcho.liquidGlassBlur"
        static let liquidGlassSize = "tidalEcho.liquidGlassSize"
        static let pwaBubbleMetricsV1 = "tidalEcho.pwaBubbleMetricsV1"
        static let paperPresetV3 = "tidalEcho.paperPresetV3"
        static let peerRemark = "tidalEcho.peerRemark"
        static let aiBubbleColor = "tidalEcho.aiBubbleColor"
        static let humanBubbleColor = "tidalEcho.humanBubbleColor"
        static let aiBubbleTextColor = "tidalEcho.aiBubbleTextColor"
        static let humanBubbleTextColor = "tidalEcho.humanBubbleTextColor"
        // Kept only to migrate the first shared text-color setting.
        static let bubbleTextColor = "tidalEcho.bubbleTextColor"
        static let lastNativeNotificationID = "tidalEcho.lastNativeNotificationID"
        static let activeSessionID = "tidalEcho.activeSessionID"
        static let locallyHiddenMessageIDs = "tidalEcho.locallyHiddenMessageIDs"
        static let missedCallMessageIDs = "tidalEcho.missedCallMessageIDs"
        static let pendingMissedCallMessageIDs = "tidalEcho.pendingMissedCallMessageIDs"
        static let seenGiftTokens = "tidalEcho.seenGiftTokens"
        static let seenAIPostIDs = "tidalEcho.seenAIPostIDs"
        static let greetingCache = "tidalEcho.greetingCache"
    }

    enum AppearanceImageKind: Equatable {
        case background
        case aiAvatar
        case humanAvatar

        var filename: String {
            switch self {
            case .background: return "chat-background.jpg"
            case .aiAvatar: return "ai-avatar.jpg"
            case .humanAvatar: return "human-avatar.jpg"
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        let rawTheme = defaults.string(forKey: Keys.theme) ?? EchoTheme.mist.rawValue
        let initialTheme = EchoTheme(rawValue: rawTheme) ?? .mist
        let shouldMigratePaperPreset = initialTheme == .paper && !defaults.bool(forKey: Keys.paperPresetV3)
        theme = initialTheme
        let rawFont = defaults.string(forKey: Keys.chatFont) ?? EchoChatFont.system.rawValue
        chatFont = EchoChatFont(rawValue: rawFont) ?? .system
        fontScale = defaults.object(forKey: Keys.fontScale) == nil ? 1 : defaults.double(forKey: Keys.fontScale)
        showsAIAvatar = defaults.object(forKey: Keys.showsAIAvatar) == nil ? true : defaults.bool(forKey: Keys.showsAIAvatar)
        bubbleOpacity = defaults.object(forKey: Keys.bubbleOpacity) == nil ? 1 : defaults.double(forKey: Keys.bubbleOpacity)
        let savedBubbleRadius = defaults.object(forKey: Keys.bubbleRadius) == nil ? 14 : defaults.double(forKey: Keys.bubbleRadius)
        if !defaults.bool(forKey: Keys.pwaBubbleMetricsV1), abs(savedBubbleRadius - 18) < 0.001 {
            // v1.11 used 18 as its native default; PWA resolves clamp(14px, 2vw, 20px)
            // to 14px on an iPhone. Migrate only the untouched old default once.
            bubbleRadius = 14
            defaults.set(14, forKey: Keys.bubbleRadius)
        } else {
            bubbleRadius = savedBubbleRadius
        }
        defaults.set(true, forKey: Keys.pwaBubbleMetricsV1)
        chatWeight = defaults.object(forKey: Keys.chatWeight) == nil ? 400 : defaults.double(forKey: Keys.chatWeight)
        backgroundOpacity = defaults.object(forKey: Keys.backgroundOpacity) == nil ? 1 : defaults.double(forKey: Keys.backgroundOpacity)
        backgroundBlur = defaults.object(forKey: Keys.backgroundBlur) == nil ? 0 : defaults.double(forKey: Keys.backgroundBlur)
        showsAIBubble = defaults.object(forKey: Keys.showsAIBubble) == nil ? true : defaults.bool(forKey: Keys.showsAIBubble)
        showsHumanAvatar = defaults.object(forKey: Keys.showsHumanAvatar) == nil ? false : defaults.bool(forKey: Keys.showsHumanAvatar)
        bubbleWidthScale = defaults.object(forKey: Keys.bubbleWidthScale) == nil ? 1 : defaults.double(forKey: Keys.bubbleWidthScale)
        bubbleBorderWidth = defaults.object(forKey: Keys.bubbleBorderWidth) == nil ? 0 : defaults.double(forKey: Keys.bubbleBorderWidth)
        bubbleStyle = EchoBubbleStyle(rawValue: defaults.string(forKey: Keys.bubbleStyle) ?? "") ?? .classic
        bubbleShapeStyle = EchoBubbleShapeStyle(
            rawValue: defaults.string(forKey: Keys.bubbleShapeStyle) ?? ""
        ) ?? .standard
        liquidGlassStrength = defaults.object(forKey: Keys.liquidGlassStrength) == nil ? 56.8 : defaults.double(forKey: Keys.liquidGlassStrength)
        liquidGlassDispersion = defaults.object(forKey: Keys.liquidGlassDispersion) == nil ? 0.39 : defaults.double(forKey: Keys.liquidGlassDispersion)
        liquidGlassRimWidth = defaults.object(forKey: Keys.liquidGlassRimWidth) == nil ? 0.28 : defaults.double(forKey: Keys.liquidGlassRimWidth)
        liquidGlassMagnify = defaults.object(forKey: Keys.liquidGlassMagnify) == nil ? 0 : defaults.double(forKey: Keys.liquidGlassMagnify)
        liquidGlassBlur = defaults.object(forKey: Keys.liquidGlassBlur) == nil ? 0.94 : defaults.double(forKey: Keys.liquidGlassBlur)
        liquidGlassSize = defaults.object(forKey: Keys.liquidGlassSize) == nil ? 174 : defaults.double(forKey: Keys.liquidGlassSize)
        peerRemark = defaults.string(forKey: Keys.peerRemark) ?? ""
        aiBubbleColorHex = defaults.string(forKey: Keys.aiBubbleColor) ?? ""
        humanBubbleColorHex = defaults.string(forKey: Keys.humanBubbleColor) ?? ""
        let legacyBubbleTextColor = defaults.string(forKey: Keys.bubbleTextColor) ?? ""
        aiBubbleTextColorHex = defaults.string(forKey: Keys.aiBubbleTextColor) ?? legacyBubbleTextColor
        humanBubbleTextColorHex = defaults.string(forKey: Keys.humanBubbleTextColor) ?? legacyBubbleTextColor
        activeSessionID = defaults.string(forKey: Keys.activeSessionID) ?? Self.legacySessionID
        if let hidden = defaults.array(forKey: Keys.locallyHiddenMessageIDs) as? [Int] {
            locallyHiddenMessageIDs = Set(hidden)
        }
        missedCallMessageIDs = Set((defaults.array(forKey: Keys.missedCallMessageIDs) as? [Int]) ?? [])
        pendingMissedCallMessageIDs = Set((defaults.array(forKey: Keys.pendingMissedCallMessageIDs) as? [Int]) ?? [])
        backgroundImage = Self.loadAppearanceImage(.background)
        aiAvatarImage = Self.loadAppearanceImage(.aiAvatar)
        humanAvatarImage = Self.loadAppearanceImage(.humanAvatar)
        if shouldMigratePaperPreset {
            applyPaperAppearancePreset()
            defaults.set(true, forKey: Keys.paperPresetV3)
        }
        NativeCallCoordinator.shared.onDeclineIncomingCall = { [weak self] messageID in
            await self?.markIncomingCallMissed(messageID: messageID)
        }
    }

    var savedServerAddress: String {
        UserDefaults.standard.string(forKey: Keys.relayURL) ?? ""
    }

    var connectionText: String {
        if isTyping { return "\(peerDisplayName)正在输入…" }
        return isStreamConnected ? "online" : "connecting…"
    }

    /// Every theme respects the wallpaper selected by the user. Paper used to
    /// suppress it here, which made the picker preview update while chat stayed
    /// pinned to the preset background.
    var visibleBackgroundImage: UIImage? {
        backgroundImage
    }

    var peerDisplayName: String {
        let value = peerRemark.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "小克" : value
    }

    var liquidGlassSettings: LiquidGlassSettings {
        LiquidGlassSettings(
            strength: liquidGlassStrength,
            dispersion: liquidGlassDispersion,
            rimWidth: liquidGlassRimWidth,
            magnify: liquidGlassMagnify,
            blur: liquidGlassBlur,
            size: liquidGlassSize
        )
    }

    func applyTheme(_ nextTheme: EchoTheme) {
        theme = nextTheme
        guard nextTheme == .paper else { return }
        applyPaperAppearancePreset()
        UserDefaults.standard.set(true, forKey: Keys.paperPresetV3)
    }

    private func applyPaperAppearancePreset() {
        chatFont = .rounded
        fontScale = 0.95
        chatWeight = 340
        showsAIBubble = true
        bubbleStyle = .classic
        bubbleShapeStyle = .standard
        aiBubbleColorHex = "#EEEBE4"
        humanBubbleColorHex = "#E2C2C5"
        bubbleOpacity = 0.60
        bubbleRadius = 21
        bubbleWidthScale = 1.20
        bubbleBorderWidth = 0
        backgroundOpacity = 1
        showsAIAvatar = true
        showsHumanAvatar = true
        installPaperPresetAvatar(named: "paper-ai-avatar", kind: .aiAvatar)
        installPaperPresetAvatar(named: "paper-human-avatar", kind: .humanAvatar)
    }

    private func installPaperPresetAvatar(named name: String, kind: AppearanceImageKind) {
        let rootURL = Bundle.main.url(forResource: name, withExtension: "jpg")
        let nestedURL = Bundle.main.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: "ThemePresets"
        )
        guard let url = rootURL ?? nestedURL,
              let data = try? Data(contentsOf: url) else { return }
        try? saveAppearanceImage(data: data, kind: kind)
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
        incrementalSyncTask?.cancel()
        incrementalSyncTask = nil
        client = nil
        messages = []
        historyArchive = []
        sessions = []
        canLoadOlderHistory = false
        pendingAttachments = []
        streamingThinking = ""
        streamingReply = ""
        updateTypingState(false)
        isStreamConnected = false
        KeychainStore.delete(account: Keys.relaySecret)
        phase = .signedOut
    }

    func refresh() async {
        guard client != nil else { return }
        await loadHistory()
    }

    func loadOlderHistory() async -> Int? {
        guard !isLoadingOlderHistory, canLoadOlderHistory,
              let oldestID = messages.filter({ $0.id > 0 }).map(\.id).min(),
              let oldestIndex = historyArchive.firstIndex(where: { $0.id == oldestID }),
              oldestIndex > 0 else {
            canLoadOlderHistory = false
            return nil
        }
        isLoadingOlderHistory = true
        defer { isLoadingOlderHistory = false }
        let start = max(0, oldestIndex - Self.olderHistoryPageSize)
        let older = historyArchive[start..<oldestIndex]
        var merged = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        older.forEach { merged[$0.id] = $0 }
        messages = merged.values.sorted(by: Self.messageComesBefore)
        canLoadOlderHistory = start > 0
        return oldestID
    }

    func searchMessages(_ query: String) async throws -> [ChatMessage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await requireClient().search(trimmed).filter { !locallyHiddenMessageIDs.contains($0.id) }
    }

    func sessionTitle(for message: ChatMessage) -> String {
        guard let id = message.meta.apiSession, !id.isEmpty else { return "Claude Code" }
        return sessions.first(where: { $0.id == id })?.title ?? "对话窗口"
    }

    func jumpToMessage(_ message: ChatMessage) async {
        let targetSession = normalizedSessionID(message.meta.apiSession)
        if targetSession != activeSessionID {
            await activateSession(targetSession)
        }
        guard let index = historyArchive.firstIndex(where: { $0.id == message.id }) else {
            errorMessage = "没有在当前记录中找到这条消息"
            return
        }
        let start = max(0, index - 45)
        let end = min(historyArchive.count, index + 46)
        messages = Array(historyArchive[start..<end])
        canLoadOlderHistory = start > 0
        navigationRequest = MessageNavigationRequest(messageID: message.id)
    }

    func refreshSessions() async {
        guard let client else { return }
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            applySessionsResponse(try await client.sessions(), chooseServerActiveWhenNeeded: false)
        } catch {
            sessions = []
        }
    }

    func activateSession(_ id: String) async {
        guard let client else { return }
        let next = normalizedSessionID(id)
        guard next != activeSessionID else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            applySessionsResponse(try await client.updateSession(id: next, active: true), chooseServerActiveWhenNeeded: false)
            activeSessionID = next
            UserDefaults.standard.set(next, forKey: Keys.activeSessionID)
            streamingThinking = ""
            streamingReply = ""
            updateTypingState(false)
            await loadHistory(showLoadingState: false)
        } catch {
            errorMessage = "切换对话失败：\(error.localizedDescription)"
        }
    }

    func createSession(body: BrainTarget, title: String? = nil) async throws {
        let fallback = body == .codex ? "Codex 对话" : "API 对话"
        let response = try await requireClient().createSession(title: title ?? fallback, body: body)
        applySessionsResponse(response, chooseServerActiveWhenNeeded: true)
        if let created = response.created {
            activeSessionID = created.id
        } else if let active = response.activeSession, !active.isEmpty {
            activeSessionID = active
        }
        UserDefaults.standard.set(activeSessionID, forKey: Keys.activeSessionID)
        historyArchive = []
        messages = []
        canLoadOlderHistory = false
    }

    func renameSession(id: String, title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        applySessionsResponse(
            try await requireClient().updateSession(id: id, title: trimmed),
            chooseServerActiveWhenNeeded: false
        )
    }

    func deleteSession(id: String) async throws {
        let wasActive = activeSessionID == id
        let response = try await requireClient().deleteSession(id: id)
        applySessionsResponse(response, chooseServerActiveWhenNeeded: true)
        if wasActive {
            activeSessionID = normalizedSessionID(response.activeSession)
            UserDefaults.standard.set(activeSessionID, forKey: Keys.activeSessionID)
            await loadHistory()
        }
    }

    func editMessage(id: Int, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        upsert(try await requireClient().editMessage(id: id, text: trimmed))
    }

    func regenerateMessage(id: Int) async throws {
        try await requireClient().regenerateMessage(id: id)
        typingSuppressedUntil = .distantPast
        updateTypingState(true)
    }

    func hideMessageLocally(id: Int) {
        guard id > 0 else {
            messages.removeAll { $0.id == id }
            return
        }
        locallyHiddenMessageIDs.insert(id)
        UserDefaults.standard.set(Array(locallyHiddenMessageIDs).sorted(), forKey: Keys.locallyHiddenMessageIDs)
        messages.removeAll { $0.id == id }
        historyArchive.removeAll { $0.id == id }
    }

    var activeSessionTitle: String {
        if activeSessionID == Self.legacySessionID { return "Claude Code" }
        return sessions.first(where: { $0.id == activeSessionID })?.title ?? "对话窗口"
    }

    private var activeWireSessionID: String? {
        activeSessionID == Self.legacySessionID ? nil : activeSessionID
    }

    func backgroundRefreshForNotifications() async -> Bool {
        if client == nil { await bootstrap() }
        guard let client else { return false }
        let lastNotified = UserDefaults.standard.integer(forKey: Keys.lastNativeNotificationID)
        let visibleHistoryCursor = messages.map(\.id).filter { $0 > 0 }.max() ?? 0
        let historyCursor = max(visibleHistoryCursor, lastNotified)
        guard historyCursor > 0 else { return false }
        do {
            let fetched = try await client.history(since: historyCursor, limit: 100).filter { !$0.meta.hidden }
            let newestFetchedID = fetched.map(\.id).filter { $0 > 0 }.max() ?? historyCursor
            if lastNotified == 0 {
                fetched.forEach { upsert($0, allowsNativeArrival: false) }
                markNativeNotificationCursor(newestFetchedID)
                return false
            }
            var deliveredNativeEvent = false
            for message in fetched {
                let isNewForNotifications = message.id > lastNotified
                upsert(message, allowsNativeArrival: isNewForNotifications)
                if isNewForNotifications, message.author == .ai,
                   message.kind == "reply" || isFreshIncomingCall(message) {
                    deliveredNativeEvent = true
                }
            }
            markNativeNotificationCursor(newestFetchedID)
            return deliveredNativeEvent
        } catch {
            return false
        }
    }

    func sendMessage(text rawText: String) async {
        guard let client else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            meta: MessageMeta(
                attachments: attachments,
                apiSession: activeSessionID == Self.legacySessionID ? nil : activeSessionID
            ),
            delivery: .sending
        )
        messages.append(optimistic)
        pendingAttachments = []
        // Show feedback immediately. The relay also broadcasts a typing event,
        // but that frame can arrive before the POST response on some iOS stacks.
        typingSuppressedUntil = .distantPast
        updateTypingState(true)

        do {
            let response = try await client.send(
                text: text,
                attachments: attachments,
                sessionID: activeSessionID == Self.legacySessionID ? nil : activeSessionID
            )
            if let realIndex = messages.firstIndex(where: { $0.id == response.id }) {
                messages[realIndex].delivery = .sent
                messages.removeAll { $0.id == tempID }
            } else if let tempIndex = messages.firstIndex(where: { $0.id == tempID }) {
                messages[tempIndex].id = response.id
                messages[tempIndex].delivery = .sent
                historyArchive.append(messages[tempIndex])
                historyArchive.sort(by: Self.messageComesBefore)
            }
        } catch {
            updateTypingState(false)
            if let index = messages.firstIndex(where: { $0.id == tempID }) {
                messages[index].delivery = .failed
            }
            errorMessage = "发送失败：\(error.localizedDescription)"
        }
    }

    func uploadImage(data: Data, name: String, mime: String) async {
        await uploadAttachment(data: data, name: name, mime: mime)
    }

    func uploadAttachment(data: Data, name: String, mime: String) async {
        guard let client else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            pendingAttachments.append(try await client.upload(data: data, name: name, mime: mime))
        } catch {
            errorMessage = "附件上传失败：\(error.localizedDescription)"
        }
    }

    func removePendingAttachment(_ attachment: Attachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func attachmentRequest(for attachment: Attachment) -> URLRequest? {
        client?.attachmentRequest(path: attachment.url)
    }

    func authenticatedRequest(path: String) -> URLRequest? {
        client?.attachmentRequest(path: path)
    }

    func spaceStars() async throws -> [ChatMessage] { try await requireClient().stars() }
    func spaceAlbum() async throws -> [AlbumPhoto] { try await requireClient().album() }
    func spaceGiftPages() async throws -> [GiftPage] { try await requireClient().giftPages() }
    func giftPageURL(file: String) -> URL? { client?.giftPageURL(file: file) }

    func answerAsk(messageID: Int, index: Int? = nil, text: String? = nil) async throws {
        let ask = try await requireClient().answerAsk(messageID: messageID, index: index, text: text)
        updateAsk(messageID: messageID, ask: ask)
    }

    func greetingForCurrentTime() async -> String? {
        let defaults = UserDefaults.standard
        let pool: GreetingPool?
        do {
            let fresh = try await requireClient().greetings()
            if let data = try? JSONEncoder().encode(fresh) {
                defaults.set(data, forKey: Keys.greetingCache)
            }
            pool = fresh
        } catch {
            pool = defaults.data(forKey: Keys.greetingCache)
                .flatMap { try? JSONDecoder().decode(GreetingPool.self, from: $0) }
        }
        guard let lines = pool?.slots[Self.greetingSlot(for: Date())], !lines.isEmpty else { return nil }
        return lines.randomElement()
    }

    func desireState() async throws -> DesireState {
        try await requireClient().desire()
    }

    func updateDesire(enabled: Bool? = nil, libidoMultiplier: Double? = nil) async throws -> DesireState {
        let client = try requireClient()
        try await client.updateDesire(enabled: enabled, libidoMultiplier: libidoMultiplier)
        return try await client.desire()
    }

    func refreshSpaceUnreadCounts() async {
        do {
            updateGiftUnread(with: try await requireClient().giftPages())
        } catch {
            // Keep the last trustworthy count when the room is temporarily offline.
        }

        do {
            let client = try requireClient()
            let moments = try await client.moments(kind: .moment, limit: 100).posts
            let journals = try await client.moments(kind: .journal, limit: 100).posts
            updateMomentUnread(with: moments + journals)
        } catch {
            // The two badges are independent; one failed endpoint should not erase either count.
        }
    }

    func markGiftPagesRead(_ pages: [GiftPage]) {
        currentGiftTokens.formUnion(pages.map(Self.giftToken))
        let defaults = UserDefaults.standard
        var seen = Set(defaults.stringArray(forKey: Keys.seenGiftTokens) ?? [])
        seen.formUnion(currentGiftTokens)
        defaults.set(Array(seen), forKey: Keys.seenGiftTokens)
        giftUnreadCount = 0
    }

    func markCurrentMomentsRead() {
        let defaults = UserDefaults.standard
        var seen = Set((defaults.array(forKey: Keys.seenAIPostIDs) as? [Int]) ?? [])
        seen.formUnion(currentAIPostIDs)
        defaults.set(Array(seen), forKey: Keys.seenAIPostIDs)
        momentsUnreadCount = 0
    }

    func markAllMomentsRead() async {
        do {
            let client = try requireClient()
            let moments = try await client.moments(kind: .moment, limit: 100).posts
            let journals = try await client.moments(kind: .journal, limit: 100).posts
            currentAIPostIDs.formUnion((moments + journals).filter { $0.author == .ai }.map(\.id))
        } catch {
            // The snapshot already loaded by the space home is still safe to mark.
        }
        markCurrentMomentsRead()
    }

    func markMomentPostsRead(_ posts: [MomentPost]) {
        currentAIPostIDs.formUnion(posts.filter { $0.author == .ai }.map(\.id))
        markCurrentMomentsRead()
    }

    func setStar(messageID: Int, on: Bool) async throws {
        let starred = try await requireClient().setStar(messageID: messageID, on: on)
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].meta.starred = starred
        }
        if let index = historyArchive.firstIndex(where: { $0.id == messageID }) {
            historyArchive[index].meta.starred = starred
        }
    }

    func reactToMessage(messageID: Int, emoji: String) async throws {
        let reactions = try await requireClient().reactToMessage(id: messageID, emoji: emoji)
        updateReactions(messageID: messageID, reactions: reactions)
    }

    func completeTimer(messageID: Int) async throws {
        let timer = try await requireClient().completeTimer(messageID: messageID)
        updateTimer(messageID: messageID, timer: timer)
    }

    func sendVoiceRecording(_ recording: VoiceRecordingResult) async -> Bool {
        guard let client else { return false }
        isUploadingVoice = true
        defer { isUploadingVoice = false }
        do {
            let response = try await client.sendVoiceAudio(
                data: recording.data,
                name: recording.name,
                mime: recording.mime,
                sessionID: activeWireSessionID
            )
            if !messages.contains(where: { $0.id == response.id }) {
                let transcript = (response.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                upsert(ChatMessage(
                    id: response.id,
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    author: .human,
                    kind: "voice",
                    text: transcript.isEmpty ? "" : "🎤 \(transcript)",
                    meta: MessageMeta(
                        attachments: response.attachment.map { [$0] } ?? [],
                        apiSession: activeWireSessionID
                    ),
                    delivery: .sent
                ))
            }
            await catchUp(using: client)
            return true
        } catch {
            errorMessage = "语音发送失败：\(error.localizedDescription)"
            return false
        }
    }

    func sendCallTranscript(_ text: String, callID: String) async throws -> VoiceResponse {
        let client = try requireClient()
        let response = try await client.sendVoiceText(
            text,
            source: "ios_speech",
            callID: callID,
            sessionID: activeWireSessionID
        )
        await catchUp(using: client)
        return response
    }

    /// 通话里说完的一句：转写和这句话的录音一起送。
    /// 录音会挂在她自己的气泡上（像语音条），也让耳朵听得见她是怎么说的。
    func sendCallUtterance(
        text: String,
        data: Data,
        name: String,
        mime: String,
        callID: String
    ) async throws -> VoiceResponse {
        let client = try requireClient()
        let response = try await client.sendVoiceAudio(
            data: data,
            name: name,
            mime: mime,
            callID: callID,
            text: text,
            sessionID: activeWireSessionID
        )
        await catchUp(using: client)
        return response
    }

    func sendCallAudioSegment(data: Data, name: String, mime: String, callID: String) async throws -> VoiceResponse {
        let client = try requireClient()
        let response = try await client.sendVoiceAudio(
            data: data,
            name: name,
            mime: mime,
            callID: callID,
            sessionID: activeWireSessionID
        )
        await catchUp(using: client)
        return response
    }

    func postCallEvent(_ action: String, callID: String, messageID: Int? = nil) async throws {
        _ = try await requireClient().callEvent(
            action,
            callID: callID,
            messageID: messageID,
            sessionID: activeWireSessionID
        )
    }

    private func markIncomingCallMissed(messageID: Int) async {
        guard messageID > 0 else { return }
        missedCallMessageIDs.insert(messageID)
        pendingMissedCallMessageIDs.insert(messageID)
        persistMissedCallState()
        applyMissedCallState(messageID: messageID)
        await flushPendingCallDeclines()
    }

    private func flushPendingCallDeclines() async {
        guard let client else { return }
        for messageID in pendingMissedCallMessageIDs.sorted() {
            do {
                _ = try await client.callEvent(
                    "decline",
                    callID: "incoming-\(messageID)",
                    messageID: messageID
                )
                pendingMissedCallMessageIDs.remove(messageID)
            } catch {
                // Keep it queued. The next successful connection retries the
                // idempotent server update so CallKit declines are never lost.
            }
        }
        persistMissedCallState()
    }

    private func applyMissedCallState(messageID: Int) {
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].meta.callStatus = "missed"
        }
        if let index = historyArchive.firstIndex(where: { $0.id == messageID }) {
            historyArchive[index].meta.callStatus = "missed"
        }
    }

    private func persistMissedCallState() {
        UserDefaults.standard.set(missedCallMessageIDs.sorted(), forKey: Keys.missedCallMessageIDs)
        UserDefaults.standard.set(pendingMissedCallMessageIDs.sorted(), forKey: Keys.pendingMissedCallMessageIDs)
    }

    func synthesizeSpeech(text: String, messageID: Int? = nil, persist: Bool = false) async throws -> Data {
        try await requireClient().tts(text: text, messageID: messageID, persist: persist)
    }

    func speakMessage(_ message: ChatMessage) async {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isSynthesizingMessageID == nil else { return }
        isSynthesizingMessageID = message.id
        defer { isSynthesizingMessageID = nil }
        do {
            let data = try await synthesizeSpeech(text: text)
            try VoicePlaybackCenter.shared.play(data: data, id: "tts-\(message.id)")
        } catch {
            errorMessage = "朗读失败：\(error.localizedDescription)"
        }
    }

    func spaceMoments(kind: MomentKind, before: Int? = nil, limit: Int = 20) async throws -> MomentsResponse {
        try await requireClient().moments(kind: kind, before: before, limit: limit)
    }

    func uploadMomentImage(data: Data, name: String, mime: String) async throws -> Attachment {
        try await requireClient().upload(data: data, name: name, mime: mime)
    }

    func createMoment(kind: MomentKind, text: String, attachments: [Attachment]) async throws -> MomentPost {
        try await requireClient().createMoment(kind: kind, text: text, attachments: attachments)
    }

    func likeMoment(id: Int, on: Bool) async throws -> [String: String] {
        try await requireClient().likeMoment(id: id, on: on)
    }

    func commentMoment(id: Int, text: String, replyTo: MessageAuthor? = nil) async throws -> MomentComment {
        try await requireClient().commentMoment(id: id, text: text, replyTo: replyTo)
    }

    func deleteMoment(id: Int) async throws { try await requireClient().deleteMoment(id: id) }

    // MARK: - 书房

    func bookShelf() async throws -> [Book] { try await requireClient().books() }

    func importBook(data: Data, name: String) async throws -> BookImportResult {
        try await requireClient().uploadBook(data: data, name: name)
    }

    func removeBook(id: Int) async throws { try await requireClient().deleteBook(id: id) }

    func bookChapter(bookID: Int, index: Int) async throws -> BookChapter {
        try await requireClient().bookChapter(bookID: bookID, index: index)
    }

    func reportBookProgress(bookID: Int, chapter: Int, offset: Int) async throws -> BookProgressResponse {
        try await requireClient().reportBookProgress(bookID: bookID, chapter: chapter, offset: offset)
    }

    func annotateBook(
        bookID: Int,
        chapterIdx: Int,
        start: Int,
        end: Int,
        quote: String,
        note: String
    ) async throws -> BookAnnotation {
        try await requireClient().annotateBook(
            bookID: bookID, chapterIdx: chapterIdx, start: start, end: end, quote: quote, note: note
        )
    }

    func deleteBookAnnotation(id: Int) async throws {
        try await requireClient().deleteBookAnnotation(id: id)
    }

    func bookThread(bookID: Int, annotationIDs: [Int]) async throws -> [ChatMessage] {
        try await requireClient().bookThread(bookID: bookID, annotationIDs: annotationIDs)
    }

    /// 从书页里说的一句话。走主聊天流，所以照常触发打字提示。
    func sendFromBook(text: String, bookRef: BookRef) async throws {
        let client = try requireClient()
        typingSuppressedUntil = .distantPast
        updateTypingState(true)
        _ = try await client.sendFromBook(
            text: text,
            bookRef: bookRef,
            sessionID: activeSessionID == Self.legacySessionID ? nil : activeSessionID
        )
    }

    func spaceCalendar(year: Int, month: Int) async throws -> CalendarMonthResponse {
        try await requireClient().calendar(year: year, month: month)
    }

    func relationshipAnniversary() async throws -> AnniversarySummary? {
        try await requireClient().anniversary()
    }

    func createCalendarEvent(_ payload: CalendarCreatePayload) async throws -> CalendarEvent {
        try await requireClient().createCalendarEvent(payload)
    }

    func deleteCalendarEvent(id: Int) async throws { try await requireClient().deleteCalendarEvent(id: id) }

    func resolvedAIBubbleColor(default fallback: Color) -> Color {
        Color(hexString: aiBubbleColorHex) ?? fallback
    }

    func resolvedHumanBubbleColor(default fallback: Color) -> Color {
        Color(hexString: humanBubbleColorHex) ?? fallback
    }

    func resolvedAIBubbleTextColor(default fallback: Color) -> Color {
        Color(hexString: aiBubbleTextColorHex) ?? fallback
    }

    func resolvedHumanBubbleTextColor(default fallback: Color) -> Color {
        Color(hexString: humanBubbleTextColorHex) ?? fallback
    }

    func setAIBubbleColor(_ color: Color) {
        aiBubbleColorHex = Self.hexString(color) ?? ""
    }

    func setHumanBubbleColor(_ color: Color) {
        humanBubbleColorHex = Self.hexString(color) ?? ""
    }

    func setAIBubbleTextColor(_ color: Color) {
        aiBubbleTextColorHex = Self.hexString(color) ?? ""
    }

    func setHumanBubbleTextColor(_ color: Color) {
        humanBubbleTextColorHex = Self.hexString(color) ?? ""
    }

    func resetBubbleColors() {
        aiBubbleColorHex = ""
        humanBubbleColorHex = ""
        aiBubbleTextColorHex = ""
        humanBubbleTextColorHex = ""
        UserDefaults.standard.removeObject(forKey: Keys.bubbleTextColor)
    }

    func saveAppearanceImage(data: Data, kind: AppearanceImageKind) throws {
        guard let original = UIImage(data: data) else { throw APIError.invalidResponse }
        let maxDimension: CGFloat = kind == .background ? 2200 : 640
        let image = Self.resizedImage(original, maxDimension: maxDimension)
        guard let encoded = image.jpegData(compressionQuality: kind == .background ? 0.84 : 0.9) else {
            throw APIError.invalidResponse
        }
        let url = try Self.appearanceImageURL(kind)
        try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        setAppearanceImage(image, kind: kind)
    }

    func removeAppearanceImage(_ kind: AppearanceImageKind) {
        if let url = try? Self.appearanceImageURL(kind) {
            try? FileManager.default.removeItem(at: url)
        }
        setAppearanceImage(nil, kind: kind)
    }

    func settingsBrain() async throws -> BrainTarget {
        try await requireClient().brain()
    }

    func updateSettingsBrain(_ target: BrainTarget) async throws -> BrainTarget {
        try await requireClient().setBrain(target)
    }

    func settingsLoopConfig() async throws -> LoopConfigResponse {
        try await requireClient().loopConfig()
    }

    func updateLoopModel(_ modelID: String, chainCount: Int) async throws -> LoopConfigResponse {
        try await requireClient().setLoopModel(modelID, chainCount: chainCount)
    }

    func activateAPIPreset(_ index: Int) async throws -> LoopConfigResponse {
        try await requireClient().activateAPIPreset(index)
    }

    func replaceAPIPresets(_ presets: [APIPresetInput]) async throws -> LoopConfigResponse {
        try await requireClient().replaceAPIPresets(presets)
    }

    func settingsChatMode() async throws -> ChatMode {
        try await requireClient().chatMode()
    }

    func updateChatMode(_ mode: ChatMode) async throws -> ChatMode {
        try await requireClient().setChatMode(mode)
    }

    func settingsQuota() async throws -> QuotaResponse {
        try await requireClient().quota()
    }

    func settingsAPIUsage() async throws -> APIUsageStats {
        try await requireClient().loopStats()
    }

    func settingsDesktopModel() async throws -> DesktopModelResponse {
        try await requireClient().desktopModel()
    }

    func updateDesktopModel(_ modelID: String) async throws -> DesktopModelResponse {
        try await requireClient().setDesktopModel(modelID)
    }

    func settingsContextStatus() async throws -> ContextStatus {
        try await requireClient().contextStatus()
    }

    func updateContextThreshold(triggerK: Int? = nil, auto: Bool? = nil) async throws -> ContextThresholdResponse {
        try await requireClient().updateContextThreshold(triggerK: triggerK, auto: auto)
    }

    func performContextAction(_ action: String, sid: String? = nil) async throws -> ContextActionResponse {
        try await requireClient().performContextAction(action, sid: sid)
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
            startStream(using: nextClient)
            startIncrementalSync(using: nextClient)
            // Open the real-time stream before loading a potentially large history.
            // Otherwise the chat UI is already usable while replies are not yet observed.
            phase = .connected
            await loadInitialSessions(using: nextClient)
            await loadHistory()
            if UIApplication.shared.applicationState == .active {
                markNativeNotificationCursor(messages.map(\.id).filter { $0 > 0 }.max() ?? 0)
            }
            await waitForStreamConnection()
            await catchUp(using: nextClient)
            await flushPendingCallDeclines()
            startHeartbeat()
        } catch {
            client = nil
            phase = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    private func loadHistory(showLoadingState: Bool = true) async {
        guard let client else { return }
        if showLoadingState { isLoadingHistory = true }
        defer { if showLoadingState { isLoadingHistory = false } }

        do {
            var cursor = 0
            var archive: [ChatMessage] = []
            for _ in 0..<200 {
                let batch = try await client.history(since: cursor, limit: 500, sessionID: activeSessionID)
                guard !batch.isEmpty else { break }
                archive.append(contentsOf: batch.filter {
                    !$0.meta.hidden && !locallyHiddenMessageIDs.contains($0.id) && messageBelongsToActiveSession($0)
                }.map(normalizingMissedCallState))
                guard let last = batch.last else { break }
                cursor = max(cursor, last.id)
                if batch.count < 500 { break }
            }
            historyArchive = Dictionary(uniqueKeysWithValues: archive.map { ($0.id, $0) })
                .values.sorted(by: Self.messageComesBefore)
            // Render only the newest window on launch. Building hundreds of variable-height
            // SwiftUI rows makes ScrollViewReader visibly travel through old conversations.
            let historyMaxID = historyArchive.map(\.id).max() ?? 0
            let visibleHistory = historyArchive.suffix(Self.initialHistoryWindow)
            var merged = Dictionary(uniqueKeysWithValues: visibleHistory.map { ($0.id, $0) })
            // Preserve SSE messages that arrived after the history snapshot, plus any
            // optimistic outgoing message still waiting for its permanent server id.
            for message in messages where (message.id < 0 || message.id > historyMaxID) && messageBelongsToActiveSession(message) {
                merged[message.id] = message
            }
            messages = merged.values.sorted(by: Self.messageComesBefore)
            canLoadOlderHistory = historyArchive.count > visibleHistory.count
            if UIApplication.shared.applicationState == .active {
                markNativeNotificationCursor(historyMaxID)
            }
        } catch {
            errorMessage = "聊天记录加载失败：\(error.localizedDescription)"
        }
    }

    private func loadInitialSessions(using client: APIClient) async {
        do {
            let response = try await client.sessions()
            applySessionsResponse(response, chooseServerActiveWhenNeeded: true)
        } catch {
            sessions = []
            activeSessionID = Self.legacySessionID
        }
    }

    private func applySessionsResponse(_ response: SessionsResponse, chooseServerActiveWhenNeeded: Bool) {
        sessions = response.sessions
        let validIDs = Set(response.sessions.map(\.id))
        let saved = UserDefaults.standard.string(forKey: Keys.activeSessionID) ?? activeSessionID
        if saved == Self.legacySessionID || validIDs.contains(saved) {
            activeSessionID = saved
        } else if chooseServerActiveWhenNeeded,
                  let serverActive = response.activeSession,
                  validIDs.contains(serverActive) {
            activeSessionID = serverActive
        } else {
            activeSessionID = Self.legacySessionID
        }
        UserDefaults.standard.set(activeSessionID, forKey: Keys.activeSessionID)
    }

    private func normalizedSessionID(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return Self.legacySessionID }
        return id
    }

    private func messageBelongsToActiveSession(_ message: ChatMessage) -> Bool {
        let messageSession = normalizedSessionID(message.meta.apiSession)
        return messageSession == activeSessionID
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
        guard !isCatchingUp else { return }
        let visibleHistoryCursor = messages.map(\.id).filter { $0 > 0 }.max() ?? 0
        var cursor = max(
            visibleHistoryCursor,
            UserDefaults.standard.integer(forKey: Keys.lastNativeNotificationID)
        )
        // While the initial history request is still walking old pages, wait until
        // either it finds a cursor or a newly sent message gives us one.
        guard cursor > 0 || !isLoadingHistory else { return }
        isCatchingUp = true
        defer { isCatchingUp = false }
        do {
            for _ in 0..<20 {
                let batch = try await client.history(since: cursor, limit: 500)
                guard !batch.isEmpty else { break }
                batch.filter { !$0.meta.hidden }.forEach { upsert($0) }
                guard let last = batch.last else { break }
                cursor = max(cursor, last.id)
                if batch.count < 500 { break }
            }
        } catch {
            // SSE is already active; a transient catch-up failure can recover on refresh.
        }
    }

    private func requireClient() throws -> APIClient {
        guard let client else { throw APIError.invalidResponse }
        return client
    }

    private func setAppearanceImage(_ image: UIImage?, kind: AppearanceImageKind) {
        switch kind {
        case .background: backgroundImage = image
        case .aiAvatar: aiAvatarImage = image
        case .humanAvatar: humanAvatarImage = image
        }
    }

    private static func appearanceImageURL(_ kind: AppearanceImageKind) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("TidalEcho", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(kind.filename)
    }

    private static func loadAppearanceImage(_ kind: AppearanceImageKind) -> UIImage? {
        guard let url = try? appearanceImageURL(kind),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else { return image }
        let scale = maxDimension / largest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private static func hexString(_ color: Color) -> String? {
        let resolved = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    private func startIncrementalSync(using client: APIClient) {
        incrementalSyncTask?.cancel()
        incrementalSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_200_000_000)
                } catch {
                    return
                }
                guard let self, self.phase == .connected else { return }
                // This is deliberately incremental (`since=<latest id>`), so the
                // response is normally empty and cheap. It covers iOS/network stacks
                // that report an open SSE connection but delay delivery of its chunks.
                await self.catchUp(using: client)
            }
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

    private func updateTypingState(_ active: Bool) {
        guard !active || Date() >= typingSuppressedUntil else { return }
        isTyping = active
        typingTimeoutTask?.cancel()
        typingTimeoutTask = nil
        guard active else { return }
        // Match the PWA safeguard: a dropped "typing: false" frame must not
        // leave the header stuck indefinitely.
        typingTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.isTyping = false
            self?.typingTimeoutTask = nil
        }
    }

    private func finishTypingAfterAIActivity() {
        // A queued `typing: true` frame can arrive just after the final reply.
        // Briefly reject that stale frame instead of flashing typing again.
        typingSuppressedUntil = Date().addingTimeInterval(2)
        updateTypingState(false)
    }

    private func receiveStreamEvent(_ data: Data) {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(StreamEnvelope.self, from: data),
           let type = envelope.type {
            switch type {
            case "typing":
                updateTypingState(envelope.active ?? false)
                return
            case "post":
                if let post = envelope.post, post.author == .ai {
                    currentAIPostIDs.insert(post.id)
                    if UserDefaults.standard.object(forKey: Keys.seenAIPostIDs) != nil {
                        let seen = Set((UserDefaults.standard.array(forKey: Keys.seenAIPostIDs) as? [Int]) ?? [])
                        momentsUnreadCount = currentAIPostIDs.subtracting(seen).count
                    }
                }
                return
            case "reaction":
                finishTypingAfterAIActivity()
                if let id = envelope.id {
                    updateReactions(messageID: id, reactions: envelope.reactions ?? [:], haptic: true)
                }
                return
            case "timer":
                if let id = envelope.id, let timer = envelope.timer {
                    updateTimer(messageID: id, timer: timer)
                }
                return
            case "ask":
                if let id = envelope.id, let ask = envelope.ask {
                    updateAsk(messageID: id, ask: ask)
                }
                return
            case "star":
                if let id = envelope.id,
                   let index = messages.firstIndex(where: { $0.id == id }) {
                    messages[index].meta.starred = envelope.starred
                }
                if let id = envelope.id,
                   let index = historyArchive.firstIndex(where: { $0.id == id }) {
                    historyArchive[index].meta.starred = envelope.starred
                }
                return
            case "book_annotation":
                if let bookID = envelope.bookID, let annotation = envelope.annotation {
                    incomingBookAnnotation = BookAnnotationEvent(bookID: bookID, annotation: annotation)
                }
                return
            case "remove":
                if let id = envelope.id {
                    messages.removeAll { $0.id == id }
                    historyArchive.removeAll { $0.id == id }
                }
                return
            case "thinking_delta":
                guard normalizedSessionID(envelope.apiSession) == activeSessionID else { return }
                streamingThinking += envelope.text ?? ""
                updateTypingState(false)
                return
            case "reply_delta":
                guard normalizedSessionID(envelope.apiSession) == activeSessionID else { return }
                streamingReply += envelope.text ?? ""
                updateTypingState(false)
                return
            default:
                break
            }
        }

        guard let message = try? decoder.decode(ChatMessage.self, from: data),
              !message.meta.hidden else { return }
        upsert(message)
        if message.author == .ai && messageBelongsToActiveSession(message) {
            finishTypingAfterAIActivity()
            if message.kind == "thinking" { streamingThinking = "" }
            if message.kind == "reply" {
                streamingReply = ""
            }
        }
    }

    private func updateAsk(messageID: Int, ask: MessageAsk) {
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].meta.ask = ask
        }
        if let index = historyArchive.firstIndex(where: { $0.id == messageID }) {
            historyArchive[index].meta.ask = ask
        }
    }

    private func updateGiftUnread(with pages: [GiftPage]) {
        let defaults = UserDefaults.standard
        currentGiftTokens = Set(pages.map(Self.giftToken))
        guard defaults.object(forKey: Keys.seenGiftTokens) != nil else {
            defaults.set(Array(currentGiftTokens), forKey: Keys.seenGiftTokens)
            giftUnreadCount = 0
            return
        }
        let seen = Set(defaults.stringArray(forKey: Keys.seenGiftTokens) ?? [])
        giftUnreadCount = currentGiftTokens.subtracting(seen).count
    }

    private func updateMomentUnread(with posts: [MomentPost]) {
        let defaults = UserDefaults.standard
        currentAIPostIDs = Set(posts.filter { $0.author == .ai }.map(\.id))
        guard defaults.object(forKey: Keys.seenAIPostIDs) != nil else {
            defaults.set(Array(currentAIPostIDs), forKey: Keys.seenAIPostIDs)
            momentsUnreadCount = 0
            return
        }
        let seen = Set((defaults.array(forKey: Keys.seenAIPostIDs) as? [Int]) ?? [])
        momentsUnreadCount = currentAIPostIDs.subtracting(seen).count
    }

    private static func giftToken(_ page: GiftPage) -> String {
        "\(page.file)#\(page.modified)"
    }

    private static func greetingSlot(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 0..<5: return "smallhours"
        case 5..<8: return "dawn"
        case 8..<11: return "morning"
        case 11..<14: return "noon"
        case 14..<18: return "afternoon"
        case 18..<21: return "evening"
        default: return "night"
        }
    }

    private func upsert(_ incomingMessage: ChatMessage, allowsNativeArrival: Bool = true) {
        let message = normalizingMissedCallState(incomingMessage)
        guard !locallyHiddenMessageIDs.contains(message.id) else { return }
        let wasKnown = messages.contains(where: { $0.id == message.id })
        let belongsToActiveSession = messageBelongsToActiveSession(message)
        if belongsToActiveSession {
            if let archiveIndex = historyArchive.firstIndex(where: { $0.id == message.id }) {
                historyArchive[archiveIndex] = message
            } else if message.id > 0 {
                historyArchive.append(message)
                historyArchive.sort(by: Self.messageComesBefore)
            }
        }
        guard belongsToActiveSession else {
            if allowsNativeArrival { handleNativeArrival(message, wasKnown: false) }
            return
        }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
            messages.sort(by: Self.messageComesBefore)
        }
        if allowsNativeArrival { handleNativeArrival(message, wasKnown: wasKnown) }
    }

    private func normalizingMissedCallState(_ incomingMessage: ChatMessage) -> ChatMessage {
        var message = incomingMessage
        if message.meta.callStatus == "missed" {
            missedCallMessageIDs.insert(message.id)
        } else if missedCallMessageIDs.contains(message.id) {
            message.meta.callStatus = "missed"
        }
        return message
    }

    private func handleNativeArrival(_ message: ChatMessage, wasKnown: Bool) {
        guard !wasKnown else { return }
        let lastSeenID = UserDefaults.standard.integer(forKey: Keys.lastNativeNotificationID)
        guard message.id > lastSeenID else { return }
        if message.author == .ai {
            if isFreshIncomingCall(message) {
                NativeCallCoordinator.shared.reportIncoming(messageID: message.id, text: message.text)
            } else if message.kind == "reply", UIApplication.shared.applicationState != .active {
                NativeNotificationCenter.shared.scheduleMessage(message)
            }
        }
        markNativeNotificationCursor(message.id)
    }

    private func isFreshIncomingCall(_ message: ChatMessage) -> Bool {
        guard message.author == .ai,
              message.kind == "call",
              message.meta.callStatus == nil || message.meta.callStatus == "ringing" else { return false }
        let formatter = ISO8601DateFormatter()
        let date: Date?
        if let parsed = formatter.date(from: message.timestamp) {
            date = parsed
        } else {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = formatter.date(from: message.timestamp)
        }
        guard let date else { return false }
        let age = Date().timeIntervalSince(date)
        return age >= -30 && age <= 120
    }

    private func updateReactions(messageID: Int, reactions: [String: String], haptic: Bool = false) {
        var shouldPulse = false
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            shouldPulse = haptic && messages[index].author == .human
                && messages[index].meta.reactions["ai"] != reactions["ai"]
                && reactions["ai"] != nil
            messages[index].meta.reactions = reactions
        }
        if let index = historyArchive.firstIndex(where: { $0.id == messageID }) {
            historyArchive[index].meta.reactions = reactions
        }
        if shouldPulse {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func updateTimer(messageID: Int, timer: MessageTimer) {
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].meta.timer = timer
        }
        if let index = historyArchive.firstIndex(where: { $0.id == messageID }) {
            historyArchive[index].meta.timer = timer
        }
    }

    private func markNativeNotificationCursor(_ id: Int) {
        guard id > 0 else { return }
        let current = UserDefaults.standard.integer(forKey: Keys.lastNativeNotificationID)
        if id > current { UserDefaults.standard.set(id, forKey: Keys.lastNativeNotificationID) }
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
