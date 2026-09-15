import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context

    private var settings: AppSettings {
        if let s = settingsList.first { return s }
        let s = AppSettings()
        context.insert(s)
        return s
    }

    var body: some View {
        Group {
            if settings.onboardingCompleted {
                ContentView()
            } else {
                OnboardingView(settings: settings)
            }
        }
        .onAppear {
            NotificationManager.shared.restoreIfNeeded(settings: settings)
        }
    }
}
