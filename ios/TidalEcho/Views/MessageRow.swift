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
    let liquidGlass: LiquidGlassSettings
    let chatWeight: Double
    let peerName: String
    let showsTimestamp: Bool
    let isTail: Bool
    let isPaper: Bool
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
                chatWeight: chatWeight,
                isPaper: isPaper,
                showsAIAvatar: showsAIAvatar,
                bubbleWidthScale: bubbleWidthScale
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
                        MarkdownMessageText(
                            source: message.text,
                            palette: palette,
                            chatFont: chatFont,
                            fontScale: fontScale,
                            chatWeight: chatWeight
                        )
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
                .padding(.horizontal, message.author == .ai && !showsAIBubble ? 2 : 13)
                .padding(.vertical, 9)
                .background { bubbleBackground }
                .overlay {
                    if bubbleBorderWidth > 0 && (message.author == .human || showsAIBubble) {
                        if bubbleStyle == .liquid {
                            RoundedRectangle(cornerRadius: CGFloat(bubbleRadius), style: .continuous)
                                .stroke(palette.hairline, lineWidth: CGFloat(bubbleBorderWidth))
                        } else {
                            bubbleShape
                                .stroke(palette.hairline, lineWidth: CGFloat(bubbleBorderWidth))
                        }
                    }
                }
                // Constrain wrapping without painting the background across the
                // whole max-width frame. Short messages keep their intrinsic width.
                .frame(
                    maxWidth: message.author == .ai && !showsAIBubble
                        ? .infinity
                        : CGFloat(280 * bubbleWidthScale),
                    alignment: message.author == .human ? .trailing : .leading
                )

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
                                SendingClock()
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

            if message.author == .ai && showsAIBubble {
                Spacer(minLength: showsAIAvatar ? 44 : 18)
            }
        }
        .frame(maxWidth: .infinity)
        .contextMenu { messageActions }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.author == .human || showsAIBubble {
            let color = message.author == .human ? humanBubbleColor : aiBubbleColor
            if bubbleStyle == .liquid {
                LiquidGlassBubbleBackground(
                    tint: color,
                    tintOpacity: bubbleOpacity,
                    radius: CGFloat(bubbleRadius),
                    settings: liquidGlass
                )
            } else {
                let shape = bubbleShape
                if bubbleStyle == .frosted {
                    shape
                        .fill(.ultraThinMaterial)
                        // Keep backdrop sampling at full strength. The slider controls
                        // only the color wash, so zero still looks like real glass.
                        .overlay(shape.fill(color.opacity(bubbleOpacity * 0.55)))
                        .shadow(color: Color.black.opacity(0.04), radius: 9, y: 3)
                } else {
                    shape
                        .fill(color.opacity(bubbleOpacity))
                        .shadow(color: Color.black.opacity(0.045 * bubbleOpacity), radius: 4.5, y: 2)
                }
            }
        }
    }

    private var bubbleShape: PWAChatBubbleShape {
        PWAChatBubbleShape(
            radius: CGFloat(bubbleRadius),
            bottomLeftRadius: message.author == .ai ? 5 : CGFloat(bubbleRadius),
            bottomRightRadius: message.author == .human && isTail ? 5 : CGFloat(bubbleRadius)
        )
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
            output.dateFormat = "M/d HH:mm"
        } else {
            output.dateFormat = "yyyy/M/d HH:mm"
        }
        return output.string(from: date)
    }
}

private struct MarkdownMessageText: View {
    let source: String
    let palette: EchoPalette
    let chatFont: EchoChatFont
    let fontScale: Double
    let chatWeight: Double

    var body: some View {
        Text(attributedText)
            .lineSpacing(PWAChatMetrics.lineSpacing(
                font: chatFont,
                size: PWAChatMetrics.bubbleFontSize(for: chatFont) * fontScale
            ))
            .textSelection(.enabled)
    }

    private var attributedText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            // SwiftUI Text does not lay out Markdown block presentation intents;
            // `.full` therefore collapsed the overflow paragraphs in short-chat's
            // fifth bubble. Preserve whitespace while still parsing inline markup.
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var value = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        let size = PWAChatMetrics.bubbleFontSize(for: chatFont) * fontScale
        value.font = chatFont.font(size: size, numericWeight: chatWeight)
        value.foregroundColor = palette.text

