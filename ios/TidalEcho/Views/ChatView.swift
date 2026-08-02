import AudioToolbox
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var nativeCalls = NativeCallCoordinator.shared
    @State private var showingSettings = false
    @State private var showingSpaces = false
    @State private var showingVoiceCall = false
    @State private var didPositionInitialHistory = false

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
                    onAccept: { nativeCalls.acceptRingingCall() },
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
        .fullScreenCover(isPresented: $showingSpaces) {
            SpacesView(model: model)
        }
        .fullScreenCover(isPresented: $showingVoiceCall) {
            VoiceCallView(model: model)
        }
        .onAppear { openAcceptedCallIfNeeded() }
        .onChange(of: nativeCalls.acceptedInvite?.id) { _ in openAcceptedCallIfNeeded() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(palette.aiBubble).frame(width: 38, height: 38)
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(palette.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("小克")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
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

            Spacer()

            if model.isLoadingHistory {
                ProgressView().tint(palette.accent)
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
                    if model.messages.isEmpty && !model.isLoadingHistory {
                        VStack(spacing: 10) {
                            Image(systemName: "water.waves")
                                .font(.system(size: 28, weight: .light))
                            Text("这里只有你和小克。\n说点什么吧。")
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
                            chatWeight: model.chatWeight,
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
        }
    }

    private func positionInitialHistoryIfNeeded(_ proxy: ScrollViewProxy) {
        guard !model.messages.isEmpty else { return }
        didPositionInitialHistory = true
        settleAtBottom(proxy)
    }

    private func settleAtBottom(_ proxy: ScrollViewProxy) {
        scrollToBottom(proxy, animated: false)
        // Lazy rows and authenticated images finish their first layout on later passes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
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
        showingVoiceCall = true
        nativeCalls.consumeAcceptedInvite()
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

                Text("小克来电")
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
    @State private var photoItem: PhotosPickerItem?
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
                                Image(systemName: "photo")
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
                PhotosPicker(selection: $photoItem, matching: .images) {
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
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                defer { photoItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    model.errorMessage = "没有读到这张图片"
                    return
                }
                let type = item.supportedContentTypes.first ?? .jpeg
                let ext = type.preferredFilenameExtension ?? "jpg"
                await model.uploadImage(
                    data: data,
                    name: "photo-\(UUID().uuidString.prefix(8)).\(ext)",
                    mime: type.preferredMIMEType ?? "image/jpeg"
                )
            }
        }
    }

    private var canSend: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.pendingAttachments.isEmpty
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

