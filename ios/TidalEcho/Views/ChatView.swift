import AudioToolbox
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var nativeCalls = NativeCallCoordinator.shared
    @State private var showingSettings = false
    @State private var showingSpaces = false
    @State private var showingVoiceCall = false
    @State private var showingSearch = false
    @State private var showingSessions = false
    @State private var editingMessage: ChatMessage?
    @State private var pendingRegeneration: ChatMessage?
    @State private var pendingHide: ChatMessage?
    @State private var didPositionInitialHistory = false
    @State private var canTriggerOlderHistory = false
    @State private var isPrependingHistory = false

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            if let background = model.backgroundImage {
                GeometryReader { geometry in
                    Image(uiImage: background)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(model.backgroundOpacity)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                topBar
                Divider().overlay(palette.hairline)
                messageList
                ComposerView(model: model)
            }

            if let invite = nativeCalls.ringingInvite {
                NativeIncomingCallOverlay(
                    model: model,
                    invite: invite,
                    onAccept: { presentVoiceCallDirectly() },
                    onDecline: { nativeCalls.declineRingingCall() }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSearch) {
            MessageSearchView(model: model)
        }
        .sheet(isPresented: $showingSessions) {
            SessionManagerView(model: model)
        }
        .sheet(item: $editingMessage) { message in
            EditMessageView(model: model, message: message)
        }
        .fullScreenCover(isPresented: $showingSpaces) {
            SpacesView(model: model)
        }
        .fullScreenCover(isPresented: $showingVoiceCall) {
            VoiceCallView(model: model)
        }
        .onAppear { openAcceptedCallIfNeeded() }
        .onChange(of: nativeCalls.acceptedInvite?.id) { _ in openAcceptedCallIfNeeded() }
        .confirmationDialog(
            "重新生成这条回复？",
            isPresented: Binding(
                get: { pendingRegeneration != nil },
                set: { if !$0 { pendingRegeneration = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("重新生成") {
                guard let message = pendingRegeneration else { return }
                pendingRegeneration = nil
                Task {
                    do { try await model.regenerateMessage(id: message.id) }
                    catch { model.errorMessage = error.localizedDescription }
                }
            }
            Button("取消", role: .cancel) { pendingRegeneration = nil }
        }
        .confirmationDialog(
            "只在这台 iPhone 上隐藏这条消息？",
            isPresented: Binding(
                get: { pendingHide != nil },
                set: { if !$0 { pendingHide = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("隐藏", role: .destructive) {
                guard let message = pendingHide else { return }
                pendingHide = nil
                model.hideMessageLocally(id: message.id)
            }
            Button("取消", role: .cancel) { pendingHide = nil }
        } message: {
            Text("不会删除服务器或对方那边的记录。")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(palette.aiBubble).frame(width: 38, height: 38)
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(palette.accent)
            }

            Button { showingSessions = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(model.peerDisplayName)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                        if model.activeSessionID != AppModel.legacySessionID {
                            Text("· \(model.activeSessionTitle)")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(palette.text)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(model.isStreamConnected ? Color.green.opacity(0.8) : palette.secondaryText)
                            .frame(width: 6, height: 6)
                        Text(model.connectionText)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if model.isLoadingHistory {
                ProgressView().tint(palette.accent)
            }

            Button { showingSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.text)
                    .frame(width: 36, height: 36)
                    .background(palette.composer, in: Circle())
            }

            Button { showingVoiceCall = true } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.text)
                    .frame(width: 38, height: 38)
                    .background(palette.composer, in: Circle())
            }

            Button { showingSpaces = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.text)
                    .frame(width: 38, height: 38)
                    .background(palette.composer, in: Circle())
            }

            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.text)
                    .frame(width: 38, height: 38)
                    .background(palette.composer, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(palette.backgroundTop.opacity(0.82))
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 9) {
                    if canTriggerOlderHistory && model.canLoadOlderHistory {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("载入更早的记录…")
                        }
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .onAppear { prependOlderHistory(using: proxy) }
                    }

                    if model.messages.isEmpty && !model.isLoadingHistory {
                        VStack(spacing: 10) {
                            Image(systemName: "water.waves")
                                .font(.system(size: 28, weight: .light))
                            Text("这里只有你和\(model.peerDisplayName)。\n说点什么吧。")
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(palette.secondaryText)
                        .padding(.top, 120)
                    }

                    ForEach(model.messages) { message in
                        MessageRow(
                            message: message,
                            palette: palette,
                            chatFont: model.chatFont,
                            fontScale: model.fontScale,
                            showsAIAvatar: model.showsAIAvatar,
                            showsHumanAvatar: model.showsHumanAvatar,
                            aiAvatarImage: model.aiAvatarImage,
                            humanAvatarImage: model.humanAvatarImage,
                            showsAIBubble: model.showsAIBubble,
                            aiBubbleColor: model.resolvedAIBubbleColor(default: palette.aiBubble),
                            humanBubbleColor: model.resolvedHumanBubbleColor(default: palette.humanBubble),
                            bubbleOpacity: model.bubbleOpacity,
                            bubbleRadius: model.bubbleRadius,
                            bubbleWidthScale: model.bubbleWidthScale,
                            bubbleBorderWidth: model.bubbleBorderWidth,
                            bubbleStyle: model.bubbleStyle,
                            chatWeight: model.chatWeight,
                            peerName: model.peerDisplayName,
                            showsTimestamp: shouldShowTimestamp(for: message),
                            onToggleStar: {
                                Task {
                                    do {
                                        try await model.setStar(
                                            messageID: message.id,
                                            on: message.meta.starred == nil
                                        )
                                    } catch {
                                        model.errorMessage = error.localizedDescription
                                    }
                                }
                            },
                            onSpeak: {
                                Task { await model.speakMessage(message) }
                            },
                            onCopy: {
                                UIPasteboard.general.string = message.text
                            },
                            onEdit: {
                                editingMessage = message
                            },
                            onRegenerate: {
                                pendingRegeneration = message
                            },
                            onHide: {
                                pendingHide = message
                            },
                            onReact: { emoji in
                                Task {
                                    do { try await model.reactToMessage(messageID: message.id, emoji: emoji) }
                                    catch { model.errorMessage = error.localizedDescription }
                                }
                            },
                            onCompleteTimer: {
                                Task {
                                    do { try await model.completeTimer(messageID: message.id) }
                                    catch { model.errorMessage = error.localizedDescription }
                                }
                            },
                            onAnswerCall: {
                                presentVoiceCallDirectly()
                            },
                            attachmentRequest: model.attachmentRequest
                        )
                        .id(message.id)
                    }

                    if !model.streamingThinking.isEmpty {
                        StreamingProcessRow(
                            title: "Thought process",
                            text: model.streamingThinking,
                            palette: palette,
                            chatFont: model.chatFont,
                            fontScale: model.fontScale,
                            chatWeight: model.chatWeight
                        )
                    }

                    if !model.streamingReply.isEmpty {
                        StreamingReplyRow(
                            text: model.streamingReply,
                            palette: palette,
                            chatFont: model.chatFont,
                            fontScale: model.fontScale,
                            showsAIAvatar: model.showsAIAvatar,
                            aiAvatarImage: model.aiAvatarImage,
                            showsAIBubble: model.showsAIBubble,
                            aiBubbleColor: model.resolvedAIBubbleColor(default: palette.aiBubble),
                            bubbleOpacity: model.bubbleOpacity,
                            bubbleRadius: model.bubbleRadius,
                            bubbleWidthScale: model.bubbleWidthScale,
                            bubbleBorderWidth: model.bubbleBorderWidth,
                            bubbleStyle: model.bubbleStyle,
                            chatWeight: model.chatWeight
                        )
                    } else if model.isTyping {
                        TypingRow(palette: palette)
                    }

                    Color.clear.frame(height: 2).id("chat-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh() }
            .onAppear { positionInitialHistoryIfNeeded(proxy) }
            .onChange(of: model.messages.count) { _ in
                guard !isPrependingHistory else { return }
                if didPositionInitialHistory && !model.isLoadingHistory {
                    scrollToBottom(proxy, animated: true)
                } else {
                    scrollToBottom(proxy, animated: false)
                }
            }
            .onChange(of: model.isLoadingHistory) { loading in
                guard !loading, !model.messages.isEmpty else { return }
                didPositionInitialHistory = true
                settleAtBottom(proxy)
            }
            .onChange(of: model.streamingReply) { _ in scrollToBottom(proxy, animated: false) }
            .onChange(of: model.isTyping) { _ in scrollToBottom(proxy, animated: true) }
            .onChange(of: model.navigationRequest) { request in
                guard let request else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(request.messageID, anchor: .center)
                    }
                }
            }
        }
    }

    private func positionInitialHistoryIfNeeded(_ proxy: ScrollViewProxy) {
        guard !model.messages.isEmpty else { return }
        didPositionInitialHistory = true
        settleAtBottom(proxy)
    }

    private func shouldShowTimestamp(for message: ChatMessage) -> Bool {
        if message.author == .human { return true }
        if message.kind == "thinking" || message.kind == "act" { return false }
        guard let index = model.messages.firstIndex(where: { $0.id == message.id }) else { return true }
        for later in model.messages.indices where later > index {
            let next = model.messages[later]
            if next.kind == "thinking" || next.kind == "act" { continue }
            return next.author != .ai
        }
        return true
    }

    private func settleAtBottom(_ proxy: ScrollViewProxy) {
        scrollToBottom(proxy, animated: false)
        // Lazy rows and authenticated images finish their first layout on later passes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            canTriggerOlderHistory = true
        }
    }

    private func prependOlderHistory(using proxy: ScrollViewProxy) {
        guard !isPrependingHistory, !model.isLoadingOlderHistory else { return }
        isPrependingHistory = true
        Task {
            let anchor = await model.loadOlderHistory()
            DispatchQueue.main.async {
                if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                isPrependingHistory = false
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.24)) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            } else {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    private func openAcceptedCallIfNeeded() {
        guard nativeCalls.acceptedInvite != nil, !showingVoiceCall else { return }
        presentVoiceCallDirectly()
    }

    private func presentVoiceCallDirectly() {
        guard !showingVoiceCall else { return }
        nativeCalls.transitionToInAppCall()
        // Let the incoming overlay / system CallKit surface finish dismissing before
        // asking SwiftUI for a different full-screen presentation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingVoiceCall = true
        }
    }
}

private struct MessageSearchView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ChatMessage] = []
    @State private var isSearching = false
    @State private var isOpening = false
    @State private var errorText: String?

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && results.isEmpty && !isSearching {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                        Text("没有找到相关聊天")
                    }
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 70)
                    .listRowBackground(Color.clear)
                }

                ForEach(results) { message in
                    Button {
                        guard !isOpening else { return }
                        isOpening = true
                        Task {
                            await model.jumpToMessage(message)
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 7) {
                                Text(message.author == .human ? "小雪" : model.peerDisplayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(message.author == .ai ? palette.accent : palette.text)
                                Text(model.sessionTitle(for: message))
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryText)
                                Spacer()
                                Text(Self.shortDate(message.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryText)
                            }
                            Text(message.text.isEmpty ? "[附件]" : message.text)
                                .font(model.chatFont.font(size: 15, weight: model.chatWeight.echoFontWeight))
                                .foregroundStyle(palette.text)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if isSearching { ProgressView("正在搜索…").tint(palette.accent) }
                else if query.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 31, weight: .light))
                        Text("搜索所有窗口里的聊天记录")
                    }
                    .foregroundStyle(palette.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("搜索聊天记录")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "输入关键词")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    results = []
                    isSearching = false
                    return
                }
                isSearching = true
                do {
                    try await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled else { return }
                    results = try await model.searchMessages(trimmed)
                    errorText = nil
                } catch is CancellationError {
                    return
                } catch {
                    results = []
                    errorText = error.localizedDescription
                }
                isSearching = false
            }
            .alert("搜索失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
        .tint(palette.accent)
        .presentationDetents([.large])
    }

    private static func shortDate(_ raw: String) -> String {
        let input = ISO8601DateFormatter()
        input.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = input.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return "" }
        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M月d日"
        return output.string(from: date)
    }
}

