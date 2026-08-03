import SwiftUI
import UIKit
import QuickLook

struct MessageRow: View {
    let message: ChatMessage
    let palette: EchoPalette
    let chatFont: EchoChatFont
    let fontScale: Double
    let showsAIAvatar: Bool
    let showsHumanAvatar: Bool
    let aiAvatarImage: UIImage?
    let humanAvatarImage: UIImage?
    let showsAIBubble: Bool
    let aiBubbleColor: Color
    let humanBubbleColor: Color
    let bubbleOpacity: Double
    let bubbleRadius: Double
    let bubbleWidthScale: Double
    let bubbleBorderWidth: Double
    let bubbleStyle: EchoBubbleStyle
    let chatWeight: Double
    let peerName: String
    let showsTimestamp: Bool
    let onToggleStar: () -> Void
    let onSpeak: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onHide: () -> Void
    let onReact: (String) -> Void
    let onCompleteTimer: () -> Void
    let onAnswerCall: () -> Void
    let attachmentRequest: (Attachment) -> URLRequest?

    var body: some View {
        if message.kind == "thinking" || message.kind == "act" {
            ProcessRow(
                message: message,
                palette: palette,
                chatFont: chatFont,
                fontScale: fontScale,
                chatWeight: chatWeight
            )
        } else if message.kind == "call" {
            if message.author == .ai {
                Button(action: onAnswerCall) {
                    HStack(spacing: 12) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.green, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(peerName)来电").font(.subheadline.weight(.semibold))
                            Text(message.text).font(.caption).lineLimit(2)
                        }
                        .foregroundStyle(palette.text)
                        Spacer()
                        Text("接听")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .padding(12)
                    .background(palette.composer.opacity(0.86), in: RoundedRectangle(cornerRadius: 17))
                    .padding(.horizontal, 28)
                }
                .buttonStyle(.plain)
            } else {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
        } else {
            bubble
        }
    }

    private var bubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.author == .human { Spacer(minLength: 56) }

            if message.author == .ai && showsAIAvatar {
                AvatarBadge(image: aiAvatarImage, fallback: "sparkle", palette: palette)
            }

            VStack(alignment: message.author == .human ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(message.meta.attachments) { attachment in
                        AttachmentView(attachment: attachment, request: attachmentRequest(attachment), palette: palette)
                    }

                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(chatFont.font(size: 16 * fontScale, weight: chatWeight.echoFontWeight))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }

