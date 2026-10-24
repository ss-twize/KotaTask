import AppKit
import Observation
@preconcurrency import UserNotifications

/// Утренний дайджест через `UNUserNotificationCenter`.
///
/// При каждом изменении задач или настроек пересобирает уведомления на 7 дней вперёд
/// (см. `NotificationPlanner`). Клик по уведомлению просто открывает приложение —
/// в Android-версии тап не делал ничего.
@MainActor
@Observable
final class NotificationScheduler: NSObject {
    static let identifierPrefix = "kotatask.daily."

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var center: UNUserNotificationCenter { .current() }

    func configure() {
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Спрашивает разрешение один раз; если пользователь уже отказал — ничего не делает.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await refreshAuthorization()
        guard authorization == .notDetermined else { return authorization == .authorized || authorization == .provisional }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Открывает «Системные настройки → Уведомления».
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Пересобирает расписание с небольшой задержкой, чтобы не дёргать центр на каждое нажатие.
    func reschedule(tasks: [TaskItem], enabled: Bool, hour: Int, minute: Int, order: @escaping ([TaskItem]) -> [TaskItem]) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            await self.apply(tasks: tasks, enabled: enabled, hour: hour, minute: minute, order: order)
        }
    }

    private func apply(tasks: [TaskItem], enabled: Bool, hour: Int, minute: Int, order: ([TaskItem]) -> [TaskItem]) async {
        let pendingRequests = await center.pendingNotificationRequests()
        let ours = pendingRequests.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard enabled else { return }
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }

        let plans = NotificationPlanner.plans(tasks: tasks, hour: hour, minute: minute, now: .now, order: order)
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = NotificationPlanner.title
            content.body = plan.body
            content.sound = .default
            content.threadIdentifier = "kotatask.daily"
            let components = Calendar.kota.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Self.identifierPrefix + plan.day.iso, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}

extension NotificationScheduler: UNUserNotificationCenterDelegate {
    /// Показываем баннер, даже если приложение сейчас на экране.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NSApp.activate()
            AppModel.shared.selection = AppModel.shared.settings.splitToday ? .today : .board
        }
    }
}