        let runs = value.runs.map { ($0.range, $0.inlinePresentationIntent) }
        for (range, intent) in runs {
            guard let intent else { continue }
            var font = chatFont.font(
                size: size,
                numericWeight: intent.contains(.stronglyEmphasized) ? 700 : chatWeight
            )
            if intent.contains(.emphasized) { font = font.italic() }
            if intent.contains(.code) {
                font = .system(size: CGFloat(size * 0.92), weight: .regular, design: .monospaced)
                value[range].backgroundColor = palette.composer.opacity(0.72)
            }
            value[range].font = font
            if intent.contains(.strikethrough) {
                value[range].strikethroughStyle = .single
            }
        }
        return value
    }
}

private struct SendingClock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: "clock")
            .rotationEffect(.degrees(rotation))
            .onAppear {
                guard !reduceMotion else { return }
                rotation = 360
            }
            .animation(
                reduceMotion ? nil : .linear(duration: 1.15).repeatForever(autoreverses: false),
                value: rotation
            )
            .accessibilityLabel("发送中")
    }
}

/// CSS-like independent corner radii. PWA gives the last bubble in a same-author
/// five-minute group a 5px corner toward the avatar; the other corners use the
/// user-selected radius (14px by default on iPhone).
private struct PWAChatBubbleShape: Shape {
    let radius: CGFloat
    let bottomLeftRadius: CGFloat
    let bottomRightRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let topLeft = min(max(0, radius), limit)
        let topRight = topLeft
        let bottomRight = min(max(0, bottomRightRadius), limit)
        let bottomLeft = min(max(0, bottomLeftRadius), limit)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
            radius: topRight,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
            radius: bottomRight,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
            radius: bottomLeft,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(
            center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
            radius: topLeft,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
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
    let isPaper: Bool
    let showsAIAvatar: Bool
    let bubbleWidthScale: Double
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard canExpand else { return }
                withAnimation(.easeOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    if isThinking {
                        Text("THINKING")
                        Image(systemName: "play.fill")
                            .font(.system(size: 7.5, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    } else {
                        Image(systemName: "wrench")
                            .font(.system(size: 11, weight: .medium))
                        Text(toolTitle)
                    }
                }
                .font(chatFont.font(size: 12.5 * fontScale, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, isPaper ? 0 : 11)
                .padding(.vertical, isPaper ? 2 : 4)
                .background {
                    if !isPaper {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
                    }
                }
            }
            .buttonStyle(.plain)

            if expanded {
                processDetail
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: CGFloat(280 * bubbleWidthScale), alignment: .leading)
        .padding(.leading, showsAIAvatar ? 35 : 0)
        .padding(.trailing, 44)
    }

    private var isThinking: Bool { message.kind == "thinking" }
    private var canExpand: Bool { isThinking ? !message.text.isEmpty : !message.meta.steps.isEmpty }

    private var toolTitle: String {
        let title = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "他做了点什么" }
        return title.hasPrefix("他") ? title : "他(title)"
    }

    @ViewBuilder
    private var processDetail: some View {
        Group {
            if isThinking {
                Text(message.text)
                    .font(chatFont.font(
                        size: PWAChatMetrics.thinkingFontSize(for: chatFont) * fontScale,
                        numericWeight: chatWeight
                    ).italic())
                    .lineSpacing(PWAChatMetrics.lineSpacing(
                        font: chatFont,
                        size: PWAChatMetrics.thinkingFontSize(for: chatFont) * fontScale
                    ))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(message.meta.steps.enumerated()), id: \.offset) { _, step in
                        ToolStepPreview(step: step, palette: palette)
                    }
                }
            }
        }
        .foregroundStyle(palette.secondaryText)
        .italic(isPaper)
        .padding(.leading, isPaper ? 15 : 12)
        .padding(.trailing, isPaper ? 2 : 12)
        .padding(.vertical, isPaper ? 2 : 10)
        .background {
            if !isPaper {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.hairline))
            }
        }
        .overlay(alignment: .leading) {
            if isPaper {
                Rectangle()
                    .fill(Color(hex: 0xD6D4CE))
                    .frame(width: 1.5)
            }
        }
    }
}