                    if let timer = message.meta.timer {
                        MessageTimerCard(
                            timer: timer,
                            palette: palette,
                            onDone: onCompleteTimer
                        )
                    }
                }
                .foregroundStyle(palette.text)
                .padding(.horizontal, message.author == .ai && !showsAIBubble ? 2 : 14)
                .padding(.vertical, 10)
                .frame(maxWidth: CGFloat(280 * bubbleWidthScale), alignment: .leading)
                .background { bubbleBackground }
                .overlay {
                    if bubbleBorderWidth > 0 && (message.author == .human || showsAIBubble) {
                        RoundedRectangle(cornerRadius: CGFloat(bubbleRadius), style: .continuous)
                            .stroke(palette.hairline, lineWidth: CGFloat(bubbleBorderWidth))
                    }
                }

                if let reaction = displayedReaction, !reaction.isEmpty {
                    Text(reaction)
                        .font(.system(size: 17))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(palette.hairline))
                        .padding(.top, -7)
                        .transition(.scale.combined(with: .opacity))
                }

                if shouldShowMetaLine {
                    HStack(spacing: 5) {
                        if message.meta.edited && message.delivery == .sent {
                            Text("已编辑")
                        }
                        if message.author == .human {
                            switch message.delivery {
                            case .sending:
                                Image(systemName: "clock")
                            case .failed:
                                Label("未送达", systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(Color.red)
                            case .sent:
                                Text(Self.formatTime(message.timestamp))
                            }
                        } else if showsTimestamp {
                            Text(Self.formatTime(message.timestamp))
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, 3)
                }
            }

            if message.author == .human && showsHumanAvatar {
                AvatarBadge(image: humanAvatarImage, fallback: "person.fill", palette: palette)
            }

            if message.author == .ai { Spacer(minLength: showsAIAvatar ? 44 : 18) }
        }
        .frame(maxWidth: .infinity)
        .contextMenu { messageActions }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.author == .human || showsAIBubble {
            let shape = RoundedRectangle(cornerRadius: CGFloat(bubbleRadius), style: .continuous)
            let color = message.author == .human ? humanBubbleColor : aiBubbleColor
            if bubbleStyle == .frosted {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(color.opacity(max(0.1, bubbleOpacity * 0.32))))
            } else {
                shape.fill(color.opacity(bubbleOpacity))
            }
        }
    }

    private var displayedReaction: String? {
        message.meta.reactions[message.author == .human ? "ai" : "human"]
    }

    private var myReaction: String? {
        message.meta.reactions["human"]
    }

    private var shouldShowMetaLine: Bool {
        message.author == .human || showsTimestamp || message.meta.edited
    }

    @ViewBuilder
    private var messageActions: some View {
        if !message.text.isEmpty {
            Button(action: onCopy) { Label("复制", systemImage: "doc.on.doc") }
        }
        if message.id > 0 {
            if message.author == .ai {
                Menu {
                    ForEach(["❤️", "😘", "😂", "🥺", "🔥", "👀"], id: \.self) { emoji in
                        Button(emoji) { onReact(emoji) }
                    }
                    if myReaction != nil {
                        Divider()
                        Button("收回回应", role: .destructive) { onReact("") }
                    }
                } label: {
                    Label("表情回应", systemImage: "face.smiling")
                }
            }
            Button(action: onToggleStar) {
                Label(message.meta.starred == nil ? "收藏" : "取消收藏",
                      systemImage: message.meta.starred == nil ? "star" : "star.slash")
            }
        }
        if message.author == .ai && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button(action: onSpeak) { Label("朗读", systemImage: "speaker.wave.2") }
        }
        if message.id > 0 && message.author == .human && (message.kind == "user" || message.kind == "voice") {
            Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
        }
        if message.id > 0 && message.author == .ai && message.kind == "reply" {
            Button(action: onRegenerate) { Label("重新生成", systemImage: "arrow.clockwise") }
        }
        Button(role: .destructive, action: onHide) {
            Label("在本机隐藏", systemImage: "eye.slash")
        }
    }

    private static func formatTime(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return "" }
        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        let zone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        output.timeZone = zone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        if calendar.isDateInToday(date) {
            output.dateFormat = "HH:mm"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            output.dateFormat = "M月d日 HH:mm"
        } else {
            output.dateFormat = "yyyy年M月d日 HH:mm"
        }
        return output.string(from: date)
    }
}

private struct MessageTimerCard: View {
    let timer: MessageTimer
    let palette: EchoPalette
    let onDone: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = secondsRemaining(at: context.date)
            HStack(spacing: 10) {
                Image(systemName: timer.status == "done" ? "checkmark.circle.fill" : "timer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(timer.status == "done" ? Color.green : palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(timer.label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    if timer.status == "running" && remaining > 0 {
                        Text(Self.durationText(remaining))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(palette.accent)
                    } else if timer.status == "done" {
                        Text("✓ 搞定").font(.caption).foregroundStyle(Color.green)
                    } else {
                        Text("时间到").font(.caption).foregroundStyle(Color.red.opacity(0.82))
                    }
                }
                Spacer(minLength: 8)
                if timer.status == "running" && remaining > 0 {
                    Button("搞定了", action: onDone)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                }
            }
            .padding(11)
            .background(palette.composer.opacity(0.62), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.hairline))
        }
    }

    private func secondsRemaining(at date: Date) -> Int {
        guard let end = Self.parseDate(timer.endsAt) else { return 0 }
        return max(0, Int(end.timeIntervalSince(date).rounded()))
    }

    private static func parseDate(_ raw: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static func durationText(_ total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ProcessRow: View {
    let message: ChatMessage
    let palette: EchoPalette
    let chatFont: EchoChatFont
    let fontScale: Double
    let chatWeight: Double
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(message.text)
                .font(chatFont.font(size: 13 * fontScale, weight: chatWeight.echoFontWeight))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: message.kind == "thinking" ? "sparkles" : "wrench.and.screwdriver")
                Text(message.kind == "thinking" ? "Thought process" : "Action")
            }
            .font(.system(size: 12, weight: .medium))
        }
        .tint(palette.accent)
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(palette.composer.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.leading, 34)
        .padding(.trailing, 60)
    }
}