private struct SessionManagerView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var renamingSession: APISession?
    @State private var renameText = ""
    @State private var deletingSession: APISession?
    @State private var isCreating = false
    @State private var errorText: String?

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        NavigationStack {
            List {
                Section("对话窗口") {
                    sessionButton(id: AppModel.legacySessionID, title: "旧主线 / Desktop 记录", subtitle: "没有 API 窗口标记的聊天")
                    ForEach(model.sessions) { session in
                        sessionButton(
                            id: session.id,
                            title: session.title,
                            subtitle: "从消息 #\(session.sinceID) 开始"
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deletingSession = session } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                renameText = session.title
                                renamingSession = session
                            } label: {
                                Label("改名", systemImage: "pencil")
                            }
                            .tint(palette.accent)
                        }
                    }
                }

                if model.sessions.isEmpty && !model.isLoadingSessions {
                    Section {
                        Text("API loop 没有开启时，只会显示旧主线；这不影响 Desktop 聊天。")
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }
            .overlay { if model.isLoadingSessions { ProgressView("读取对话窗口…") } }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("对话窗口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard !isCreating else { return }
                        isCreating = true
                        Task {
                            defer { isCreating = false }
                            do {
                                try await model.createSession()
                                dismiss()
                            } catch { errorText = error.localizedDescription }
                        }
                    } label: {
                        if isCreating { ProgressView().controlSize(.small) }
                        else { Image(systemName: "plus") }
                    }
                }
            }
            .task { await model.refreshSessions() }
            .alert("重命名对话", isPresented: Binding(
                get: { renamingSession != nil },
                set: { if !$0 { renamingSession = nil } }
            )) {
                TextField("对话名称", text: $renameText)
                Button("保存") {
                    guard let session = renamingSession else { return }
                    renamingSession = nil
                    Task {
                        do { try await model.renameSession(id: session.id, title: renameText) }
                        catch { errorText = error.localizedDescription }
                    }
                }
                Button("取消", role: .cancel) { renamingSession = nil }
            }
            .confirmationDialog(
                "删除这个对话窗口？",
                isPresented: Binding(
                    get: { deletingSession != nil },
                    set: { if !$0 { deletingSession = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除窗口和其中记录", role: .destructive) {
                    guard let session = deletingSession else { return }
                    deletingSession = nil
                    Task {
                        do { try await model.deleteSession(id: session.id) }
                        catch { errorText = error.localizedDescription }
                    }
                }
                Button("取消", role: .cancel) { deletingSession = nil }
            } message: {
                Text("服务器里的这个 API 窗口及聊天记录会被永久删除。")
            }
            .alert("对话操作失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
        .tint(palette.accent)
        .presentationDetents([.medium, .large])
    }

    private func sessionButton(id: String, title: String, subtitle: String) -> some View {
        Button {
            Task {
                await model.activateSession(id)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(palette.text)
                    Text(subtitle).font(.caption).foregroundStyle(palette.secondaryText)
                }
                Spacer()
                if model.activeSessionID == id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EditMessageView: View {
    @ObservedObject var model: AppModel
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var errorText: String?

    init(model: AppModel, message: ChatMessage) {
        self.model = model
        self.message = message
        _text = State(initialValue: message.text)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(model.chatFont.font(size: 17, weight: model.chatWeight.echoFontWeight))
                .padding(12)
                .navigationTitle("编辑消息")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving { ProgressView().controlSize(.small) }
                        else {
                            Button("保存") {
                                isSaving = true
                                Task {
                                    do {
                                        try await model.editMessage(id: message.id, text: text)
                                        dismiss()
                                    } catch {
                                        isSaving = false
                                        errorText = error.localizedDescription
                                    }
                                }
                            }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .alert("编辑失败", isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )) {
                    Button("好", role: .cancel) { errorText = nil }
                } message: {
                    Text(errorText ?? "")
                }
        }
        .tint(model.theme.palette.accent)
        .presentationDetents([.medium, .large])
    }
}

private struct NativeIncomingCallOverlay: View {
    @ObservedObject var model: AppModel
    let invite: IncomingCallInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    @StateObject private var ringer = IncomingCallRinger()

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.backgroundTop, palette.backgroundBottom, palette.accent.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("incoming call")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.top, 72)

                Spacer()

                Group {
                    if let image = model.aiAvatarImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 45, weight: .light))
                            .foregroundStyle(palette.accent)
                            .background(palette.aiBubble)
                    }
                }
                .frame(width: 134, height: 134)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                .shadow(color: palette.accent.opacity(0.25), radius: 28)
                .scaleEffect(ringer.pulse ? 1.025 : 0.98)

                Text("\(model.peerDisplayName)来电")
                    .font(.system(size: 29, weight: .semibold, design: .serif))
                    .foregroundStyle(palette.text)
                    .padding(.top, 24)
                Text(invite.text)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 10)

                Spacer()

                HStack(spacing: 82) {
                    incomingAction(title: "拒绝", icon: "phone.down.fill", color: .red, action: onDecline)
                    incomingAction(title: "接听", icon: "phone.fill", color: .green, action: onAccept)
                }
                .padding(.bottom, 62)
            }
        }
        .onAppear { ringer.start() }
        .onDisappear { ringer.stop() }
    }

    private func incomingAction(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(color, in: Circle())
                    .shadow(color: color.opacity(0.28), radius: 14, y: 8)
                Text(title).font(.caption).foregroundStyle(palette.text)
            }
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private final class IncomingCallRinger: ObservableObject {
    @Published var pulse = false
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        ring()
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
        timer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { _ in
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func ring() {
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }
}

private struct ComposerView: View {
    @ObservedObject var model: AppModel
    @StateObject private var recorder = VoiceRecorder()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingAttachmentMenu = false
    @State private var showingPhotoPicker = false
    @State private var importingAttachments = false
    @State private var importedTypes: [UTType] = [.item]
    @State private var draftText = ""

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        VStack(spacing: 8) {
            if recorder.isRecording || recorder.hasRecording {
                HStack(spacing: 11) {
                    Button { recorder.cancel() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(palette.secondaryText)

                    HStack(alignment: .center, spacing: 3) {
                        ForEach(0..<18, id: \.self) { index in
                            Capsule()
                                .fill(palette.accent.opacity(0.45 + min(0.5, recorder.level)))
                                .frame(width: 2.5, height: CGFloat(7 + ((index * 5) % 13)) * (0.55 + recorder.level * 0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(formatVoiceTime(recorder.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.secondaryText)

                    Button {
                        sendVoice()
                    } label: {
                        if model.isUploadingVoice {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Label(recorder.isRecording ? "发送" : "发出", systemImage: "arrow.up")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(palette.accent, in: Capsule())
                    .disabled(model.isUploadingVoice)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(palette.composer.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 14)
            }

            if !model.pendingAttachments.isEmpty || model.isUploading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingAttachments) { attachment in
                            HStack(spacing: 7) {
                                Image(systemName: attachmentIcon(attachment))
                                Text(attachment.name).lineLimit(1)
                                Button { model.removePendingAttachment(attachment) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(palette.aiBubble, in: Capsule())
                        }
                        if model.isUploading { ProgressView().tint(palette.accent) }
                    }
                    .padding(.horizontal, 16)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button { showingAttachmentMenu = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 38, height: 38)
                        .background(palette.aiBubble, in: Circle())
                }
                .disabled(model.isUploading)

                TextField("写点什么…", text: $draftText, axis: .vertical)
                    .lineLimit(1...5)
                    .font(model.chatFont.font(size: 16 * model.fontScale, weight: model.chatWeight.echoFontWeight))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(palette.composer, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 19).stroke(palette.hairline))

                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(recorder.isRecording ? Color.white : palette.accent)
                        .frame(width: 38, height: 38)
                        .background(recorder.isRecording ? Color.red.opacity(0.82) : palette.aiBubble, in: Circle())
                }
                .disabled(model.isUploadingVoice)

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 39, height: 39)
                        .background(palette.accent, in: Circle())
                }
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .onDisappear { recorder.cancel() }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await uploadPhotos(items) }
        }
        .confirmationDialog("添加附件", isPresented: $showingAttachmentMenu, titleVisibility: .visible) {
            Button("照片") { presentPhotoPicker() }
            Button("文件") { presentFileImporter(types: [.item]) }
            Button("音乐") { presentFileImporter(types: [.audio]) }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: 9,
            matching: .images
        )
        .fileImporter(
            isPresented: $importingAttachments,
            allowedContentTypes: importedTypes,
            allowsMultipleSelection: true
        ) { result in
            importURLs(result)
        }
    }

    private var canSend: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.pendingAttachments.isEmpty
    }

    private func presentPhotoPicker() {
        // Let the confirmation dialog finish dismissing before presenting a
        // second system controller. Presenting both in the same run-loop turn
        // is silently ignored on some iOS 16/17 builds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingPhotoPicker = true
        }
    }

    private func presentFileImporter(types: [UTType]) {
        importedTypes = types
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            importingAttachments = true
        }
    }

    private func attachmentIcon(_ attachment: Attachment) -> String {
        if attachment.isImage { return "photo" }
        if attachment.mime?.hasPrefix("audio/") == true || attachment.kind == "audio" { return "music.note" }
        return "doc"
    }

    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items.prefix(9) {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                model.errorMessage = "有一张图片没有读出来"
                continue
            }
            let type = item.supportedContentTypes.first ?? .jpeg
            let ext = type.preferredFilenameExtension ?? "jpg"
            await model.uploadAttachment(
                data: data,
                name: "photo-\(UUID().uuidString.prefix(8)).\(ext)",
                mime: type.preferredMIMEType ?? "image/jpeg"
            )
        }
    }

    private func importURLs(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            model.errorMessage = "没有读到附件：\(error.localizedDescription)"
        case .success(let urls):
            Task {
                for url in urls.prefix(9) {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let values = try url.resourceValues(forKeys: [.contentTypeKey])
                        let data = try Data(contentsOf: url, options: .mappedIfSafe)
                        await model.uploadAttachment(
                            data: data,
                            name: url.lastPathComponent,
                            mime: values.contentType?.preferredMIMEType ?? "application/octet-stream"
                        )
                    } catch {
                        model.errorMessage = "附件读取失败：\(url.lastPathComponent)"
                    }
                }
            }
        }
    }

    private func send() {
        guard canSend else { return }
        let text = draftText
        draftText = ""
        Task { await model.sendMessage(text: text) }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.finish()
        } else {
            recorder.cancel()
            Task {
                do { try await recorder.start() }
                catch { model.errorMessage = error.localizedDescription }
            }
        }
    }

    private func sendVoice() {
        if recorder.isRecording { recorder.finish() }
        Task {
            do {
                let result = try recorder.result()
                if await model.sendVoiceRecording(result) { recorder.markSent() }
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func formatVoiceTime(_ value: TimeInterval) -> String {
        let total = max(0, Int(value))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

