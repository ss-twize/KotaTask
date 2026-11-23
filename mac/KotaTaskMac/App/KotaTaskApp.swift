import SwiftUI

@main
struct KotaTaskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("KotaTask", id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.store.flush() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Записываем сразу, а не через задержку: приложение могут закрыть из Dock или выключить Mac.
        MainActor.assumeIsolated { AppModel.shared.store.flush() }
    }
}

/// Меню приложения и шорткаты.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Новая задача") { model.presentNewTask() }
                .keyboardShortcut("n")
                .disabled(!model.settings.onboardingDone)
            Button("Экспортировать задачи…") { model.showsTaskExport = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.settings.onboardingDone)
        }

        CommandMenu("Переход") {
            if model.settings.splitToday {
                Button("Сегодня") { model.selection = .today }
                    .keyboardShortcut("1")
            }
            Button(model.settings.projectsEnabled ? "Общий" : "Задачи") { model.selection = .board }
                .keyboardShortcut("2")
            if model.settings.calendarEnabled {
                Button("Календарь") { model.selection = .calendar }
                    .keyboardShortcut("3")
            }
            Button("Архив") { model.selection = .archive }
                .keyboardShortcut("4")
        }

        CommandGroup(replacing: .help) {
            Button("Написать в поддержку") { model.openURL("mailto:\(AppModel.supportEmail)") }
            Button("Telegram") { model.openURL(AppModel.telegramURL) }
            Button("Предложить изменения") { model.openURL(AppModel.suggestURL) }
            Divider()
            Button("Поддержать проект") { model.openURL(AppModel.donateURL) }
        }
    }
}
