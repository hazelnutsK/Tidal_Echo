import SwiftUI
import UIKit

/// 开屏：星光 → 十字星芒 → 放射星图 → 星盘 → 月相成环 → 扭转为莫比乌斯 → pulse → Aquila
///
/// 整幅星图是**时间的纯函数**（TimelineView + Canvas），没有 repeatForever、没有 delay 叠加，
/// 因此任何一帧都可复现，也不存在元素"等待出发"的静止帧。
struct LaunchView: View {
    let theme: EchoTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var titleVisible = false
    @State private var subtitleVisible = false

    private var palette: EchoPalette { theme.palette }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                palette.background.ignoresSafeArea()

                if reduceMotion {
                    Canvas { context, size in
                        renderer(size: size).draw(into: context, t: Sky.staticFrame)
                    }
                } else {
                    TimelineView(.animation) { timeline in
                        Canvas { context, size in
                            renderer(size: size)
                                .draw(into: context, t: timeline.date.timeIntervalSince(start))
                        }
                    }
                }

                VStack(spacing: 18) {
                    Text("Aquila")
                        .font(Self.titleFont)
                        .foregroundStyle(palette.text)
                        .opacity(titleVisible ? 1 : 0)
                        .offset(y: titleVisible ? 0 : 9)

                    LaunchSubtitle(
                        tracking: subtitleVisible ? 3.4 : 6.2,
                        color: palette.secondaryText.opacity(0.82)
                    )
                    .opacity(subtitleVisible ? 1 : 0)
                }
                .position(
                    x: geo.size.width / 2,
                    y: Double(Sky.center(in: geo.size).y) + Sky.radius(in: geo.size) + 96
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tidal Echo 正在启动")
        .onAppear(perform: play)
    }

    private func renderer(size: CGSize) -> StarChart {
        StarChart(theme: theme, size: size, reduced: reduceMotion)
    }

    private func play() {
        start = Date()

        guard !reduceMotion else {
            titleVisible = true
            subtitleVisible = true
            return
        }
        withAnimation(.easeOut(duration: 0.36).delay(Sky.title.lowerBound)) {
            titleVisible = true
        }
        withAnimation(.easeOut(duration: 0.44).delay(Sky.subtitle.lowerBound)) {
            subtitleVisible = true
        }
    }

    /// Sacramento 的 PostScript 名是 `Sacramento-Regular`；万一没注册上，退回 family 名。
    private static let titleFont: Font = {
        let name = UIFont(name: "Sacramento-Regular", size: 44) != nil
            ? "Sacramento-Regular"
            : "Sacramento"
        return .custom(name, size: 44)
    }()
}

// MARK: - 时间轴与几何常量

private enum Sky {
    static let moonCount = 16
    static let dustCount = 220
    static let rayCount = 46
    static let bandHalfWidth: Double = 9      // 尘埃带半宽
    static let flatK: Double = 0.62           // 扭转后 ∞ 的高/宽系数
    static let perspective: Double = 760
    static let moonRadius: Double = 7.4
    static let drift: Double = 0.075          // 成形后沿轨道的流动 rad/s

    // 紧凑时间轴（秒）。关键叙事在 2.6s 内讲完，之后是可无限停留的 idle。
    static let core = 0.0...0.32
    static let cross = 0.15...0.62
    static let rays = 0.25...1.00
    static let rayGrow: Double = 0.38         // 单条放射线的生长时长
    static let raySpread: Double = 0.34       // 逐条错开的最大延迟
    static let dial = 0.62...1.14
    static let moons = 0.92...1.66
    static let dust = 1.05...1.70
    static let twist = 1.74...2.58
    static let pulseAt: Double = 2.58
    static let title = 2.45...2.85
    static let subtitle = 2.62...3.06

    /// reduceMotion 用的静止帧：所有进度已满、pulse 已过、无漂移。
    static let staticFrame: Double = 99