struct StreamingProcessRow: View {
    let title: String
    let text: String
    let palette: EchoPalette
    let chatFont: EchoChatFont
    let fontScale: Double
    let chatWeight: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "sparkles")
                .font(.caption.weight(.medium))
            Text(text)
                .font(chatFont.font(size: 13 * fontScale, weight: chatWeight.echoFontWeight))
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .foregroundStyle(palette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.composer.opacity(0.60), in: RoundedRectangle(cornerRadius: 14))
        .padding(.leading, 34)
        .padding(.trailing, 60)
    }
}

struct StreamingReplyRow: View {
    let text: String
    let palette: EchoPalette
    let chatFont: EchoChatFont
    let fontScale: Double
    let showsAIAvatar: Bool
    let aiAvatarImage: UIImage?
    let showsAIBubble: Bool
    let aiBubbleColor: Color
    let bubbleOpacity: Double
    let bubbleRadius: Double
    let bubbleWidthScale: Double
    let bubbleBorderWidth: Double
    let bubbleStyle: EchoBubbleStyle
    let chatWeight: Double

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showsAIAvatar {
                AvatarBadge(image: aiAvatarImage, fallback: "sparkle", palette: palette)
            }
            Text(text)
                .font(chatFont.font(size: 16 * fontScale, weight: chatWeight.echoFontWeight))
                .lineSpacing(4)
                .foregroundStyle(palette.text)
                .padding(.horizontal, showsAIBubble ? 14 : 2)
                .padding(.vertical, 10)
                .frame(maxWidth: CGFloat(280 * bubbleWidthScale), alignment: .leading)
                .background {
                    if showsAIBubble {
                        let shape = RoundedRectangle(cornerRadius: CGFloat(bubbleRadius), style: .continuous)
                        if bubbleStyle == .frosted {
                            shape
                                .fill(.ultraThinMaterial)
                                .overlay(shape.fill(aiBubbleColor.opacity(max(0.1, bubbleOpacity * 0.32))))
                        } else {
                            shape.fill(aiBubbleColor.opacity(bubbleOpacity))
                        }
                    }
                }
                .overlay {
                    if showsAIBubble && bubbleBorderWidth > 0 {
                        RoundedRectangle(cornerRadius: CGFloat(bubbleRadius), style: .continuous)
                            .stroke(palette.hairline, lineWidth: CGFloat(bubbleBorderWidth))
                    }
                }
            Spacer(minLength: showsAIAvatar ? 44 : 18)
        }
    }
}

private struct AvatarBadge: View {
    let image: UIImage?
    let fallback: String
    let palette: EchoPalette

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallback)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(palette.accent)
                    .background(palette.aiBubble)
            }
        }
        .frame(width: 27, height: 27)
        .clipShape(Circle())
        .overlay(Circle().stroke(palette.hairline))
    }
}

