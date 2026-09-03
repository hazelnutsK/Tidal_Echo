import SwiftUI
import UIKit
import QuickLook

private enum CallLifecycleEvent: Equatable {
    case started
    case ended
    case missed

    var icon: String {
        switch self {
        case .started: return "phone"
        case .ended: return "phone.down"
        case .missed: return "phone.down.fill"
        }
    }

    var title: String {
        switch self {
        case .started: return "语音通话开启"
        case .ended: return "语音通话结束"
        case .missed: return "未接来电"
        }
    }
}

private struct CallLifecycleEventRow: View {
    let event: CallLifecycleEvent
    let palette: EchoPalette
    let fontScale: Double

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: event.icon)
            Text(event.title)
        }
        .font(.system(size: CGFloat(13 * fontScale), weight: .medium))
        .foregroundStyle(event == .missed ? Color.red : palette.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private enum IncomingCallCardState: Equatable {
    case ringing
    case missed
    case ended

    var icon: String {
        switch self {
        case .ringing: return "phone.fill"
        case .missed: return "phone.down.fill"
        case .ended: return "phone.down"
        }
    }

    var color: Color {
        switch self {
        case .ringing: return .green
        case .missed: return .red
        case .ended: return .gray
        }
    }

    func subtitle(_ fallback: String) -> String {
        switch self {
        case .ringing: return fallback
        case .missed: return "未接听"
        case .ended: return "通话已结束"
        }
    }

    func accessibilityLabel(peerName: String) -> String {
        switch self {
        case .ringing: return "\(peerName)来电，接听"
        case .missed: return "\(peerName)未接来电"
        case .ended: return "\(peerName)通话已结束"
        }
    }
}

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
    let aiBubbleTextColor: Color
    let humanBubbleTextColor: Color
    let bubbleOpacity: Double
    let bubbleRadius: Double
    let bubbleWidthScale: Double
    let bubbleBorderWidth: Double
    let bubbleStyle: EchoBubbleStyle
    let bubbleShapeStyle: EchoBubbleShapeStyle
    let liquidGlass: LiquidGlassSettings
    let chatWeight: Double
    let peerName: String
    let showsTimestamp: Bool
    let isGroupStart: Bool
    let isTail: Bool
    let isGroupedWithPrevious: Bool
    let isPaper: Bool
    let isMist: Bool
    let isIncomingCallActive: Bool
    let onToggleStar: () -> Void
    let onSpeak: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onHide: () -> Void
    let onReact: (String) -> Void
    let onCompleteTimer: () -> Void
    let onOpenAsk: () -> Void
    let onAnswerCall: () -> Void
    let attachmentRequest: (Attachment) -> URLRequest?

    var body: some View {
        Group {
            if let event = callLifecycleEvent {
                CallLifecycleEventRow(event: event, palette: palette, fontScale: fontScale)
            } else if message.kind == "thinking" || message.kind == "act" {
                ProcessRow(
                    message: message,
                    palette: palette,
                    chatFont: chatFont,
                    fontScale: fontScale,
                    chatWeight: chatWeight,
                    isPaper: isPaper,
                    isMist: isMist,
                    showsAIAvatar: showsAIAvatar,
                    bubbleWidthScale: bubbleWidthScale
                )
            } else if message.kind == "call" {
                if message.author == .ai {
                    if incomingCallCardState == .ringing {
                        Button(action: onAnswerCall) {
                            incomingCallCard(state: .ringing)
                        }
                        .buttonStyle(.plain)
                    } else {
                        incomingCallCard(state: incomingCallCardState)
                    }
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
        .padding(.top, usesCompactGroupSpacing && isGroupedWithPrevious ? -6 : 0)
    }

    private var callLifecycleEvent: CallLifecycleEvent? {
        guard message.kind == "call" else { return nil }
        if message.text.contains("[call_start]") {
            return .started
        }
        if message.text.contains("[call_end]") {
            return .ended
        }
        if message.text.contains("[call_missed]") {
            return .missed
        }
        return nil
    }

    private var incomingCallCardState: IncomingCallCardState {
        if message.meta.callStatus == "missed" { return .missed }
        return isIncomingCallActive ? .ringing : .ended
    }

    private func incomingCallCard(state: IncomingCallCardState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(state.color, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(state == .missed ? "\(peerName)未接来电" : "\(peerName)来电")
                    .font(.subheadline.weight(.semibold))
                Text(state.subtitle(message.text))
                    .font(.caption)
                    .lineLimit(2)
            }
            .foregroundStyle(state == .missed ? Color.red : palette.text)
            Spacer()
            if state == .ringing {
                Text("接听")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(12)
        .background(palette.composer.opacity(0.86), in: RoundedRectangle(cornerRadius: 17))
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.accessibilityLabel(peerName: peerName))
    }

    private var bubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.author == .human { Spacer(minLength: 56) }

            if message.author == .ai && showsAIAvatar {
                AvatarBadge(image: aiAvatarImage, fallback: "sparkle", palette: palette)
            }

            VStack(alignment: message.author == .human ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 9) {
                    if imageAttachments.count > 1 {
                        PhotoStackAttachmentView(
                            attachments: imageAttachments,
                            request: attachmentRequest,
                            palette: palette
                        )
                    } else if let image = imageAttachments.first {
                        AttachmentView(
                            attachment: image,
                            request: attachmentRequest(image),
                            palette: palette
                        )
                    }

                    ForEach(nonImageAttachments) { attachment in
                        AttachmentView(
                            attachment: attachment,
                            request: attachmentRequest(attachment),
                            palette: palette
                        )
                    }

                    if !displayedMessageText.isEmpty {
                        MarkdownMessageText(
                            source: displayedMessageText,
                            palette: palette,
                            textColor: resolvedBubbleTextColor,
                            chatFont: chatFont,
                            fontScale: fontScale,
                            chatWeight: chatWeight
                        )
                    }

                    if let card = message.meta.xhs {
                        XHSNoteCard(
                            card: card,
                            palette: palette,
                            fontScale: fontScale,
                            request: attachmentRequest
                        )
                    }

                    if let timer = message.meta.timer {
                        MessageTimerCard(
                            timer: timer,
                            palette: palette,
                            onDone: onCompleteTimer
                        )
                    }

                    if let ask = message.meta.ask {
                        MessageAskChip(ask: ask, palette: palette, onOpen: onOpenAsk)
                    }

                    if !message.meta.album.isEmpty {
                        MessageAlbumChip(entries: message.meta.album, palette: palette)
                    }
                }
                .foregroundStyle(resolvedBubbleTextColor)
                .padding(.horizontal, message.author == .ai && !showsAIBubble ? 2 : bubbleHorizontalPadding)
                .padding(.vertical, bubbleVerticalPadding)
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
                        : resolvedBubbleMaxWidth,
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
                Spacer(minLength: 0)
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
                    FrostedGlassBubbleBackground(
                        shape: shape,
                        tint: color,
                        tintOpacity: bubbleOpacity
                    )
                } else {
                    shape
                        .fill(color.opacity(bubbleOpacity))
                        .shadow(color: Color.black.opacity(0.045 * bubbleOpacity), radius: 4.5, y: 2)
                }
            }
        }
    }

    private var bubbleShape: EchoMessageBubbleShape {
        EchoMessageBubbleShape(
            style: bubbleShapeStyle,
            author: message.author,
            radius: CGFloat(bubbleRadius),
            isGroupStart: isGroupStart,
            isTail: isTail
        )
    }

    private var resolvedBubbleTextColor: Color {
        message.author == .ai ? aiBubbleTextColor : humanBubbleTextColor
    }

    private var resolvedBubbleMaxWidth: CGFloat {
        let scale = CGFloat(bubbleWidthScale)
        if message.author == .ai {
            // Above 100%, grow in screen-friendly point increments so 120% and
            // 130% remain visibly distinct instead of both hitting the old spacer.
            return scale <= 1 ? 280 * scale : 280 + ((scale - 1) * 140)
        }
        return 280 * min(scale, 1.2)
    }

    private var usesCompactGroupSpacing: Bool {
        bubbleShapeStyle == .telegram
            && (bubbleStyle == .classic || bubbleStyle == .frosted)
    }

    private var usesTelegramShape: Bool {
        bubbleShapeStyle == .telegram && usesCompactGroupSpacing
    }

    private var bubbleHorizontalPadding: CGFloat { usesTelegramShape ? 10 : 13 }
    private var bubbleVerticalPadding: CGFloat { usesTelegramShape ? 8 : 9 }

    private var displayedMessageText: String {
        guard message.kind == "voice" else { return message.text }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["🎙️", "🎤", "🎙"] where text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private var displayedReaction: String? {
        message.meta.reactions[message.author == .human ? "ai" : "human"]
    }

    /// 小红书笔记的配图归预览卡管，从普通附件里摘掉（不然图会出现两次）。
    private var ownAttachments: [Attachment] {
        message.meta.attachments.filter { !$0.isXHS }
    }

    private var imageAttachments: [Attachment] {
        ownAttachments.filter(\.isImage)
    }

    private var nonImageAttachments: [Attachment] {
        ownAttachments.filter { !$0.isImage }
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
        EchoDateCache.bubbleTimeLabel(raw)
    }
}

