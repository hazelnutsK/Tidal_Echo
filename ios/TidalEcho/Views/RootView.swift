import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchPresentationComplete = false

    var body: some View {
        ZStack {
            if showsLaunchView {
                LaunchView(theme: model.theme)
                    .transition(.opacity)
            } else {
                Group {
                    switch model.phase {
                    case .launching:
                        LaunchView(theme: model.theme)
                    case .signedOut, .connecting:
                        LoginView(model: model)
                    case .connected:
                        ChatView(model: model)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.34), value: showsLaunchView)
        .task {
            NativeNotificationCenter.shared.fetchHandler = { [weak model] in
                guard let model else { return false }
                return await model.backgroundRefreshForNotifications()
            }

            async let bootstrapTask: Void = model.bootstrap()
            // 星图开屏把关键叙事（星芒→星图→月相成环→扭转→pulse→标题）讲完约 3.1s。
            // bootstrap 更慢时开屏自然停在 idle（月相沿轨道缓慢流动），不会有突兀的收尾。
            let minimumPresentation: Duration = reduceMotion ? .milliseconds(250) : .milliseconds(3200)
            try? await Task.sleep(for: minimumPresentation)
            launchPresentationComplete = true
            await bootstrapTask
        }
        .alert(
            "Tidal Echo",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var showsLaunchView: Bool {
        !launchPresentationComplete || model.phase == .launching
    }
}

