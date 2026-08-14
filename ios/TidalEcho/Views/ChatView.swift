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
    @State private var askSheetContext: AskSheetContext?
    @State private var seenAskMessageIDs = Set<Int>()
    @State private var didPrimeAskAutopresentation = false
    @State private var editingMessage: ChatMessage?
    @State private var pendingRegeneration: ChatMessage?
    @State private var pendingHide: ChatMessage?
    @State private var didPositionInitialHistory = false
    @State private var canTriggerOlderHistory = false
    @State private var isPrependingHistory = false
    @State private var composerHeight: CGFloat = 126
    @State private var isAtBottom = true
    @State private var chatScrollView: UIScrollView?

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            if let background = model.visibleBackgroundImage {
                GeometryReader { geometry in
                    Image(uiImage: background)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(1 + model.backgroundBlur / 260)
                        .blur(radius: model.backgroundBlur)
                        .clipped()
                        .opacity(model.backgroundOpacity)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            ZStack(alignment: .top) {
                messageList
                topFog
                topBar

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ComposerView(
                        model: model,
                        onShowSessions: { showingSessions = true }
                    )
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ComposerHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        }
                }
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
            SettingsView(
                model: model,
                onSearch: { showingSearch = true },
                onCall: { showingVoiceCall = true }
            )
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSearch) {
            MessageSearchView(model: model)
        }
        .sheet(item: $askSheetContext) { context in
            MessageAskSheet(model: model, context: context)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
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
        .onAppear {
            openAcceptedCallIfNeeded()
            primeAskAutopresentationIfNeeded()
        }
        .onPreferenceChange(ComposerHeightPreferenceKey.self) { height in
            if height > 0 { composerHeight = height }
        }
        .onChange(of: nativeCalls.acceptedInvite?.id) { _ in openAcceptedCallIfNeeded() }
        .onChange(of: model.isLoadingHistory) { loading in
            if loading {
                didPrimeAskAutopresentation = false
            } else {
                primeAskAutopresentationIfNeeded()
            }
        }
        .onChange(of: newestUnansweredAskID) { _ in
            presentNewestAskIfNeeded()
        }
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
            headerButton(icon: "slider.horizontal.3", size: 17) { showingSettings = true }

            Spacer(minLength: 6)

            if model.isLoadingHistory {
                ProgressView()
                    .controlSize(.small)
                    .tint(palette.accent)
            }

            HStack(spacing: 14) {
                headerButton(icon: "phone.fill", size: 15) { showingVoiceCall = true }
                headerButton(icon: "square.grid.2x2", size: 16) { showingSpaces = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 8)
    }

    private var topFog: some View {
        ZStack {
            VariableBackdropBlur(
                radius: 16,
                mask: .blurredTopClearBottom,
                fadeFrom: 0.25,
                fadeTo: 0.65
            )

            VariableBackdropBlur(
                radius: 3,
                mask: .blurredTopClearBottom,
                fadeFrom: 0.50,
                fadeTo: 0.88
            )

            Rectangle()
                .fill(topFogTint)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.78), location: 0.42),
                            .init(color: .clear, location: 0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(height: 120)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func headerGlass<S: InsettableShape>(shape: S) -> some View {
        ZStack {
            VariableBackdropBlur(radius: 18, mask: .solid)
            shape.fill(headerGlassTint)
        }
        .clipShape(shape)
        .overlay(shape.stroke(headerGlassRing, lineWidth: 0.65))
        .shadow(color: headerShadowColor, radius: model.theme == .paper ? 10 : 11, y: 3.5)
    }

    private func headerButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(palette.text)
                .frame(width: 32, height: 32)
                .background { headerGlass(shape: Circle()) }
        }
        .buttonStyle(.plain)
    }

    private var headerGlassTint: Color {
        switch model.theme {
        case .mist: return Color(hex: 0xF7FAFC).opacity(0.52)
        case .paper: return Color(hex: 0xF0EEE6).opacity(0.62)
        case .harbor: return Color(hex: 0x1C2A35).opacity(0.56)
        }
    }

    private var headerGlassRing: Color {
        switch model.theme {
        case .mist: return Color.white.opacity(0.48)
        case .paper: return Color.white.opacity(0.48)
        case .harbor: return Color.white.opacity(0.12)
        }
    }

    private var headerShadowColor: Color {
        switch model.theme {
        case .mist: return Color.black.opacity(0.10)
        case .paper: return Color(hex: 0x8C7466).opacity(0.16)
        case .harbor: return Color.black.opacity(0.18)
        }
    }

    private var topFogTint: Color {
        switch model.theme {
        case .mist: return Color(hex: 0xECF1F6).opacity(0.24)
        case .paper: return Color(hex: 0xFAFAF8).opacity(0.72)
        case .harbor: return Color(hex: 0x15212D).opacity(0.38)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
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
                            bubbleShapeStyle: model.bubbleShapeStyle,
                            liquidGlass: model.liquidGlassSettings,
                            chatWeight: model.chatWeight,
                            peerName: model.peerDisplayName,
                            showsTimestamp: shouldShowTimestamp(for: message),
                            isGroupStart: isBubbleGroupStart(message),
                            isTail: isBubbleTail(message),
                            isGroupedWithPrevious: isGroupedWithPrevious(message),
                            isPaper: model.theme == .paper,
                            isMist: model.theme == .mist,
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
                            onOpenAsk: {
                                guard let ask = message.meta.ask else { return }
                                askSheetContext = AskSheetContext(messageID: message.id, initialAsk: ask)
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
                            isPaper: model.theme == .paper,
                            isMist: model.theme == .mist,
                            showsAIAvatar: model.showsAIAvatar,
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
                            bubbleShapeStyle: model.bubbleShapeStyle,
                            liquidGlass: model.liquidGlassSettings,
                            chatWeight: model.chatWeight
                        )
                    } else if model.isTyping {
                        TypingRow(
                            palette: palette,
                            showsAIAvatar: model.showsAIAvatar,
                            aiAvatarImage: model.aiAvatarImage
                        )
                    }

                        Color.clear
                            .frame(height: 2)
                            .id("chat-bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .background {
                        ScrollViewResolver { resolved in
                            if chatScrollView !== resolved { chatScrollView = resolved }
                        }
                        .frame(width: 0, height: 0)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: 76)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: composerHeight)
                }
                // Extend under the device chrome, but keep the keyboard safe area.
                // Ignoring all bottom safe areas made the last bubble scroll behind
                // the raised composer with no reachable space below it.
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await model.refresh() }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height <= geometry.containerSize.height
                        || geometry.visibleRect.maxY >= geometry.contentSize.height - 56
                } action: { _, nextValue in
                    if nextValue != isAtBottom { isAtBottom = nextValue }
                }
                .onAppear { positionInitialHistoryIfNeeded(proxy) }
                .onChange(of: model.messages.count) { _ in
                    guard !isPrependingHistory else { return }
                    guard didPositionInitialHistory else {
                        guard !model.isLoadingHistory, !model.messages.isEmpty else { return }
                        didPositionInitialHistory = true
                        settleAtBottom(proxy)
                        return
                    }
                    guard !model.isLoadingHistory else { return }
                    let sentByMe = model.messages.last?.author == .human
                    guard isAtBottom || sentByMe else { return }
                    scrollToBottom(proxy, animated: true)
                }
                .onChange(of: model.isLoadingHistory) { loading in
                    guard !loading, !model.messages.isEmpty else { return }
                    guard !didPositionInitialHistory else { return }
                    didPositionInitialHistory = true
                    settleAtBottom(proxy)
                }
                .onChange(of: model.streamingReply) { _ in
                    if isAtBottom { scrollToBottom(proxy, animated: false) }
                }
                .onChange(of: model.isTyping) { _ in
                    if isAtBottom { scrollToBottom(proxy, animated: true) }
                }
                .onChange(of: viewport.size.height) { _ in
                    guard isAtBottom else { return }
                    scrollToBottom(proxy, animated: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        scrollToBottom(proxy, animated: false)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    // Match the PWA: focusing the composer opens enough scrollable
                    // room and settles the latest bubble above the keyboard.
                    isAtBottom = true
                    scrollToBottom(proxy, animated: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        scrollToBottom(proxy, animated: false)
                    }
                }
                .onChange(of: model.navigationRequest) { request in
                    guard let request else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(request.messageID, anchor: .center)
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isAtBottom {
                        Button {
                            jumpToBottom(proxy)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(palette.hairline, lineWidth: 0.5))
                                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.bottom, composerHeight + 12)
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                        .accessibilityLabel("回到最新消息")
                    }
                }
                .animation(.easeOut(duration: 0.18), value: isAtBottom)
            }
        }
    }

    private func positionInitialHistoryIfNeeded(_ proxy: ScrollViewProxy) {
        guard !model.isLoadingHistory, !model.messages.isEmpty else { return }
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
            // Short-chat parts created from one reply share the exact source
            // timestamp. Hide only those intermediate timestamps; a later
            // autonomous send has its own timestamp even without a human reply.
            return next.author != .ai || next.timestamp != message.timestamp
        }
        return true
    }

    private var newestUnansweredAskID: Int? {
        model.messages.last(where: {
            $0.id > 0 && $0.meta.ask != nil && $0.meta.ask?.answer == nil
        })?.id
    }

    private func primeAskAutopresentationIfNeeded() {
        guard !model.isLoadingHistory, !didPrimeAskAutopresentation else { return }
        seenAskMessageIDs = Set(model.messages.compactMap { message in
            message.meta.ask == nil ? nil : message.id
        })
        didPrimeAskAutopresentation = true
    }

    private func presentNewestAskIfNeeded() {
        guard !model.isLoadingHistory else { return }
        guard didPrimeAskAutopresentation else {
            primeAskAutopresentationIfNeeded()
            return
        }
        guard let message = model.messages.last(where: {
            $0.id > 0 && $0.meta.ask != nil && $0.meta.ask?.answer == nil
        }), let ask = message.meta.ask,
              !seenAskMessageIDs.contains(message.id) else { return }
        seenAskMessageIDs.insert(message.id)
        askSheetContext = AskSheetContext(messageID: message.id, initialAsk: ask)
    }

    private func isBubbleGroupStart(_ message: ChatMessage) -> Bool {
        guard let index = model.messages.firstIndex(where: { $0.id == message.id }), index > 0 else {
            return true
        }
        return !messagesShareBubbleGroup(model.messages[index - 1], message)
    }

    private func isGroupedWithPrevious(_ message: ChatMessage) -> Bool {
        !isBubbleGroupStart(message)
    }

    private func isBubbleTail(_ message: ChatMessage) -> Bool {
        guard message.kind != "thinking", message.kind != "act",
              let index = model.messages.firstIndex(where: { $0.id == message.id }),
              model.messages.indices.contains(index + 1) else { return true }
        return !messagesShareBubbleGroup(message, model.messages[index + 1])
    }

    private func messagesShareBubbleGroup(_ first: ChatMessage, _ second: ChatMessage) -> Bool {
        guard first.kind != "thinking", first.kind != "act",
              second.kind != "thinking", second.kind != "act",
              first.author == second.author,
              let date = Self.messageDate(first.timestamp),
              let nextDate = Self.messageDate(second.timestamp) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        guard calendar.isDate(date, inSameDayAs: nextDate) else { return false }
        let interval = nextDate.timeIntervalSince(date)
        return interval >= 0 && interval < 5 * 60
    }

    private static func messageDate(_ raw: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private func settleAtBottom(_ proxy: ScrollViewProxy) {
        scrollToBottom(proxy, animated: false)
        // Lazy rows and authenticated images finish their first layout on later passes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            scrollToBottom(proxy, animated: false)
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
        guard let scrollView = chatScrollView else {
            DispatchQueue.main.async {
                if animated {
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            return
        }
        let distance = abs(bottomOffset(for: scrollView) - scrollView.contentOffset.y)
        let shouldAnimate = animated && distance <= max(scrollView.bounds.height * 1.8, 900)
        setExactBottom(on: scrollView, animated: shouldAnimate)
    }

    private func jumpToBottom(_ proxy: ScrollViewProxy) {
        guard let scrollView = chatScrollView else {
            scrollToBottom(proxy, animated: false)
            return
        }

        scrollView.layoutIfNeeded()
        let destination = bottomOffset(for: scrollView)
        let distance = abs(destination - scrollView.contentOffset.y)
        let shouldAnimate = distance <= max(scrollView.bounds.height * 1.8, 900)
        setExactBottom(on: scrollView, animated: shouldAnimate)

        // Lazy rows can refine their heights after a long jump. Re-read the
        // real UIKit content size and settle again instead of trusting an
        // estimated SwiftUI row position.
        for delay in [0.10, 0.32] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard chatScrollView === scrollView else { return }
                setExactBottom(on: scrollView, animated: false)
            }
        }
    }

    private func setExactBottom(on scrollView: UIScrollView, animated: Bool) {
        scrollView.layoutIfNeeded()
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: bottomOffset(for: scrollView)),
            animated: animated
        )
    }

    private func bottomOffset(for scrollView: UIScrollView) -> CGFloat {
        max(
            -scrollView.adjustedContentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
    }

    private struct ScrollViewResolver: UIViewRepresentable {
        let onResolve: (UIScrollView) -> Void

        func makeUIView(context: Context) -> UIView {
            let view = UIView(frame: .zero)
            resolve(from: view)
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            resolve(from: uiView)
        }

        private func resolve(from view: UIView) {
            DispatchQueue.main.async {
                var candidate = view.superview
                while let current = candidate {
                    if let scrollView = current as? UIScrollView {
                        onResolve(scrollView)
                        return
                    }
                    candidate = current.superview
                }
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

private struct AskSheetContext: Identifiable {
    let messageID: Int
    let initialAsk: MessageAsk
    var id: Int { messageID }
}

private struct MessageAskSheet: View {
    @ObservedObject var model: AppModel
    let context: AskSheetContext
    @Environment(\.dismiss) private var dismiss
    @State private var freeText = ""
    @State private var isSubmitting = false
    @State private var errorText: String?
    @FocusState private var freeAnswerFocused: Bool

    private var palette: EchoPalette { model.theme.palette }
    private var accentForeground: Color {
        model.theme == .harbor ? Color(hex: 0x15212D) : .white
    }
    private var ask: MessageAsk {
        model.messages.first(where: { $0.id == context.messageID })?.meta.ask ?? context.initialAsk
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text("ALTAIR 在问")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(palette.accent)
                            .padding(.top, 5)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.secondaryText)
                                .frame(width: 32, height: 32)
                                .background(palette.composer.opacity(0.82), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭")
                    }

                    Text(ask.question)
                        .font(model.chatFont.font(size: 17 * model.fontScale, numericWeight: max(450, model.chatWeight)))
                        .foregroundStyle(palette.text)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                        .padding(.bottom, 15)

                    VStack(spacing: 0) {
                        ForEach(Array(ask.options.enumerated()), id: \.offset) { index, option in
                            Button { submit(index: index) } label: {
                                HStack(spacing: 12) {
                                    Text(letter(for: index))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(isPicked(index) ? accentForeground : palette.secondaryText)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            isPicked(index) ? palette.accent : palette.composer,
                                            in: Circle()
                                        )
                                    Text(option)
                                        .font(model.chatFont.font(size: 15 * model.fontScale, numericWeight: model.chatWeight))
                                        .foregroundStyle(palette.text)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 8)
                                    Image(systemName: isPicked(index) ? "checkmark" : "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(isPicked(index) ? palette.accent : palette.secondaryText)
                                }
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(ask.answer != nil || isSubmitting)
                            .opacity(ask.answer == nil || isPicked(index) ? 1 : 0.42)

                            Divider().overlay(palette.hairline)
                        }
                    }

                    if let answer = ask.answer {
                        Text(answer.kind == "free" ? "你自己答的：「\(answer.text)」" : "答过了，不许改口。")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondaryText)
                            .padding(.top, 16)
                    } else {
                        HStack(spacing: 9) {
                            TextField("自己胡说一个答案…", text: $freeText)
                                .font(model.chatFont.font(size: 14 * model.fontScale, numericWeight: model.chatWeight))
                                .foregroundStyle(palette.text)
                                .focused($freeAnswerFocused)
                                .submitLabel(.send)
                                .onSubmit { submitFreeAnswer() }
                                .padding(.horizontal, 15)
                                .frame(height: 42)
                                .background(palette.composer.opacity(0.82), in: Capsule())
                                .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.6))

                            Button { submitFreeAnswer() } label: {
                                if isSubmitting {
                                    ProgressView().controlSize(.small).tint(accentForeground)
                                } else {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 15, weight: .bold))
                                }
                            }
                            .foregroundStyle(accentForeground)
                            .frame(width: 42, height: 42)
                            .background(palette.accent, in: Circle())
                            .disabled(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                            .opacity(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background {
                if model.theme == .mist {
                    Color.white.ignoresSafeArea()
                } else {
                    palette.background.ignoresSafeArea()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(model.theme.preferredColorScheme)
        .alert("没答上", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "请再试一次。")
        }
    }

    private func letter(for index: Int) -> String {
        let letters = Array("ABCDEF")
        return letters.indices.contains(index) ? String(letters[index]) : String(index + 1)
    }

    private func isPicked(_ index: Int) -> Bool {
        ask.answer?.kind == "pick" && ask.answer?.index == index
    }

    private func submitFreeAnswer() {
        let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        submit(text: String(text.prefix(200)))
    }

    private func submit(index: Int? = nil, text: String? = nil) {
        guard ask.answer == nil, !isSubmitting else { return }
        isSubmitting = true
        freeAnswerFocused = false
        Task {
            do {
                try await model.answerAsk(messageID: context.messageID, index: index, text: text)
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
            }
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
                    errorText = nil
                    return
                }
                let searchedQuery = trimmed
                isSearching = true
                errorText = nil
                do {
                    try await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled else { return }
                    let nextResults = try await model.searchMessages(searchedQuery)
                    guard !Task.isCancelled,
                          query.trimmingCharacters(in: .whitespacesAndNewlines) == searchedQuery else { return }
                    results = nextResults
                    errorText = nil
                } catch is CancellationError {
                    return
                } catch let error as URLError where error.code == .cancelled {
                    return
                } catch {
                    guard query.trimmingCharacters(in: .whitespacesAndNewlines) == searchedQuery else { return }
                    results = []
                    errorText = error.localizedDescription
                }
                if query.trimmingCharacters(in: .whitespacesAndNewlines) == searchedQuery {
                    isSearching = false
                }
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
                    sessionButton(id: AppModel.legacySessionID, title: "Claude Code", subtitle: "Claude Code / Desktop 会话记录")
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
                        Text("API loop 没有开启时，只会显示 Claude Code；这不影响 Desktop 聊天。")
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

private struct ComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 126

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ComposerView: View {
    @ObservedObject var model: AppModel
    let onShowSessions: () -> Void
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
                .padding(.horizontal, 2)
                .padding(.vertical, 6)
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
                    .padding(.horizontal, 2)
                }
            }

            TextField("和Altair说话…", text: $draftText, axis: .vertical)
                .lineLimit(1...5)
                .font(model.chatFont.font(
                    size: PWAChatMetrics.composerFontSize(for: model.chatFont) * model.fontScale,
                    numericWeight: model.chatWeight
                ))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 4)
                .padding(.top, 3)
                .padding(.bottom, 2)

            HStack(alignment: .center, spacing: 9) {
                Button { showingAttachmentMenu = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(composerAuxiliaryForeground)
                        .frame(width: 38, height: 38)
                        .background(composerAuxiliaryBackground, in: Circle())
                }
                .disabled(model.isUploading)

                Button(action: onShowSessions) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(model.isStreamConnected ? Color.green.opacity(0.86) : palette.secondaryText.opacity(0.72))
                            .frame(width: 7, height: 7)
                        Text(model.activeSessionTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(composerAuxiliaryBackground.opacity(0.86), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "切换对话窗口，当前为 \(model.activeSessionTitle)，\(model.isStreamConnected ? "在线" : "离线")"
                )

                Spacer(minLength: 0)

                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(recorder.isRecording ? Color.white : composerAuxiliaryForeground)
                        .frame(width: 38, height: 38)
                        .background(
                            recorder.isRecording ? Color.red.opacity(0.82) : composerAuxiliaryBackground,
                            in: Circle()
                        )
                }
                .disabled(model.isUploadingVoice)

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white.opacity(canSend ? 1 : 0.72))
                        .frame(width: 39, height: 39)
                        .background(composerSendBackground.opacity(canSend ? 1 : 0.34), in: Circle())
                }
                .disabled(!canSend)
            }
        }
        .padding(12)
        .background { composerContainerGlass }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
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

    private var composerContainerGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 29, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(palette.composer.opacity(model.theme == .paper ? 0.58 : 0.42)))
            .overlay(shape.stroke(Color.white.opacity(model.theme == .harbor ? 0.13 : 0.42), lineWidth: 0.7))
            .overlay(shape.stroke(palette.hairline, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 5)
    }

    private var composerAuxiliaryBackground: Color {
        model.theme == .paper ? Color(hex: 0xF0EEE6) : palette.aiBubble
    }

    private var composerAuxiliaryForeground: Color {
        model.theme == .paper ? Color(hex: 0x2B2A27) : palette.accent
    }

    private var composerSendBackground: Color {
        model.theme == .paper ? Color(hex: 0x2B2A27) : palette.accent
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
        if attachment.isAudio { return "music.note" }
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

