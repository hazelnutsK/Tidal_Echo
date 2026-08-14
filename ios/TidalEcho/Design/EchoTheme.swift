import CoreText
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
                text: Color(hex: 0x292929),
                secondaryText: Color.black.opacity(0.54),
                aiBubble: Color(hex: 0xEBEBEB).opacity(0.92),
                humanBubble: Color(hex: 0xC9CCD3).opacity(0.90),
                composer: Color.white.opacity(0.58),
                accent: Color.black,
                hairline: Color.black.opacity(0.13)
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

    func font(size: Double, numericWeight: Double) -> Font {
        guard self == .system else {
            return font(size: size, weight: numericWeight.echoFontWeight)
        }
        // iOS 18 / macOS Sequoia 起，系统里的 PingFang 换成了带 wght 轴的可变字体
        // (私有 PingFangUI)。Safari 因此能把 420 / 440 / 460 渲染成各不相同的粗细，
        // 而这里原先点名静态 face，只能在 4 档之间跳——同一个滑块值两端就对不上。
        // 能拿到 wght 轴就走连续字重，拿不到(旧系统/静态 PingFang)按老办法分桶。
        if let variable = Self.variableSans(size: CGFloat(size), weight: numericWeight) {
            return Font(variable)
        }
        let face: String
        switch numericWeight {
        case ..<350: face = "PingFangSC-Light"
        case ..<450: face = "PingFangSC-Regular"
        case ..<550: face = "PingFangSC-Medium"
        default: face = "PingFangSC-Semibold"
        }
        return .custom(face, fixedSize: CGFloat(size))
    }

    /// 'wght' 轴的四字符标识
    static let wghtAxisID: UInt32 = 0x77676874

    /// PingFang 的 wght 轴可用时，返回按 `weight` 连续插值的字体；否则 nil。
    static func variableSans(size: CGFloat, weight: Double) -> UIFont? {
        guard let base = UIFont(name: "PingFangSC-Regular", size: size) else { return nil }
        guard let ids = variationAxisIDs(of: base), ids.contains(wghtAxisID) else { return nil }
        let attribute = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = base.fontDescriptor.addingAttributes([
            attribute: [NSNumber(value: wghtAxisID): NSNumber(value: weight)]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func variationAxisIDs(of font: UIFont) -> [UInt32]? {
        guard let raw = CTFontCopyVariationAxes(font as CTFont) as NSArray? else { return nil }
        guard let axes = raw as? [[String: Any]], !axes.isEmpty else { return nil }
        let key = kCTFontVariationAxisIdentifierKey as String
        return axes.compactMap { ($0[key] as? NSNumber)?.uint32Value }
    }

    /// 设置页那行小字：一眼看出这台机上到底走没走可变字重。
    static func weightDiagnostic() -> String {
        guard let base = UIFont(name: "PingFangSC-Regular", size: 14) else {
            return "取不到 PingFangSC-Regular · 走系统回退"
        }
        guard let ids = variationAxisIDs(of: base) else {
            return "静态字体 · 无可变轴 · 4 档分桶"
        }
        return ids.contains(wghtAxisID)
            ? "可变 wght ✓ 连续字重（\(ids.count) 轴）"
            : "有 \(ids.count) 轴但无 wght · 4 档分桶"
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
    // Keep the requested slightly-open rhythm. Only 黑体 adopts the PWA's
    // resolved iPhone sizes; the App's existing 宋体/圆体/等宽 sizing stays put.
    static let lineHeightRatio = 1.64
    static let mobileBubbleFontSize = 14.0
    static let nativeBubbleFontSize = 16.0

    static func bubbleFontSize(for font: EchoChatFont) -> Double {
        font == .system ? mobileBubbleFontSize : nativeBubbleFontSize
    }

    static func thinkingFontSize(for font: EchoChatFont) -> Double {
        font == .system ? 12 : 14
    }

    static func composerFontSize(for font: EchoChatFont) -> Double {
        font == .system ? 15 : 16
    }

    static func lineSpacing(font: EchoChatFont, size: Double) -> CGFloat {
        let targetLineHeight: CGFloat
        if font == .system {
            targetLineHeight = CGFloat(size * lineHeightRatio)
        } else {
            let scale = size / nativeBubbleFontSize
            targetLineHeight = CGFloat(mobileBubbleFontSize * scale * lineHeightRatio)
        }
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
