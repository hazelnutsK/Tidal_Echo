import SwiftUI

struct LaunchView: View {
    let theme: EchoTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var echoesExpanded = false
    @State private var markVisible = false

    private var palette: EchoPalette { theme.palette }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(theme == .harbor ? 0.035 : 0.24))
                .frame(width: 340, height: 340)
                .blur(radius: 3)
                .offset(x: 138, y: -310)

            VStack(spacing: 12) {
                ZStack {
                    if !reduceMotion {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(palette.accent.opacity(0.22), lineWidth: 0.7)
                                .frame(width: 82, height: 82)
                                .scaleEffect(echoesExpanded ? 1.9 : 0.74)
                                .opacity(echoesExpanded ? 0 : 0.52)
                                .animation(
                                    .easeOut(duration: 1.75)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(index) * 0.40),
                                    value: echoesExpanded
                                )
                        }
                    }

                    Circle()
                        .fill(palette.composer)
                        .frame(width: 82, height: 82)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(theme == .harbor ? 0.10 : 0.48), lineWidth: 0.65)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)

                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(palette.accent)
                        .scaleEffect(markVisible ? 1 : 0.82)
                        .opacity(markVisible ? 1 : 0)
                }
                .frame(width: 156, height: 156)

                Text("Tidal Echo")
                    .font(.system(size: 31, weight: .medium, design: .serif))
                    .foregroundStyle(palette.text)

                Text("潮汐抵达，回声醒来")
                    .font(.system(size: 12.5, weight: .regular))
                    .tracking(1.4)
                    .foregroundStyle(palette.secondaryText.opacity(0.78))
            }
            .offset(y: -12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tidal Echo 正在启动")
        .onAppear {
            if reduceMotion {
                markVisible = true
            } else {
                withAnimation(.easeOut(duration: 0.48)) {
                    markVisible = true
                }
                echoesExpanded = true
            }
        }
    }
}