struct TypingRow: View {
    let palette: EchoPalette
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(palette.accent)
                .frame(width: 25, height: 25)
                .background(palette.aiBubble, in: Circle())
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(palette.secondaryText)
                        .frame(width: 5, height: 5)
                        .opacity(pulse ? 0.35 + Double(index) * 0.25 : 0.9 - Double(index) * 0.22)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 35)
            .background(palette.aiBubble, in: Capsule())
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private struct AttachmentView: View {
    let attachment: Attachment
    let request: URLRequest?
    let palette: EchoPalette

    var body: some View {
        if attachment.isImage {
            AuthenticatedImageView(request: request, palette: palette)
                .frame(maxWidth: 260, minHeight: 120, maxHeight: 330)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else if attachment.kind == "audio" || attachment.mime?.hasPrefix("audio/") == true {
            VoiceAttachmentView(attachment: attachment, request: request, palette: palette)
        } else {
            AuthenticatedFileView(attachment: attachment, request: request, palette: palette)
        }
    }
}

private struct PreviewFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct AuthenticatedFileView: View {
    let attachment: Attachment
    let request: URLRequest?
    let palette: EchoPalette
    @State private var preview: PreviewFile?
    @State private var isLoading = false

    var body: some View {
        Button {
            guard !isLoading, let request else { return }
            isLoading = true
            Task {
                defer { isLoading = false }
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TidalEchoPreviews", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let safeName = attachment.name.replacingOccurrences(of: "/", with: "-")
                    let url = folder.appendingPathComponent("\(UUID().uuidString.prefix(8))-\(safeName)")
                    try data.write(to: url, options: .atomic)
                    preview = PreviewFile(url: url)
                } catch {
                    // The parent message remains readable even when this attachment cannot be downloaded.
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
                    .frame(width: 34, height: 34)
                    .background(palette.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                    if let size = attachment.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                Spacer(minLength: 6)
                if isLoading { ProgressView().controlSize(.small) }
                else { Image(systemName: "eye").foregroundStyle(palette.secondaryText) }
            }
            .foregroundStyle(palette.text)
            .padding(10)
            .background(palette.composer.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .sheet(item: $preview) { item in
            QuickLookPreview(url: item.url)
                .ignoresSafeArea()
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct VoiceAttachmentView: View {
    let attachment: Attachment
    let request: URLRequest?
    let palette: EchoPalette
    @ObservedObject private var playback = VoicePlaybackCenter.shared

    private var isCurrent: Bool { playback.currentID == attachment.id }

    var body: some View {
        Button {
            guard let request else { return }
            Task { await playback.toggle(id: attachment.id, request: request) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(palette.accent.opacity(0.15))
                    if isCurrent && playback.isLoading {
                        ProgressView().controlSize(.small).tint(palette.accent)
                    } else {
                        Image(systemName: isCurrent && playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.accent)
                    }
                }
                .frame(width: 32, height: 32)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        HStack(alignment: .center, spacing: 2) {
                            ForEach(0..<22, id: \.self) { index in
                                Capsule()
                                    .fill(palette.secondaryText.opacity(0.34))
                                    .frame(width: 2, height: CGFloat(7 + ((index * 7) % 12)))
                            }
                        }
                        .frame(maxHeight: .infinity)
                        if isCurrent {
                            Rectangle()
                                .fill(palette.accent.opacity(0.34))
                                .frame(width: geometry.size.width * playback.progress)
                                .blendMode(.sourceAtop)
                        }
                    }
                }
                .frame(width: 86, height: 24)

                Text(playbackLabel)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .frame(minWidth: 30, maxWidth: 92, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(palette.composer.opacity(0.72), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func voiceTime(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var playbackLabel: String {
        if isCurrent && playback.duration > 0 { return voiceTime(playback.duration) }
        if attachment.voice == true || attachment.name.lowercased().contains("voice") { return "语音" }
        return attachment.name
    }
}

@MainActor
private final class AuthenticatedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var failed = false

    func load(_ request: URLRequest?) async {
        guard let request else { failed = true; return }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                failed = true
                return
            }
            self.image = image
            failed = false
        } catch {
            failed = true
        }
    }
}

private struct AuthenticatedImageView: View {
    let request: URLRequest?
    let palette: EchoPalette
    @StateObject private var loader = AuthenticatedImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if loader.failed {
                Label("图片加载失败", systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ProgressView()
                    .tint(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .background(palette.composer.opacity(0.45))
        .task(id: request?.url?.absoluteString) { await loader.load(request) }
    }
}