private struct ToolStepPreview: View {
    let step: ToolStep
    let palette: EchoPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            previewLine("tool", step.tool, monospaced: false, limit: 1)
            previewLine("cmd", step.cmd, monospaced: true, limit: 5)
            previewLine("result", step.result, monospaced: true, limit: 4)
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private func previewLine(_ key: String, _ value: String?, monospaced: Bool, limit: Int) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 3) {
                Text("\(key):")
                    .foregroundStyle(palette.secondaryText.opacity(0.76))
                Text(value)
                    .font(monospaced ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                    .foregroundStyle(palette.text.opacity(0.78))
                    .lineLimit(limit)
                    .textSelection(.enabled)
            }
        }
    }
}

struct StreamingProcessRow: View {
    let title: String
    let text: String
    let palette: EchoPalette
    let isPaper: Bool
    let showsAIAvatar: Bool
    let chatFont: EchoChatFont
    let fontScale: Double
    let chatWeight: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("THINKING")
                Image(systemName: "play.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .rotationEffect(.degrees(90))
            }
            .font(chatFont.font(size: 12.5 * fontScale, weight: .medium))
            .padding(.horizontal, isPaper ? 0 : 11)
            .padding(.vertical, isPaper ? 2 : 4)
            .background {
                if !isPaper {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
                }
            }

