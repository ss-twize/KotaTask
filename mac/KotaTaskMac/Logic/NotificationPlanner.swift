import Foundation

/// Одно запланированное утреннее уведомление.
struct DigestPlan: Equatable, Sendable {
    let day: Day
    let fireDate: Date
    let body: String
    let taskCount: Int
}

/// Состав утренних уведомлений на несколько дней вперёд.
///
/// Android собирает список в момент показа: WorkManager будит приложение. macOS спящее
/// приложение по расписанию не будит, поэтому текст считается заранее. Это точно, потому что
/// данные меняет только само приложение: в день N в «Сегодня» окажутся текущие задачи «Сегодня»
/// плюс отложенные, чья дата наступит к N (их перенесёт полуночный перенос).
enum NotificationPlanner {
    static let title = "Ваш план на сегодня"
    static let emptyBody = "Нет задач на сегодня"
    static let maxLines = 5

    static func plans(
        tasks: [TaskItem],
        hour: Int,
        minute: Int,
        now: Date,
        days: Int = 7,
        order: ([TaskItem]) -> [TaskItem] = { $0 }
    ) -> [DigestPlan] {
        let today = Day.today(now: now)
        return (0..<days).compactMap { offset in
            let day = today.adding(days: offset)
            guard let fire = Calendar.kota.date(bySettingHour: hour, minute: minute, second: 0, of: day.date()),
                  fire > now else { return nil }
            let due = tasks.filter { task in
                if task.status == .today { return true }
                if task.status == .stack, let deferred = task.deferredDate { return deferred <= day }
                return false
            }
            let ordered = order(due)
            return DigestPlan(day: day, fireDate: fire, body: body(for: ordered.map(\.title)), taskCount: ordered.count)
        }
    }

    /// Первые пять задач списком и «и ещё N…».
    static func body(for titles: [String]) -> String {
        guard !titles.isEmpty else { return emptyBody }
        var lines = titles.prefix(maxLines).map { "• \($0)" }
        if titles.count > maxLines {
            lines.append("и ещё \(titles.count - maxLines)…")
        }
        return lines.joined(separator: "\n")
    }
}
