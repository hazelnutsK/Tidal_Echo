import SwiftUI
import UIKit

enum EchoTheme: String, CaseIterable, Hashable, Identifiable {
    case mist
    case paper
    case harbor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mist: return "雾绣"
        case .paper: return "纸白"
        case .harbor: return "夜港"
        }
    }

    var subtitle: String {
        switch self {
        case .mist: return "冷雾、银蓝与柔光"
        case .paper: return "安静、克制的纸张质感"
        case .harbor: return "深海蓝与夜间微光"
        }
    }

    var preferredColorScheme: ColorScheme {
        self == .harbor ? .dark : .light
    }

    var palette: EchoPalette {
        switch self {
        case .mist:
            return EchoPalette(
                backgroundTop: Color(hex: 0xE8EDF2),
                backgroundBottom: Color(hex: 0xF7FAFC),
                text: Color(hex: 0x344050),
                secondaryText: Color(hex: 0x738194),
                aiBubble: Color(hex: 0xEBEBEB).opacity(0.92),
                humanBubble: Color(hex: 0xC9CCD3).opacity(0.90),
                composer: Color.white.opacity(0.58),
                accent: Color(hex: 0x65758A),
                hairline: Color(hex: 0x66778A).opacity(0.16)
            )
        case .paper:
            return EchoPalette(
                backgroundTop: Color(hex: 0xFAFAF8),
                backgroundBottom: Color(hex: 0xFAFAF8),
                text: Color(hex: 0x35342F),
                secondaryText: Color(hex: 0x77746B),
                aiBubble: Color(hex: 0xEEEBE4),
                humanBubble: Color(hex: 0xE2C2C5),
                composer: Color(hex: 0xF0EEE6).opacity(0.84),
                accent: Color(hex: 0x8C7466),
                hairline: Color(hex: 0xBDA896).opacity(0.28)
            )
        case .harbor:
            return EchoPalette(
                backgroundTop: Color(hex: 0x15212D),
                backgroundBottom: Color(hex: 0x0D1720),
                text: Color(hex: 0xE5EDF3),
                secondaryText: Color(hex: 0x95A6B5),
                aiBubble: Color(hex: 0x253541).opacity(0.94),
                humanBubble: Color(hex: 0x344A5B).opacity(0.94),
                composer: Color(hex: 0x1C2A35).opacity(0.94),
                accent: Color(hex: 0x8AAFC6),
                hairline: Color.white.opacity(0.10)
            )
        }
    }
}

enum EchoChatFont: String, CaseIterable, Hashable, Identifiable {
    case system
    case serif
    case rounded
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "黑体"
        case .serif: return "宋体"
        case .rounded: return "圆体"
        case .monospaced: return "等宽"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }

    func font(size: Double, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            // Match the PWA's Chinese sans stack on iOS instead of relying on
            // SwiftUI's locale-dependent generic fallback.
            return .custom("PingFang SC", size: CGFloat(size)).weight(weight)
        case .serif:
            return .custom("Songti SC", size: CGFloat(size)).weight(weight)
        case .rounded, .monospaced:
            return .system(size: CGFloat(size), weight: weight, design: design)
        }
    }

    /// SwiftUI's `lineSpacing` is added on top of the font's native line box.
    /// Exposing that native height lets chat rows match the PWA's CSS line-height
    /// instead of approximating it with a fixed extra amount.
    func nativeLineHeight(size: Double) -> CGFloat {
        let pointSize = CGFloat(size)
        switch self {
        case .system:
            return UIFont(name: "PingFangSC-Regular", size: pointSize)?.lineHeight
                ?? UIFont.systemFont(ofSize: pointSize).lineHeight
        case .serif:
            return UIFont(name: "Songti SC", size: pointSize)?.lineHeight
                ?? UIFont.systemFont(ofSize: pointSize).lineHeight
        case .rounded:
            let descriptor = UIFont.systemFont(ofSize: pointSize).fontDescriptor.withDesign(.rounded)
            return descriptor.map { UIFont(descriptor: $0, size: pointSize).lineHeight }
                ?? UIFont.systemFont(ofSize: pointSize).lineHeight
        case .monospaced:
            return UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular).lineHeight
        }
    }
}

enum PWAChatMetrics {
    // A touch more open than the last build's PWA-exact 1.58 rhythm, while
    // remaining clearly tighter than the original native 16pt × 1.58 layout.
    static let lineHeightRatio = 1.64
    static let mobileBubbleFontSize = 14.0
    static let nativeBubbleFontSize = 16.0

    static func lineSpacing(font: EchoChatFont, size: Double) -> CGFloat {
        // On an iPhone the PWA's clamp resolves to 14px. Keep the App's chosen
        // 16pt text size, but derive baseline distance from the PWA's 14px mobile
        // size so the requested font size does not silently change.
        let scale = size / nativeBubbleFontSize
        let targetLineHeight = CGFloat(mobileBubbleFontSize * scale * lineHeightRatio)
        return max(0, targetLineHeight - font.nativeLineHeight(size: size))
    }
}

struct EchoPalette {
    let backgroundTop: Color
    let backgroundBottom: Color
    let text: Color
    let secondaryText: Color
    let aiBubble: Color
    let humanBubble: Color
    let composer: Color
    let accent: Color
    let hairline: Color

    var background: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }

    init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let hex = UInt(value, radix: 16) else { return nil }
        self.init(hex: hex)
    }
}

extension Double {
    var echoFontWeight: Font.Weight {
        switch self {
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        default: return .heavy
        }
    }
}