            Text(text)
                .font(chatFont.font(
                    size: PWAChatMetrics.thinkingFontSize(for: chatFont) * fontScale,
                    numericWeight: chatWeight
                ).italic())
                .lineLimit(4)
                .lineSpacing(PWAChatMetrics.lineSpacing(
                    font: chatFont,
                    size: PWAChatMetrics.thinkingFontSize(for: chatFont) * fontScale
                ))
                .textSelection(.enabled)
                .padding(.leading, isPaper ? 15 : 12)
                .padding(.trailing, isPaper ? 2 : 12)
                .padding(.vertical, isPaper ? 2 : 10)
                .background {
                    if !isPaper {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.hairline))
                    }
                }
                .overlay(alignment: .leading) {
                    if isPaper {
                        Rectangle().fill(Color(hex: 0xD6D4CE)).frame(width: 1.5)
                    }
                }
        }
        .foregroundStyle(palette.secondaryText)
        .frame(maxWidth: 280, alignment: .leading)
        .padding(.leading, showsAIAvatar ? 35 : 0)
        .padding(.trailing, 44)
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
    let liquidGlass: LiquidGlassSettings
    let chatWeight: Double

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showsAIAvatar {
                AvatarBadge(image: aiAvatarImage, fallback: "sparkle", palette: palette)
            }
            Text(text)
                .font(chatFont.font(
                    size: PWAChatMetrics.bubbleFontSize(for: chatFont) * fontScale,
                    numericWeight: chatWeight
                ))
                .lineSpacing(PWAChatMetrics.lineSpacing(
                    font: chatFont,
                    size: PWAChatMetrics.bubbleFontSize(for: chatFont) * fontScale
                ))
                .foregroundStyle(palette.text)
                .padding(.horizontal, showsAIBubble ? 13 : 2)
                .padding(.vertical, 9)
                .background {
                    if showsAIBubble {
                        if bubbleStyle == .liquid {
                            LiquidGlassBubbleBackground(
                                tint: aiBubbleColor,
                                tintOpacity: bubbleOpacity,
                                radius: CGFloat(bubbleRadius),
                                settings: liquidGlass
                            )
                        } else {
                            let shape = PWAChatBubbleShape(
                                radius: CGFloat(bubbleRadius),
                                bottomLeftRadius: 5,
                                bottomRightRadius: CGFloat(bubbleRadius)
                            )
                            if bubbleStyle == .frosted {
                                shape
                                    .fill(.ultraThinMaterial)
                                    .overlay(shape.fill(aiBubbleColor.opacity(bubbleOpacity * 0.55)))
                                    .shadow(color: Color.black.opacity(0.04), radius: 9, y: 3)
                            } else {
                                shape
                                    .fill(aiBubbleColor.opacity(bubbleOpacity))
                                    .shadow(color: Color.black.opacity(0.045 * bubbleOpacity), radius: 4.5, y: 2)
                            }
                        }
                    }
                }
                .overlay {
                    if showsAIBubble && bubbleBorderWidth > 0 {
                        if bubbleStyle == .liquid {
                            RoundedRectangle(cornerRadius: CGFloat(bubbleRadius), style: .continuous)
                                .stroke(palette.hairline, lineWidth: CGFloat(bubbleBorderWidth))
                        } else {
                            PWAChatBubbleShape(
                                radius: CGFloat(bubbleRadius),
                                bottomLeftRadius: 5,
                                bottomRightRadius: CGFloat(bubbleRadius)
                            )
                                .stroke(palette.hairline, lineWidth: CGFloat(bubbleBorderWidth))
                        }
                    }
                }
                .frame(
                    maxWidth: showsAIBubble ? CGFloat(280 * bubbleWidthScale) : .infinity,
                    alignment: .leading
                )
            if showsAIBubble { Spacer(minLength: showsAIAvatar ? 44 : 18) }
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
    let showsAIAvatar: Bool
    let aiAvatarImage: UIImage?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            if showsAIAvatar {
                AvatarBadge(image: aiAvatarImage, fallback: "sparkle", palette: palette)
            }
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
    @State private var previewImage: ImagePreviewItem?

    var body: some View {
        Group {
            if let image = loader.image {
                Button {
                    previewImage = ImagePreviewItem(image: image)
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开图片预览")
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
        .fullScreenCover(item: $previewImage) { item in
            FullScreenImagePreview(image: item.image)
        }
    }
}

struct LiquidGlassBubbleBackground: View {
    let tint: Color
    let tintOpacity: Double
    let radius: CGFloat
    let settings: LiquidGlassSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let strength = clamped(settings.strength / 100)
            let dispersion = clamped(settings.dispersion)
            let rim = clamped(settings.rimWidth)
            let magnify = clamped(settings.magnify)
            let blur = clamped(settings.blur)
            let lens = CGFloat(max(60, settings.size))
            let rimLine = CGFloat(0.55 + rim * 3.6)

            ZStack {
                if reduceTransparency {
                    shape.fill(tint.opacity(0.42 + tintOpacity * 0.38))
                } else {
                    shape.fill(.ultraThinMaterial)
                }

                shape.fill(tint.opacity((0.05 + (1 - blur) * 0.18) * tintOpacity))

                Ellipse()
                    .fill(RadialGradient(
                        colors: [
                            Color.white.opacity(0.30 + strength * 0.24),
                            Color.white.opacity(0.07 + magnify * 0.10),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: lens * 0.46
                    ))
                    .frame(width: lens * CGFloat(1 + magnify * 0.18), height: lens * 0.62)
                    .position(
                        x: geometry.size.width * CGFloat(0.22 + strength * 0.16),
                        y: geometry.size.height * CGFloat(0.08 + magnify * 0.16)
                    )
                    .blur(radius: CGFloat(1 + blur * 5))
                    .blendMode(.screen)

                Ellipse()
                    .fill(LinearGradient(
                        colors: [
                            Color.white.opacity(0.22 * strength),
                            tint.opacity(0.07),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: lens * 0.82, height: lens * 0.34)
                    .rotationEffect(.degrees(-16 + strength * 12))
                    .position(x: geometry.size.width * 0.78, y: geometry.size.height * 0.88)
                    .blur(radius: CGFloat(2 + blur * 7))
                    .blendMode(.plusLighter)

                shape
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.cyan.opacity(0.78),
                                Color.white.opacity(0.92),
                                Color.pink.opacity(0.72),
                                Color.yellow.opacity(0.54),
                                Color.cyan.opacity(0.78)
                            ],
                            center: .center
                        ),
                        lineWidth: rimLine * CGFloat(1.1 + dispersion)
                    )
                    .blur(radius: CGFloat(0.25 + dispersion * 1.15))
                    .opacity(0.08 + dispersion * 0.46)
                    .offset(x: CGFloat(dispersion * 0.7), y: CGFloat(dispersion * 0.35))
            }
            .clipShape(shape)
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.82),
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.58),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: rimLine
                )
            )
            .overlay(
                shape
                    .inset(by: max(1, rimLine))
                    .stroke(Color.white.opacity(0.10 + strength * 0.18), lineWidth: 0.7)
            )
            .scaleEffect(CGFloat(1 + magnify * 0.012))
            .shadow(
                color: Color.black.opacity(0.05 + strength * 0.035),
                radius: CGFloat(7 + blur * 7),
                y: 3
            )
        }
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

private struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct FullScreenImagePreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale = 1.0
    @State private var settledScale = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(settledScale * value, 1), 5)
                        }
                        .onEnded { _ in
                            settledScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scale = scale > 1 ? 1 : 2
                        settledScale = scale
                    }
                }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 14)
            .accessibilityLabel("关闭图片预览")
        }
        .statusBarHidden()
    }
}

