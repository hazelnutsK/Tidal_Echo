import SwiftUI
import UIKit

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
    let chatWeight: Double
    let onToggleStar: () -> Void
    let onSpeak: () -> Void
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
                            Text("小克来电").font(.subheadline.weight(.semibold))
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
                }
                .foregroundStyle(palette.text)
                .padding(.horizontal, message.author == .ai && !showsAIBubble ? 2 : 14)
                .padding(.vertical, 10)
                .frame(maxWidth: CGFloat(280 * bubbleWidthScale), alignment: .leading)
                .background {
                    if message.author == .human || showsAIBubble {
                        RoundedRectangle(cornerRadius: CGFloat(bubbleRadius), style: .continuous)
                            .fill((message.author == .human ? humanBubbleColor : aiBubbleColor).opacity(bubbleOpacity))
                    }
                }
                .overlay {
                    if bubbleBorderWidth > 0 && (message.author == .human || showsAIBubble) {
                        RoundedRectangle(cornerRadius: CGFloat(bubbleRadius), style: .continuous)
                            .stroke(palette.hairline, lineWidth: CGFloat(bubbleBorderWidth))
                    }
                }

                HStack(spacing: 5) {
                    if let reaction = message.meta.reactions[message.author == .human ? "ai" : "human"] {
                        Text(reaction)
                    }
                    if message.author == .human {
                        switch message.delivery {
                        case .sending: Image(systemName: "clock")
                        case .sent: Image(systemName: "checkmark.circle")
                        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.red)
                        }
                    } else {
                        Text(Self.formatTime(message.timestamp))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 3)
            }

            if message.author == .human && showsHumanAvatar {
                AvatarBadge(image: humanAvatarImage, fallback: "person.fill", palette: palette)
            }

            if message.author == .ai { Spacer(minLength: showsAIAvatar ? 44 : 18) }
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            if message.id > 0 {
                Button {
                    onToggleStar()
                } label: {
                    Label(message.meta.starred == nil ? "收藏" : "取消收藏",
                          systemImage: message.meta.starred == nil ? "star" : "star.slash")
                }
            }
            if message.author == .ai && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: onSpeak) {
                    Label("朗读", systemImage: "speaker.wave.2")
                }
            }
        }
    }

    private static func formatTime(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return "" }
        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.timeZone = TimeZone(identifier: "Asia/Shanghai")
        output.dateFormat = "HH:mm"
        return output.string(from: date)
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
                        RoundedRectangle(cornerRadius: CGFloat(bubbleRadius), style: .continuous)
                            .fill(aiBubbleColor.opacity(bubbleOpacity))
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
            Label(attachment.name, systemImage: "doc")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.text)
                .padding(10)
                .background(palette.composer.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
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

                Text(isCurrent && playback.duration > 0 ? voiceTime(playback.duration) : "语音")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .frame(minWidth: 30, alignment: .trailing)
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

