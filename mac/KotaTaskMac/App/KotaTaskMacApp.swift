import SwiftUI
import SwiftData

@main
struct KotaTaskMacApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [AppTask.self, Category.self, AppSettings.self])
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