struct MarkdownMessageText: View {
    let source: String
    let palette: EchoPalette
    let textColor: Color
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
        // Parsing Markdown and walking its runs is the single most expensive
        // thing a bubble does, and SwiftUI re-evaluates this body on any
        // ancestor change. Memoise per (text, styling) so scrolling back over
        // an already-seen bubble costs a dictionary lookup.
        let key = MarkdownStyleKey(
            source: source,
            chatFont: chatFont,
            fontScale: fontScale,
            chatWeight: chatWeight,
            textColor: textColor,
            codeBackground: palette.composer
        )
        if let cached = MarkdownRenderCache.shared.value(for: key) { return cached }
        let rendered = renderAttributedText()
        MarkdownRenderCache.shared.store(rendered, for: key)
        return rendered
    }

    private func renderAttributedText() -> AttributedString {
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
        value.foregroundColor = textColor

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

private struct MessageAlbumChip: View {
    let entries: [MessageAlbumEntry]
    let palette: EchoPalette

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 30, height: 30)
                .background(palette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(entries.count > 1 ? "收进相册 · \(entries.count) 张" : "收进相册")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Text(displayTitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(palette.secondaryText.opacity(0.72))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(palette.composer.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entries.count > 1 ? "已收进相册 \(entries.count) 张照片" : "已收进相册，\(displayTitle)")
    }

    private var displayTitle: String {
        let title = entries.first?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? (entries.count > 1 ? "这些照片" : "这张照片") : title
    }
}

/// 小红书预览卡：她丢来一条链接，relay 把那篇笔记读回来了（backend/xhs.py）。
/// 抓的那两三秒里先立一张骨架，抓完原地换成真卡；点一下去小红书看原文。
/// 笔记配图挂在卡上（MessageRow 已把它们从普通附件里摘掉），不再单独铺一排。
private struct XHSNoteCard: View {
    let card: XHSCard
    let palette: EchoPalette
    let fontScale: Double
    let request: (Attachment) -> URLRequest?

    @Environment(\.openURL) private var openURL
    @State private var pulse = false

    private let cardWidth: CGFloat = 252
    private let radius: CGFloat = 15
    private var coverHeight: CGFloat { cardWidth * 0.625 }
    private var brand: Color { Color(hex: 0xFF3C5A) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            VStack(alignment: .leading, spacing: 5) {
                if card.isLoading {
                    skeletonLine(width: cardWidth - 22)
                    skeletonLine(width: (cardWidth - 22) * 0.58)
                } else {
                    Text(displayTitle)
                        .font(.system(size: CGFloat(13.5 * fontScale), weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                    if let desc = displayDesc {
                        Text(desc)
                            .font(.system(size: CGFloat(12 * fontScale)))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(3)
                    }
                }
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.top, 9)
            .padding(.bottom, 10)
        }
        .frame(width: cardWidth)
        .background(palette.composer.opacity(0.72), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(brand.opacity(0.24), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .onTapGesture {
            if let link = card.link { openURL(link) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.isLoading ? "正在读取小红书笔记" : "小红书笔记：\(displayTitle)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var cover: some View {
        if card.isLoading {
            Rectangle()
                .fill(palette.hairline.opacity(0.55))
                .frame(width: cardWidth, height: coverHeight)
                .opacity(pulse ? 0.5 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
                }
        } else if let first = card.images.first {
            ZStack(alignment: .bottomTrailing) {
                AuthenticatedImageView(
                    request: request(Attachment(url: first, name: "小红书配图", kind: "image")),
                    palette: palette,
                    contentMode: .fill,
                    allowsPreview: false   // 点卡片是去看原文，别被图片预览截胡
                )
                .frame(width: cardWidth, height: coverHeight)
                .clipped()
                if totalImages > 1 {
                    Text("🖼 \(totalImages)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(8)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("小红书")
                .font(.system(size: CGFloat(11 * fontScale), weight: .semibold))
                .foregroundStyle(brand)
            if card.isLoading {
                Text("正在读这篇笔记…")
                    .font(.system(size: CGFloat(11 * fontScale)))
                    .foregroundStyle(palette.secondaryText)
            } else if !card.isReady {
                Text("点开看原文")
                    .font(.system(size: CGFloat(11 * fontScale)))
                    .foregroundStyle(palette.secondaryText)
            } else {
                if let who = trimmed(card.author) {
                    Text(who)
                        .font(.system(size: CGFloat(11 * fontScale)))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let stats = statsLine {
                    Text(stats)
                        .font(.system(size: CGFloat(11 * fontScale)))
                        .foregroundStyle(palette.secondaryText.opacity(0.85))
                        .fixedSize()
                }
            }
        }
        .padding(.top, 3)
    }

    private func skeletonLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(palette.hairline.opacity(0.55))
            .frame(width: width, height: 11)
            .opacity(pulse ? 0.5 : 1)
    }

    private var totalImages: Int { max(card.imageCount ?? card.images.count, card.images.count) }

    private var displayTitle: String {
        guard card.isReady else { return "这篇笔记没读到" }
        return trimmed(card.title) ?? "无标题笔记"
    }

    private var displayDesc: String? {
        guard card.isReady else { return nil }
        return trimmed(card.desc)
    }

    private var statsLine: String? {
        var parts: [String] = []
        if let liked = card.liked, liked > 0 { parts.append("♡ " + compact(liked)) }
        if let commented = card.commented, commented > 0 { parts.append("💬 " + compact(commented)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func trimmed(_ value: String?) -> String? {
        let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func compact(_ n: Int) -> String {
        guard n >= 10000 else { return "\(n)" }
        let value = Double(n) / 10000
        let text = n >= 100000 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return text.replacingOccurrences(of: ".0", with: "") + "万"
    }
}

private struct MessageAskChip: View {
    let ask: MessageAsk
    let palette: EchoPalette
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 9) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.accent)
                Text(chipText)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(ask.answer == nil ? palette.text : palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(ask.answer == nil ? "回答" : "看看")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ask.answer == nil ? palette.accent : palette.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(palette.composer.opacity(0.76), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ask.answer == nil ? "回答问题：\(ask.question)" : "查看已回答的问题：\(ask.question)")
    }

    private var chipText: String {
        if let answer = ask.answer { return "你答：\(answer.text)" }
        return ask.question
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

/// Material and silhouette are separate settings: classic/frosted bubbles can
/// opt into Telegram-like grouping while liquid glass keeps its rounded shape.
private struct EchoMessageBubbleShape: Shape {
    let style: EchoBubbleShapeStyle
    let author: MessageAuthor
    let radius: CGFloat
    let isGroupStart: Bool
    let isTail: Bool

    func path(in rect: CGRect) -> Path {
        switch style {
        case .telegram:
            return TelegramBubbleShape(
                author: author,
                radius: radius,
                isGroupStart: isGroupStart,
                isTail: isTail
            ).path(in: rect)
        case .upperTail:
            return UpperCornerBubbleShape(
                author: author,
                radius: radius
            ).path(in: rect)
        case .standard:
            return PWAChatBubbleShape(
                radius: radius,
                bottomLeftRadius: author == .ai && isTail ? 5 : radius,
                bottomRightRadius: author == .human && isTail ? 5 : radius
            ).path(in: rect)
        }
    }
}

/// A flush, nearly-square top corner inspired by the supplied reference.
/// Incoming bubbles pin the upper-left corner and outgoing bubbles mirror it
/// at upper-right. Every bubble keeps the softened pin for a consistent rhythm.
private struct UpperCornerBubbleShape: Shape {
    let author: MessageAuthor
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let full = min(max(0, radius), limit)
        let pinned = min(CGFloat(6), full)
        let topLeft = author == .ai ? pinned : full
        let topRight = author == .human ? pinned : full

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
            radius: topRight,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - full))
        path.addArc(
            center: CGPoint(x: rect.maxX - full, y: rect.maxY - full),
            radius: full,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + full, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + full, y: rect.maxY - full),
            radius: full,
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

private struct TelegramBubbleShape: Shape {
    let author: MessageAuthor
    let radius: CGFloat
    let isGroupStart: Bool
    let isTail: Bool

    func path(in rect: CGRect) -> Path {
        // Keep the rounded body on the same alignment line for every row.
        // The tail grows outward instead of reserving space inside the bubble.
        // Both sides share one tail: short, level with the baseline, resolving
        // into a clean cusp. The outgoing side is an exact mirror of it, so the
        // two columns read as the same bubble facing opposite directions.
        let tailWidth: CGFloat = 7
        let tailShoulder: CGFloat = 9
        let body = rect
        let limit = min(body.width, body.height) / 2
        let full = min(max(0, radius), limit)
        let joined = min(max(CGFloat(7), full * 0.42), min(CGFloat(10), limit))
        let topLeft = author == .ai ? (isGroupStart ? full : joined) : full
        let topRight = author == .human ? (isGroupStart ? full : joined) : full
        let bottomLeft = author == .ai ? joined : full
        let bottomRight = author == .human ? joined : full

        var path = Path()
        path.move(to: CGPoint(x: body.minX + topLeft, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - topRight, y: body.minY))
        path.addArc(
            center: CGPoint(x: body.maxX - topRight, y: body.minY + topRight),
            radius: topRight,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )

        if author == .human && isTail {
            // Mirror of the incoming tail below, traversed in reverse: this
            // edge runs down the right side into the baseline, the other runs
            // along the baseline out to the left, so the control points swap
            // order as well as sign.
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - tailShoulder))
            path.addCurve(
                to: CGPoint(x: rect.maxX + tailWidth, y: rect.maxY - 0.5),
                control1: CGPoint(x: body.maxX, y: body.maxY - 5.5),
                control2: CGPoint(x: rect.maxX + 4, y: rect.maxY - 0.75)
            )
            path.addCurve(
                to: CGPoint(x: body.maxX - tailShoulder, y: body.maxY),
                control1: CGPoint(x: rect.maxX + 1.5, y: rect.maxY - 2.25),
                control2: CGPoint(x: body.maxX - 5, y: body.maxY)
            )
        } else {
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - bottomRight))
            path.addArc(
                center: CGPoint(x: body.maxX - bottomRight, y: body.maxY - bottomRight),
                radius: bottomRight,
                startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
            )
        }

        if author == .ai && isTail {
            // Keep the incoming tail short and level with the baseline. The
            // first control point preserves the bottom edge's horizontal
            // tangent; the shallow inset then resolves into a clean cusp.
            path.addLine(to: CGPoint(x: body.minX + tailShoulder, y: body.maxY))
            path.addCurve(
                to: CGPoint(x: rect.minX - tailWidth, y: rect.maxY - 0.5),
                control1: CGPoint(x: body.minX + 5, y: body.maxY),
                control2: CGPoint(x: rect.minX - 1.5, y: rect.maxY - 2.25)
            )
            path.addCurve(
                to: CGPoint(x: body.minX, y: body.maxY - tailShoulder),
                control1: CGPoint(x: rect.minX - 4, y: rect.maxY - 0.75),
                control2: CGPoint(x: body.minX, y: body.maxY - 5.5)
            )
        } else {
            path.addLine(to: CGPoint(x: body.minX + bottomLeft, y: body.maxY))
            path.addArc(
                center: CGPoint(x: body.minX + bottomLeft, y: body.maxY - bottomLeft),
                radius: bottomLeft,
                startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: body.minX, y: body.minY + topLeft))
        path.addArc(
            center: CGPoint(x: body.minX + topLeft, y: body.minY + topLeft),
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
        EchoDateCache.date(from: raw)
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
    let isMist: Bool
    let showsAIAvatar: Bool
    let bubbleWidthScale: Double
    @State private var expanded = false
    @State private var showingMistSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard canExpand else { return }
                if isMist {
                    showingMistSheet = true
                } else {
                    withAnimation(isHarbor ? .spring(response: 0.34, dampingFraction: 0.86) : .easeOut(duration: 0.16)) {
                        expanded.toggle()
                    }
                }
            } label: {
                if isMist {
                    mistTrigger
                } else if isHarbor {
                    harborTrigger
                } else {
                    legacyTrigger
                }
            }
            .buttonStyle(.plain)

            recallHint

            if expanded && !isMist {
                if isHarbor {
                    harborProcessCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    processDetail
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: CGFloat(280 * bubbleWidthScale), alignment: .leading)
        .padding(.leading, showsAIAvatar ? 35 : 0)
        .padding(.trailing, 44)
        .sheet(isPresented: $showingMistSheet) {
            mistProcessSheet
        }
    }

    private var isThinking: Bool { message.kind == "thinking" }
    private var canExpand: Bool { isThinking ? !message.text.isEmpty : !message.meta.steps.isEmpty }

    /// 「这轮我想起了东西」——浮现本身是隐形的（旧记忆只垫在他眼前），
    /// 这一行是她唯一能看见的痕迹。收起状态也在，不用展开才看得到。
    @ViewBuilder
    private var recallHint: some View {
        if isThinking, let count = message.meta.recalled, count > 0 {
            Text("✧ 浮现 \(count) 条旧记忆")
                .font(chatFont.font(size: 11 * fontScale, weight: .regular))
                .foregroundStyle(palette.secondaryText.opacity(0.7))
                .padding(.top, -3)
        }
    }
    private var isHarbor: Bool { !isPaper && !isMist }
    private var processFontSize: Double {
        PWAChatMetrics.thinkingFontSize(for: chatFont) * fontScale * (isMist ? 1.16 : 1)
    }

    private var mistTrigger: some View {
        HStack(spacing: 6) {
            Image(systemName: isThinking ? "cloud" : "wrench")
                .font(.system(size: isThinking ? 12 : 11, weight: .medium))
            Text(isThinking ? "Thinking" : "Action")
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
        }
        .font(chatFont.font(size: 12.5 * fontScale, weight: .medium))
        .foregroundStyle(palette.secondaryText)
        .padding(.vertical, 2)
    }

    private var harborTrigger: some View {
        HStack(spacing: 6) {
            Image(systemName: isThinking ? "heart.fill" : "wrench")
                .font(.system(size: isThinking ? 11.5 : 11, weight: .medium))
            Text(isThinking ? "Thinking" : "Action")
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .font(chatFont.font(size: 12.5 * fontScale, weight: .medium))
        .foregroundStyle(palette.secondaryText)
        .padding(.vertical, 2)
    }

    private var legacyTrigger: some View {
        HStack(spacing: 7) {
            if isThinking {
                Text("THINKING")
                Image(systemName: "play.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            } else {
                Image(systemName: "wrench")
                    .font(.system(size: 11, weight: .medium))
                Text("Action")
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

    @ViewBuilder
    private func processContent(textColor: Color) -> some View {
        if isThinking {
            SelectableThinkingText(
                text: message.text,
                font: chatFont.uiFont(size: processFontSize, numericWeight: chatWeight),
                textColor: textColor,
                selectionColor: palette.accent,
                lineSpacing: PWAChatMetrics.lineSpacing(
                    font: chatFont,
                    size: processFontSize
                )
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(message.meta.steps.enumerated()), id: \.offset) { _, step in
                    ToolStepPreview(
                        step: step,
                        palette: palette,
                        chatFont: chatFont,
                        fontSize: processFontSize,
                        chatWeight: chatWeight
                    )
                }
            }
        }
    }

    private var harborProcessCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(isThinking ? "Thought process" : "Action")
                    .font(chatFont.font(size: 12.5 * fontScale, weight: .medium))
                    .foregroundStyle(palette.text.opacity(0.88))
                Spacer(minLength: 12)
                Image(systemName: isThinking ? "heart.fill" : "wrench")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
            }
            Divider().overlay(palette.hairline)
            processContent(textColor: palette.secondaryText)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.055), radius: 10, y: 5)
    }

    private var mistProcessSheet: some View {
        NavigationStack {
            ScrollView {
                processContent(textColor: palette.text.opacity(0.84))
                    .foregroundStyle(palette.text.opacity(0.84))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(isThinking ? "Thought process" : "Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingMistSheet = false } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var processDetail: some View {
        processContent(textColor: palette.secondaryText)
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

/// SwiftUI `Text` can collapse to a whole-view Copy/Share menu inside the
/// expandable process card. A non-editable `UITextView` keeps native insertion
/// points and draggable selection handles while sizing like ordinary text.
private struct SelectableThinkingText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: Color
    let selectionColor: Color
    let lineSpacing: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let attributedText = makeAttributedText()
        if !textView.attributedText.isEqual(to: attributedText) {
            textView.attributedText = attributedText
        }
        textView.tintColor = UIColor(selectionColor)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(fittingSize.height))
    }

    private func makeAttributedText() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
        let italicDescriptor = font.fontDescriptor.withSymbolicTraits(traits)
        let renderedFont = italicDescriptor.map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
        var attributes: [NSAttributedString.Key: Any] = [
            .font: renderedFont,
            .foregroundColor: UIColor(textColor),
            .paragraphStyle: paragraphStyle
        ]
        if italicDescriptor == nil {
            attributes[.obliqueness] = 0.14
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}

private struct ToolStepPreview: View {
    let step: ToolStep
    let palette: EchoPalette
    let chatFont: EchoChatFont
    let fontSize: Double
    let chatWeight: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            previewLine("tool", step.tool, monospaced: false, limit: 1)
            previewLine("cmd", step.cmd, monospaced: true, limit: 5)
            previewLine("result", step.result, monospaced: true, limit: 4)
        }
        .font(chatFont.font(size: fontSize, numericWeight: chatWeight))
    }

    @ViewBuilder
    private func previewLine(_ key: String, _ value: String?, monospaced: Bool, limit: Int) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 3) {
                Text("\(key):")
                    .foregroundStyle(palette.secondaryText.opacity(0.76))
                Text(value)
                    .font(
                        monospaced
                            ? .system(size: CGFloat(fontSize), design: .monospaced)
                            : chatFont.font(size: fontSize, numericWeight: chatWeight)
                    )
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
    let isMist: Bool
    let showsAIAvatar: Bool
    let chatFont: EchoChatFont
    let fontScale: Double
    let chatWeight: Double

    var body: some View {
        if isHarbor {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(chatFont.font(size: 12.5 * fontScale, weight: .medium))
                    Spacer(minLength: 12)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                Divider().overlay(palette.hairline)
                streamingText
            }
            .foregroundStyle(palette.secondaryText)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(0.055), radius: 10, y: 5)
            .frame(maxWidth: 280, alignment: .leading)
            .padding(.leading, showsAIAvatar ? 35 : 0)
            .padding(.trailing, 44)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if isMist {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "cloud")
                        .font(.system(size: 11, weight: .medium))
                    Text("Thinking…")
                        .font(chatFont.font(size: 12.5 * fontScale, weight: .medium))
                }
                streamingText
                    .lineLimit(2)
            }
            .foregroundStyle(palette.secondaryText)
            .frame(maxWidth: 280, alignment: .leading)
            .padding(.leading, showsAIAvatar ? 35 : 0)
            .padding(.trailing, 44)
        } else {
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

                streamingText
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

    private var streamingText: some View {
        Text(text)
            .font(chatFont.font(
                size: PWAChatMetrics.thinkingFontSize(for: chatFont) * fontScale * (isMist ? 1.07 : 1),
                numericWeight: chatWeight
            ).italic())
            .lineLimit(4)
            .lineSpacing(PWAChatMetrics.lineSpacing(
                font: chatFont,
                size: PWAChatMetrics.thinkingFontSize(for: chatFont) * fontScale
            ))
            .textSelection(.enabled)
    }

    private var isHarbor: Bool { !isPaper && !isMist }
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
    let aiBubbleTextColor: Color
    let bubbleOpacity: Double
    let bubbleRadius: Double
    let bubbleWidthScale: Double
    let bubbleBorderWidth: Double
    let bubbleStyle: EchoBubbleStyle
    let bubbleShapeStyle: EchoBubbleShapeStyle
    let liquidGlass: LiquidGlassSettings
    let chatWeight: Double
    let isTail: Bool

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
                .foregroundStyle(aiBubbleTextColor)
                .padding(.horizontal, showsAIBubble ? bubbleHorizontalPadding : 2)
                .padding(.vertical, bubbleVerticalPadding)
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
                            let shape = streamingBubbleShape
                            if bubbleStyle == .frosted {
                                FrostedGlassBubbleBackground(
                                    shape: shape,
                                    tint: aiBubbleColor,
                                    tintOpacity: bubbleOpacity
                                )
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
                            streamingBubbleShape
                                .stroke(palette.hairline, lineWidth: CGFloat(bubbleBorderWidth))
                        }
                    }
                }
                .frame(
                    maxWidth: showsAIBubble ? streamingBubbleMaxWidth : .infinity,
                    alignment: .leading
                )
            if showsAIBubble { Spacer(minLength: 0) }
        }
    }

    private var streamingBubbleMaxWidth: CGFloat {
        let scale = CGFloat(bubbleWidthScale)
        return scale <= 1 ? 280 * scale : 280 + ((scale - 1) * 140)
    }

    private var streamingBubbleShape: EchoMessageBubbleShape {
        EchoMessageBubbleShape(
            style: bubbleShapeStyle,
            author: .ai,
            radius: CGFloat(bubbleRadius),
            isGroupStart: true,
            isTail: isTail
        )
    }

    private var usesTelegramShape: Bool {
        bubbleShapeStyle == .telegram && (bubbleStyle == .classic || bubbleStyle == .frosted)
    }

    private var bubbleHorizontalPadding: CGFloat { usesTelegramShape ? 10 : 13 }
    private var bubbleVerticalPadding: CGFloat { usesTelegramShape ? 8 : 9 }
}

/// Rebuilt to match Operit's chat bubbles (`ui/theme/LiquidGlass.kt`), whose
/// surface is a bare backdrop — `vibrancy()` then `blur(28.dp)`, no refraction,
/// since the bubbles pass `enableLens = false` — under a light tint wash and a
/// thin, bright, slightly softened rim.
///
/// `.thinMaterial` cannot reach that look: a system material paints its own
/// gray/white veil over the sample, which is what makes an iOS "frosted" panel
/// read as milky plastic instead of glass. Sampling the backdrop directly and
/// applying every layer above it explicitly is the whole difference.
/// Keeping the caller's Shape preserves Telegram tails.
private struct FrostedGlassBubbleBackground<BubbleShape: Shape>: View {
    let shape: BubbleShape
    let tint: Color
    let tintOpacity: Double

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let isLight = colorScheme == .light
        let clampedTint = max(0, min(1, tintOpacity))
        // Operit tints the surface at 0.16 (light) / 0.23 (dark) plus a 0.10
        // overlay boost. Past that the wash starts hiding the backdrop and the
        // glass turns back into translucent plastic.
        let surfaceTintOpacity = min(
            isLight ? 0.26 : 0.33,
            (isLight ? 0.07 : 0.11) + clampedTint * (isLight ? 0.19 : 0.22)
        )

        Group {
            if reduceTransparency {
                shape.fill(tint.opacity(isLight ? 0.30 : 0.38))
            } else {
                // A Shape fill happily paints outside the view's bounds, but a
                // UIKit backdrop only samples its own frame — and the Telegram
                // tail is drawn past the edge on purpose. Oversizing the blur
                // keeps the tail from coming out hollow; `clipShape` still cuts
                // to the real path, which may itself extend past the bounds.
                Color.clear
                    .overlay {
                        VariableBackdropBlur(
                            radius: 26,
                            mask: .solid,
                            saturation: 1.7,
                            // One live backdrop per bubble is only affordable
                            // in a scrolling list at 1x. At the screen's own 3x
                            // this drops frames, and a 26pt blur has no detail
                            // left to lose by being sampled coarsely.
                            resolutionScale: 1
                        )
                        .padding(-14)
                    }
                    .clipShape(shape)
            }
        }
        .overlay(shape.fill(tint.opacity(surfaceTintOpacity)))
        .overlay {
            // A faint directional gloss. Operit's fallback washes flat white
            // over the surface; angling it keeps the bubble from looking like a
            // sticker without implying a light source the rim contradicts.
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isLight ? 0.10 : 0.055),
                        Color.white.opacity(isLight ? 0.02 : 0.01),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay {
            // Operit's Highlight is 0.28dp wide but blurred at 2.4x that and
            // drawn at alpha 0.62: a thin bright edge that fades inward rather
            // than a drawn outline. Clipping after the blur discards the outer
            // half, so the rim lands at roughly half this line width and the
            // shape stays crisp. No dark side — the Compose highlight has none,
            // and a black lower edge is what made this read as a drawn border.
            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isLight ? 0.62 : 0.50),
                            Color.white.opacity(isLight ? 0.26 : 0.20),
                            Color.white.opacity(isLight ? 0.10 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .blur(radius: 0.7)
                .clipShape(shape)
        }
        .shadow(
            color: Color.black.opacity(isLight ? 0.10 : 0.18),
            radius: 12,
            y: 3
        )
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
        .frame(width: 30, height: 30)
        .clipShape(Circle())
    }
}

struct TypingRow: View {
    let palette: EchoPalette
    let showsAIAvatar: Bool
    let aiAvatarImage: UIImage?

    var body: some View {
        HStack(spacing: 8) {
            if showsAIAvatar {
                AvatarBadge(image: aiAvatarImage, fallback: "sparkle", palette: palette)
            }
            JumpingDots(color: palette.secondaryText)
            .padding(.horizontal, 14)
            .frame(height: 35)
            .background(palette.aiBubble, in: Capsule())
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI 正在输入")
    }
}

/// A staggered three-dot wave shared by transient chat activity indicators.
/// Timeline-driven motion keeps the dots phase-locked after list recycling.
private struct JumpingDots: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let jump = jumpAmount(for: index, at: context.date)
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .scaleEffect(0.88 + jump * 0.16)
                        .offset(y: -4 * jump)
                        .opacity(0.42 + Double(jump) * 0.58)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func jumpAmount(for index: Int, at date: Date) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let cycle = 1.05
        let stagger = 0.14 * Double(index)
        var elapsed = (date.timeIntervalSinceReferenceDate - stagger)
            .truncatingRemainder(dividingBy: cycle)
        if elapsed < 0 { elapsed += cycle }
        let phase = elapsed / cycle
        guard phase < 0.44 else { return 0 }
        return CGFloat(sin((phase / 0.44) * .pi))
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
        } else if attachment.isAudio {
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

struct VoiceAttachmentView: View {
    let attachment: Attachment
    let request: URLRequest?
    let palette: EchoPalette
    @ObservedObject private var playback = VoicePlaybackCenter.shared
    @State private var scrubProgress: Double?

    private var isCurrent: Bool { playback.currentID == attachment.id }
    private var displayedProgress: Double {
        scrubProgress ?? (isCurrent ? playback.progress : 0)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                guard let request else { return }
                Task { await playback.toggle(id: attachment.id, request: request) }
            } label: {
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrent && playback.isPlaying ? "暂停语音" : "播放语音")

            VoiceWaveform(
                progress: displayedProgress,
                isPlaying: isCurrent && playback.isPlaying && scrubProgress == nil,
                palette: palette
            )
            .frame(width: 86, height: 28)
            .contentShape(Rectangle())
            .gesture(waveformDragGesture)
            .accessibilityElement()
            .accessibilityLabel("语音播放进度")
            .accessibilityValue("百分之 \(Int(displayedProgress * 100))")
            .accessibilityAdjustableAction { direction in
                guard isCurrent else { return }
                let delta: Double
                switch direction {
                case .increment: delta = 0.05
                case .decrement: delta = -0.05
                @unknown default: return
                }
                playback.seek(id: attachment.id, toProgress: playback.progress + delta)
            }

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

    private var waveformDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let next = waveformProgress(at: value.location.x)
                scrubProgress = next
                if isCurrent {
                    playback.seek(id: attachment.id, toProgress: next)
                }
            }
            .onEnded { value in
                let next = waveformProgress(at: value.location.x)
                if isCurrent {
                    playback.seek(id: attachment.id, toProgress: next)
                    scrubProgress = nil
                } else if let request {
                    Task { @MainActor in
                        await playback.toggle(id: attachment.id, request: request)
                        playback.seek(id: attachment.id, toProgress: next)
                        scrubProgress = nil
                    }
                } else {
                    scrubProgress = nil
                }
            }
    }

    private func waveformProgress(at x: CGFloat) -> Double {
        Double(min(86, max(0, x)) / 86)
    }

    private func voiceTime(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var playbackLabel: String {
        if let scrubProgress, isCurrent, playback.duration > 0 {
            return voiceTime(playback.duration * scrubProgress)
        }
        if isCurrent && playback.duration > 0 { return voiceTime(playback.duration) }
        if attachment.voice == true || attachment.name.lowercased().contains("voice") { return "语音" }
        return attachment.name
    }
}

private struct VoiceWaveform: View {
    let progress: Double
    let isPlaying: Bool
    let palette: EchoPalette

    private let barHeights: [CGFloat] = [
        8, 15, 21, 13, 18, 10, 16, 22, 12, 19, 9,
        17, 14, 20, 11, 18, 13, 21, 10, 16, 12, 8
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isPlaying)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(barHeights.indices, id: \.self) { index in
                    let threshold = (Double(index) + 0.5) / Double(barHeights.count)
                    Capsule()
                        .fill(threshold <= progress ? palette.accent : palette.secondaryText.opacity(0.32))
                        .frame(width: 2.2, height: animatedHeight(at: index, phase: phase))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func animatedHeight(at index: Int, phase: TimeInterval) -> CGFloat {
        guard isPlaying else { return barHeights[index] }
        let wave = sin(phase * 5.2 + Double(index) * 0.78)
        return max(6, barHeights[index] + CGFloat(wave) * 2.4)
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

struct AuthenticatedImageView: View {
    let request: URLRequest?
    let palette: EchoPalette
    var contentMode: ContentMode = .fit
    var allowsPreview = true
    @StateObject private var loader = AuthenticatedImageLoader()
    @State private var previewImage: ImagePreviewItem?

    init(
        request: URLRequest?,
        palette: EchoPalette,
        contentMode: ContentMode = .fit,
        allowsPreview: Bool = true
    ) {
        self.request = request
        self.palette = palette
        self.contentMode = contentMode
        self.allowsPreview = allowsPreview
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .scaleEffect(imageOverscan)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard allowsPreview else { return }
                        previewImage = ImagePreviewItem(image: image)
                    }
                    .accessibilityElement()
                    .accessibilityLabel("打开图片预览")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        guard allowsPreview else { return }
                        previewImage = ImagePreviewItem(image: image)
                    }
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

    private var imageOverscan: CGFloat {
        switch contentMode {
        case .fit: return 1
        case .fill: return 1.04
        @unknown default: return 1
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
            let visualThickness = clamped((settings.size - 80) / 180)
            let glassTintOpacity = clamped(0.018 + tintOpacity * (0.065 + strength * 0.045))
            let washOpacity = clamped(tintOpacity * (0.012 + strength * 0.04 + visualThickness * 0.018))
            let rimLine = CGFloat(0.32 + rim * 1.45 + visualThickness * 0.24)
            let dispersionShift = CGFloat(dispersion * 1.35)
            let usesStableLongBubble = geometry.size.height > 2000

            if reduceTransparency || usesStableLongBubble {
                // Very tall native Glass surfaces are tiled by the compositor
                // and can flash gray blocks while scrolling. A static translucent
                // surface is more important than live refraction for long essays.
                ZStack {
                    shape.fill(tint.opacity(clamped(0.13 + tintOpacity * 0.24)))
                    shape.fill(Color.white.opacity(reduceTransparency ? 0.17 : 0.065))
                }
                .overlay {
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16 + rim * 0.10),
                                Color.white.opacity(0.035),
                                Color.black.opacity(0.025)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: rimLine
                    )
                }
            } else {
                ZStack {
                    // One native glass surface per bubble. The system owns all
                    // backdrop refraction, blur, lighting and motion response.
                    shape
                        .fill(Color.white.opacity(0.001))
                        .glassEffect(
                            .clear
                                .tint(tint.opacity(glassTintOpacity))
                                .interactive(false),
                            in: shape
                        )

                    // A flat tint wash changes visual thickness without asking
                    // the compositor to sample or blur the backdrop a second time.
                    shape.fill(tint.opacity(washOpacity))

                    if dispersion > 0.001 {
                        // Lightweight rim-only approximation. True RGB backdrop
                        // displacement remains reserved for an explicit enhanced
                        // renderer with a captured background texture.
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [.clear, Color.red.opacity(0.26), Color.pink.opacity(0.10), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: rimLine
                            )
                            .offset(x: dispersionShift, y: dispersionShift * 0.28)
                            .opacity(dispersion * 0.46)

                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [.clear, Color.cyan.opacity(0.28), Color.blue.opacity(0.09), .clear],
                                    startPoint: .bottomTrailing,
                                    endPoint: .topLeading
                                ),
                                lineWidth: rimLine
                            )
                            .offset(x: -dispersionShift, y: -dispersionShift * 0.28)
                            .opacity(dispersion * 0.46)
                    }
                }
                .clipShape(shape)
                .overlay {
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10 + rim * 0.13 + visualThickness * 0.04),
                                Color.white.opacity(0.025),
                                Color.black.opacity(0.018 + strength * 0.018)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: rimLine
                    )
                }
                .shadow(
                    color: Color.black.opacity(0.018 + strength * 0.018),
                    radius: 2.2,
                    y: 1.2
                )
            }
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
