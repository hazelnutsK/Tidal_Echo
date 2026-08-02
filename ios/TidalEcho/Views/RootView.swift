import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .signedOut, .connecting:
                LoginView(model: model)
            case .connected:
                ChatView(model: model)
            }
        }
        .task { await model.bootstrap() }
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
}

