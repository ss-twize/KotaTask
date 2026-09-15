import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let notificationId = "kotatask.daily"

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { print("Notification permission error: \(error)") }
        }
    }

    /// Отменяет старое уведомление и планирует новое если включено.
    func reschedule(settings: AppSettings) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
        guard settings.notificationsEnabled else { return }
        schedule(hour: settings.notificationHour, minute: settings.notificationMinute)
    }

    /// Вызывать при старте приложения чтобы восстановить уведомление после перезагрузки.
    func restoreIfNeeded(settings: AppSettings) {
        guard settings.notificationsEnabled else { return }
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            if requests.first(where: { $0.identifier == self.notificationId }) == nil {
                self.schedule(hour: settings.notificationHour, minute: settings.notificationMinute)
            }
        }
    }

    private func schedule(hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "KotaTask"
        content.body = "Время проверить свои задачи на сегодня"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Notification scheduling error: \(error)") }
        }
    }
}
