import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    let palette: EchoPalette
    let attachmentRequest: (Attachment) -> URLRequest?

    var body: some View {
        if message.kind == "thinking" || message.kind == "act" {
            ProcessRow(message: message, palette: palette)
        } else if message.kind == "call" {
            Text(message.text)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        } else {
            bubble
        }
    }

    private var bubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.author == .human { Spacer(minLength: 56) }

            if message.author == .ai {
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(palette.accent)
                    .frame(width: 25, height: 25)
                    .background(palette.aiBubble, in: Circle())
            }

            VStack(alignment: message.author == .human ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(message.meta.attachments) { attachment in
                        AttachmentView(attachment: attachment, request: attachmentRequest(attachment), palette: palette)
                    }

                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.system(size: 16))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .foregroundStyle(palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.author == .human ? palette.humanBubble : palette.aiBubble,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )

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

            if message.author == .ai { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity)
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
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(message.text)
                .font(.system(size: 13))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "sparkles")
                .font(.caption.weight(.medium))
            Text(text)
                .font(.system(size: 13))
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(palette.accent)
                .frame(width: 25, height: 25)
                .background(palette.aiBubble, in: Circle())
            Text(text)
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(palette.aiBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 44)
        }
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
        } else {
            Label(attachment.name, systemImage: attachment.kind == "audio" ? "waveform" : "doc")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.text)
                .padding(10)
                .background(palette.composer.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
        }
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