    static func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.375)
    }

    static func radius(in size: CGSize) -> Double {
        min(Double(size.width) * 0.295, Double(size.height) * 0.16)
    }
}

private func ramp(_ t: Double, _ range: ClosedRange<Double>) -> Double {
    let x = (t - range.lowerBound) / (range.upperBound - range.lowerBound)
    return x < 0 ? 0 : (x > 1 ? 1 : x)
}

private func clamp01(_ x: Double) -> Double { x < 0 ? 0 : (x > 1 ? 1 : x) }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
private func easeInOut(_ x: Double) -> Double {
    x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

// MARK: - 预生成的装饰（固定种子，每次启动一致）

private struct Ray {
    let angle, r0, r1, width, opacity, dashPhase, delay: Double
    let dash: [CGFloat]
}

private struct Mote {
    let u, v, weight, size, opacity, twinkle: Double
}

private struct Speck {
    let x, y, r, opacity: Double
}

private struct Fleck {
    let x, y, r, opacity: Double
}

private struct Noise {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

private enum Decor {
    static let rays: [Ray] = {
        var n = Noise(20_260_829)
        return (0..<Sky.rayCount).map { i in
            let base = Double(i) / Double(Sky.rayCount) * 2 * .pi
            let dashed = n.next() < 0.62
            return Ray(
                angle: base + (n.next() - 0.5) * 0.075,
                r0: 26 + n.next() * 30,
                r1: 84 + n.next() * 104,
                width: 0.35 + n.next() * 0.55,
                opacity: 0.22 + n.next() * 0.6,
                dashPhase: n.next() * 20,
                delay: n.next() * Sky.raySpread,
                dash: dashed ? [CGFloat(3 + n.next() * 16), CGFloat(2.5 + n.next() * 9)] : []
            )
        }
    }()

    static let motes: [Mote] = {
        var n = Noise(770_113)
        return (0..<Sky.dustCount).map { _ in
            Mote(
                u: n.next() * 2 * .pi,
                v: n.next() * 2 - 1,
                weight: pow(n.next(), 0.7),
                size: 0.35 + n.next() * 0.95,
                opacity: 0.16 + n.next() * 0.5,
                twinkle: n.next() * 6.283
            )
        }
    }()

    static let specks: [Speck] = {
        var n = Noise(31_415_926)
        return (0..<80).map { _ in
            Speck(x: n.next(), y: n.next() * 0.72, r: n.next() * 0.9 + 0.25,
                  opacity: 0.12 + n.next() * 0.45)
        }
    }()

    static let flecks: [[Fleck]] = {
        var n = Noise(5_271_009)
        return (0..<Sky.moonCount).map { _ in
            (0..<5).map { _ in
                Fleck(x: (n.next() * 2 - 1) * 0.62, y: (n.next() * 2 - 1) * 0.62,
                      r: 0.12 + n.next() * 0.3, opacity: 0.05 + n.next() * 0.16)
            }
        }
    }()
}

// MARK: - 星图渲染

private struct StarChart {
    let theme: EchoTheme
    let size: CGSize
    let reduced: Bool

    private var palette: EchoPalette { theme.palette }
    private var isDark: Bool { theme == .harbor }
    private var ink: Color { isDark ? .white : palette.accent }
    private var moonFill: Color {
        isDark ? Color(hex: 0xECF2F7) : (theme == .mist ? Color(hex: 0x181818) : Color(hex: 0x68584A))
    }

    private var center: CGPoint { Sky.center(in: size) }
    private var R: Double { Sky.radius(in: size) }

    func draw(into context: GraphicsContext, t: Double) {
        let m = reduced ? 1 : easeInOut(ramp(t, Sky.twist))       // 扭转量 0→1
        let flow = reduced ? 0 : max(0, t - Sky.twist.upperBound) * Sky.drift

        drawTexture(context)
        if isDark { drawSpecks(context, t: t) }
        drawRays(context, t: t, m: m)
        drawDial(context, t: t, m: m)
        drawOrbit(context, t: t, m: m, flow: flow)
        drawCore(context, t: t, m: m)
        drawPulse(context, t: t, m: m)
    }

    // MARK: 背景

    /// graphite：极淡的竖纹，每 3pt 一条，合成一个 Path 一次 stroke 画完。
    private func drawTexture(_ context: GraphicsContext) {
        var path = Path()
        var x: Double = 0
        while x < Double(size.width) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: Double(size.height)))
            x += 3
        }
        context.stroke(
            path,
            with: .color(isDark ? Color.white.opacity(0.012) : Color.black.opacity(0.009)),
            lineWidth: 1
        )
    }

    private func drawSpecks(_ context: GraphicsContext, t: Double) {
        for s in Decor.specks {
            let x = s.x * Double(size.width)
            let y = s.y * Double(size.height)
            let a = s.opacity * (0.55 + 0.45 * sin(t * 1.4 + x))
            context.fill(
                Path(ellipseIn: CGRect(x: x - s.r, y: y - s.r, width: s.r * 2, height: s.r * 2)),
                with: .color(.white.opacity(a))
            )
        }
    }

    // MARK: 放射线

    private func drawRays(_ context: GraphicsContext, t: Double, m: Double) {
        guard t >= Sky.rays.lowerBound || reduced else { return }
        let fade = 1 - 0.55 * m                       // 扭转期让位给月相环

        for ray in Decor.rays {
            let grow = reduced
                ? 1
                : easeOut(clamp01((t - Sky.rays.lowerBound - ray.delay) / Sky.rayGrow))
            guard grow > 0 else { continue }

            let length = (ray.r1 - ray.r0) * grow
            let a = ray.opacity * (isDark ? 0.5 : 0.32) * fade * (0.35 + 0.65 * grow)

            var line = Path()
            line.move(to: CGPoint(x: ray.r0, y: 0))
            line.addLine(to: CGPoint(x: ray.r0 + length, y: 0))

            var ctx = context
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: .radians(ray.angle))
            ctx.stroke(
                line,
                with: .color(ink.opacity(a)),
                style: StrokeStyle(lineWidth: ray.width, dash: ray.dash, dashPhase: ray.dashPhase)
            )
        }
    }

    // MARK: 星盘

    private func drawDial(_ context: GraphicsContext, t: Double, m: Double) {
        let p = reduced ? 1 : easeOut(ramp(t, Sky.dial))
        guard p > 0 else { return }
        let fade = p * (1 - 0.75 * m)

        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)

        let outer = R * 0.60 * (0.85 + 0.15 * p)
        ctx.stroke(
            arc(radius: outer, sweep: p),
            with: .color(ink.opacity(0.30 * fade * (isDark ? 1 : 0.8))),
            style: StrokeStyle(lineWidth: 0.6, dash: [5, 4.5], dashPhase: -t * 4)
        )
        ctx.stroke(
            arc(radius: R * 0.43, sweep: p),
            with: .color(ink.opacity(0.20 * fade)),
            style: StrokeStyle(lineWidth: 0.5, dash: [2, 7])
        )

        var ticks = Path()
        let tickBase = R * 0.72
        for i in 0..<48 {
            guard Double(i) / 48 <= p else { break }
            let a = Double(i) / 48 * 2 * .pi
            let len = i % 4 == 0 ? 6.0 : 3.0
            ticks.move(to: CGPoint(x: cos(a) * tickBase, y: sin(a) * tickBase))
            ticks.addLine(to: CGPoint(x: cos(a) * (tickBase + len), y: sin(a) * (tickBase + len)))
        }
        ctx.stroke(ticks, with: .color(ink.opacity(0.26 * fade)), lineWidth: 0.5)
    }

    private func arc(radius: Double, sweep: Double) -> Path {
        var p = Path()
        p.addArc(center: .zero, radius: radius, startAngle: .zero,
                 endAngle: .radians(2 * .pi * max(0.0001, sweep)), clockwise: false)
        return p
    }

    // MARK: 轨道（尘埃 + 月相，按深度排序）

    /// 曲线：m=0 是正圆；m=1 是"立起来 + 拧半圈"的马鞍圆，正面投影即 ∞。
    private func point(u: Double, m: Double) -> SIMD3<Double> {
        let k = 1 + (Sky.flatK - 1) * m
        return SIMD3(R * cos(u), R * k * sin(u) * (1 - m + m * cos(u)), R * m * sin(u))
    }

    /// 带子法向：随扭转角 h = m·u/2 从面内转到竖直，扭转处收窄成一条线。
    private func bandOffset(u: Double, m: Double, v: Double) -> SIMD3<Double> {
        let h = m * u / 2
        let nx = cos(u)
        let ny = sin(u) * (1 + (Sky.flatK - 1) * m)
        let l = max(1e-6, (nx * nx + ny * ny).squareRoot())
        return SIMD3(v * cos(h) * nx / l, v * cos(h) * ny / l, v * sin(h))
    }

    private func project(_ p: SIMD3<Double>) -> (x: Double, y: Double, s: Double, z: Double) {
        let s = Sky.perspective / (Sky.perspective - p.z)
        return (Double(center.x) + p.x * s, Double(center.y) + p.y * s, s, p.z)
    }

    private enum Orbiter {
        case mote(Mote)
        case moon(index: Int, u: Double, appear: Double, phase: Double)
    }

    private func drawOrbit(_ context: GraphicsContext, t: Double, m: Double, flow: Double) {
        let dustIn = reduced ? 1 : easeOut(ramp(t, Sky.dust))
        let moonIn = reduced ? 1 : ramp(t, Sky.moons)

        var items: [(z: Double, x: Double, y: Double, s: Double, body: Orbiter)] = []
        items.reserveCapacity(Sky.dustCount + Sky.moonCount)

        if dustIn > 0 {
            for mote in Decor.motes {
                let u = mote.u + flow
                let off = bandOffset(u: u, m: m,
                                     v: mote.v * Sky.bandHalfWidth * (0.55 + 0.45 * mote.weight))
                let p = project(point(u: u, m: m) + off)
                items.append((p.z, p.x, p.y, p.s, .mote(mote)))
            }
        }
        if moonIn > 0 {
            for i in 0..<Sky.moonCount {
                let u = -Double.pi / 2 + Double(i) / Double(Sky.moonCount) * 2 * .pi + flow
                let p = project(point(u: u, m: m))
                let appear = reduced
                    ? 1
                    : easeOut(clamp01((moonIn * 1.16 - Double(i) / Double(Sky.moonCount) * 0.86) / 0.30))
                let phase = (Double(i) / Double(Sky.moonCount) + 0.5).truncatingRemainder(dividingBy: 1)
                items.append((p.z, p.x, p.y, p.s, .moon(index: i, u: u, appear: appear, phase: phase)))
            }
        }
        items.sort { $0.z < $1.z }

        let pulseT = t - Sky.pulseAt
        let pulseR = pulseT > 0 ? easeOut(clamp01(pulseT / 0.72)) * (R + 42) : -1

        for item in items {
            let depth = (item.z / R + 1) / 2                     // 0 远 → 1 近
            let dx = item.x - Double(center.x)
            let dy = item.y - Double(center.y)
            let dist = (dx * dx + dy * dy).squareRoot()
            let glow = pulseGlow(dist: dist, pulseT: pulseT, pulseR: pulseR)

            switch item.body {
            case .mote(let mote):
                let a = mote.opacity * dustIn * (0.35 + 0.65 * depth) * (isDark ? 1 : 0.62)
                    * (0.75 + 0.25 * sin(t * 1.9 + mote.twinkle))
                let r = mote.size * item.s * (1 + glow * 0.6)
                context.fill(
                    Path(ellipseIn: CGRect(x: item.x - r, y: item.y - r, width: r * 2, height: r * 2)),
                    with: .color((isDark ? Color.white : ink).opacity(min(1, a + glow * 0.5)))
                )

            case .moon(let index, let u, let appear, let phase):
                guard appear > 0 else { continue }
                drawMoon(context, index: index, u: u, appear: appear, phase: phase,
                         at: CGPoint(x: item.x, y: item.y), scale: item.s,
                         depth: depth, m: m, glow: glow)
            }
        }
    }

    private func pulseGlow(dist: Double, pulseT: Double, pulseR: Double) -> Double {
        guard pulseT > 0, pulseR > 0 else { return 0 }
        return max(0, 1 - abs(dist - pulseR) / 26) * max(0, 1 - pulseT / 1.15)
    }

    private func drawMoon(
        _ context: GraphicsContext, index: Int, u: Double, appear: Double, phase: Double,
        at p: CGPoint, scale: Double, depth: Double, m: Double, glow: Double
    ) {
        let r = Sky.moonRadius * scale * (0.5 + 0.5 * appear)
        let alpha = appear * (0.62 + 0.38 * depth)
        let h = m * u / 2                                  // 带子在此处的翻面角

        var ctx = context
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: .radians(m * sin(u) * 0.22))
        // 翻面证据：带子侧对观众时月相压扁
        ctx.scaleBy(x: 1, y: 0.42 + 0.58 * abs(cos(h)))

        if isDark {
            ctx.stroke(
                Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                with: .color(.white.opacity(0.055)),
                lineWidth: 0.6
            )
            let halo = r * 2.6
            ctx.fill(
                Path(ellipseIn: CGRect(x: -halo, y: -halo, width: halo * 2, height: halo * 2)),
                with: .radialGradient(
                    Gradient(colors: [
                        palette.accent.opacity((0.20 + glow * 0.5) * alpha),
                        palette.accent.opacity(0)
                    ]),
                    center: .zero, startRadius: r * 0.4, endRadius: halo
                )
            )
        }

        let disc = moonPath(r: r, phase: phase)
        let lift = min(1, alpha + glow * 0.85)
        ctx.fill(
            disc,
            with: .linearGradient(
                Gradient(colors: [
                    moonFill.opacity(lift * (isDark ? 0.78 : 0.92)),
                    moonFill.opacity(lift),
                    moonFill.opacity(lift * (isDark ? 0.62 : 0.8))
                ]),
                startPoint: CGPoint(x: -r, y: -r), endPoint: CGPoint(x: r, y: r)
            )
        )

        // 银箔斑驳
        var foil = ctx
        foil.clip(to: disc)
        for fleck in Decor.flecks[index] {
            let fr = fleck.r * r
            foil.fill(
                Path(ellipseIn: CGRect(x: fleck.x * r - fr, y: fleck.y * r - fr,
                                       width: fr * 2, height: fr * 2)),
                with: .color(isDark
                    ? Color(hex: 0x5A6978).opacity(fleck.opacity * 2.1)
                    : Color.white.opacity(fleck.opacity * 2.4))
            )
        }
    }

    /// 月相：右半圆 + 一段半宽为 |cos(2πphase)|·r 的 terminator，贝塞尔近似。
    /// phase 0=新月 .25=上弦 .5=满月 .75=下弦；下半周镜像成亏相。
    private func moonPath(r: Double, phase: Double) -> Path {
        let a = cos(2 * .pi * phase)          // +1 新月 → -1 满月
        let w = r * a                         // 正=terminator 与右缘同向（亮区窄）
        let K = 0.5523

        var p = Path()
        p.move(to: CGPoint(x: 0, y: -r))
        p.addCurve(to: CGPoint(x: r, y: 0),
                   control1: CGPoint(x: r * K, y: -r), control2: CGPoint(x: r, y: -r * K))
        p.addCurve(to: CGPoint(x: 0, y: r),
                   control1: CGPoint(x: r, y: r * K), control2: CGPoint(x: r * K, y: r))
        p.addCurve(to: CGPoint(x: w, y: 0),
                   control1: CGPoint(x: w * K, y: r), control2: CGPoint(x: w, y: r * K))
        p.addCurve(to: CGPoint(x: 0, y: -r),
                   control1: CGPoint(x: w, y: -r * K), control2: CGPoint(x: w * K, y: -r))
        p.closeSubpath()

        guard phase > 0.5 else { return p }
        return p.applying(CGAffineTransform(scaleX: -1, y: 1))
    }

    // MARK: 中心十字星芒

    private func drawCore(_ context: GraphicsContext, t: Double, m: Double) {
        let core = (reduced ? 1 : easeOut(ramp(t, Sky.core))) * (1 - 0.45 * m)
        guard core > 0 else { return }
        let k = reduced ? 1 : easeOut(ramp(t, Sky.cross))

        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: 1 - 0.14 * m, y: 1 - 0.14 * m)

        let halo: Double = 30
        ctx.fill(
            Path(ellipseIn: CGRect(x: -halo, y: -halo, width: halo * 2, height: halo * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    palette.accent.opacity((isDark ? 0.34 : 0.20) * core),
                    palette.accent.opacity(0)
                ]),
                center: .zero, startRadius: 0, endRadius: halo
            )
        )

        var cross = Path()
        cross.move(to: CGPoint(x: 0, y: -34 * k)); cross.addLine(to: CGPoint(x: 0, y: 34 * k))
        cross.move(to: CGPoint(x: -27 * k, y: 0)); cross.addLine(to: CGPoint(x: 27 * k, y: 0))
        ctx.stroke(cross, with: .color(ink.opacity(0.85 * core)), lineWidth: 1.05)

        var minor = Path()
        minor.move(to: CGPoint(x: 0, y: -20 * k)); minor.addLine(to: CGPoint(x: 0, y: 20 * k))
        minor.move(to: CGPoint(x: -20 * k, y: 0)); minor.addLine(to: CGPoint(x: 20 * k, y: 0))
        var diagonal = ctx
        diagonal.rotate(by: .radians(.pi / 4))
        diagonal.stroke(minor, with: .color(ink.opacity(0.42 * core)), lineWidth: 0.65)

        let dot = 1.9 * (0.6 + 0.4 * core)
        ctx.fill(
            Path(ellipseIn: CGRect(x: -dot, y: -dot, width: dot * 2, height: dot * 2)),
            with: .color(ink.opacity(0.95 * core))
        )
    }

    // MARK: pulse

    private func drawPulse(_ context: GraphicsContext, t: Double, m: Double) {
        let pulseT = t - Sky.pulseAt
        guard pulseT > 0, pulseT < 1.0 else { return }
        let r = easeOut(clamp01(pulseT / 0.72)) * (R + 42)
        let ry = r * (1 - 0.55 * m)

        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.stroke(
            Path(ellipseIn: CGRect(x: -r, y: -ry, width: r * 2, height: ry * 2)),
            with: .color(palette.accent.opacity(0.24 * max(0, 1 - pulseT / 0.9))),
            lineWidth: 0.7
        )
    }
}

// MARK: - 副标题

/// `.tracking()` 本身不参与插值，套一层 Animatable 让字距真的收拢。
private struct LaunchSubtitle: View, Animatable {
    var tracking: CGFloat
    let color: Color

    var animatableData: CGFloat {
        get { tracking }
        set { tracking = newValue }
    }

    var body: some View {
        Text("FLYING HOME TO YOU")
            .font(.system(size: 10, weight: .regular))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}
