import SwiftUI

@main
struct TidalEchoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(model.theme.preferredColorScheme)
        }
    }
}

