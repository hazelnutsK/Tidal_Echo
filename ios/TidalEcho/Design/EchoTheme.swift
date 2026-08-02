import SwiftUI

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
                backgroundBottom: Color(hex: 0xF2F0EA),
                text: Color(hex: 0x35342F),
                secondaryText: Color(hex: 0x77746B),
                aiBubble: Color(hex: 0xF0EEE8),
                humanBubble: Color(hex: 0xE4E0D7),
                composer: Color(hex: 0xFFFEFB).opacity(0.90),
                accent: Color(hex: 0x6C7065),
                hairline: Color(hex: 0x8A877E).opacity(0.16)
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
        .system(size: CGFloat(size), weight: weight, design: design)
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
}
