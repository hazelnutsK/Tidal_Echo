import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings = false

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().overlay(palette.hairline)
                messageList
                ComposerView(model: model)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
                .presentationDetents([.medium, .large])
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
                            attachmentRequest: model.attachmentRequest
                        )
                        .id(message.id)
                    }

                    if !model.streamingThinking.isEmpty {
                        StreamingProcessRow(title: "Thought process", text: model.streamingThinking, palette: palette)
                    }

                    if !model.streamingReply.isEmpty {
                        StreamingReplyRow(text: model.streamingReply, palette: palette)
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
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: model.messages.count) { _ in scrollToBottom(proxy, animated: true) }
            .onChange(of: model.streamingReply) { _ in scrollToBottom(proxy, animated: false) }
            .onChange(of: model.isTyping) { _ in scrollToBottom(proxy, animated: true) }
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
}

private struct ComposerView: View {
    @ObservedObject var model: AppModel
    @State private var photoItem: PhotosPickerItem?

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        VStack(spacing: 8) {
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

                TextField("写点什么…", text: $model.draftText, axis: .vertical)
                    .lineLimit(1...5)
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(palette.composer, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 19).stroke(palette.hairline))

                Button {
                    Task { await model.sendCurrentMessage() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 39, height: 39)
                        .background(palette.accent, in: Circle())
                }
                .disabled(model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingAttachments.isEmpty)
                .opacity((model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingAttachments.isEmpty) ? 0.45 : 1)
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
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
}

