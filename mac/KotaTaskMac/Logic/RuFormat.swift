import Foundation

/// Русские форматы дат и склонения. Локаль зашита, как и в Android:
/// интерфейс только русский, и системная локаль не должна ломать формат.
enum RuFormat {
    static let locale = Locale(identifier: "ru_RU")

    /// Склонение по числу: 1 задача, 2 задачи, 5 задач.
    static func plural(_ n: Int, one: String, few: String, many: String) -> String {
        let n100 = abs(n) % 100, n10 = abs(n) % 10
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    static func taskWord(_ n: Int) -> String {
        plural(n, one: "задача", few: "задачи", many: "задач")
    }

    static func tasksCount(_ n: Int) -> String { "\(n) \(taskWord(n))" }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = .kota
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = template
        return f
    }

    private static let dayMonthFormatter = formatter("d MMM")
    private static let monthYearFormatter = formatter("LLLL yyyy")
    private static let archiveFormatter = formatter("dd MMM yyyy, HH:mm")
    private static let longFormatter: DateFormatter = {
        let f = formatter("")
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()
    private static let weekdayFormatter = formatter("EEEE")

    /// «5 июн.»
    static func dayMonth(_ day: Day) -> String { dayMonthFormatter.string(from: day.date()) }

    /// «Октябрь 2026»
    static func monthYear(_ month: YearMonth) -> String {
        monthYearFormatter.string(from: month.firstDay.date()).capitalizedFirstLetter
    }

    /// «22 октября 2026 г.»
    static func long(_ day: Day) -> String { longFormatter.string(from: day.date()) }

    /// «Четверг»
    static func weekday(_ day: Day) -> String { weekdayFormatter.string(from: day.date()).capitalizedFirstLetter }

    /// «22 окт. 2026, 14:05» — время выполнения в архиве.
    static func archiveStamp(_ date: Date) -> String { archiveFormatter.string(from: date) }

    static let weekdaySymbols = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    /// Подпись чипа дедлайна: «Просрочено · 3 июн.», «Сегодня», «5 июн.» или диапазон «1 июн. → 5 июн.».
    static func deadlineChip(start: Day?, end: Day, today: Day) -> String {
        let endText: String
        if end < today {
            endText = "Просрочено · \(dayMonth(end))"
        } else if end == today {
            endText = "Сегодня"
        } else {
            endText = dayMonth(end)
        }
        if let start, start != end {
            return "\(dayMonth(start)) → \(endText)"
        }
        return endText
    }

    /// Нейтральная подпись срока без оценки срочности: «5 июн.» или «1 июн. → 5 июн.».
    static func dateRange(start: Day?, end: Day) -> String {
        if let start, start != end { return "\(dayMonth(start)) → \(dayMonth(end))" }
        return dayMonth(end)
    }

    /// Подпись кнопки отложенной задачи: «До 5 июн.».
    static func deferChip(_ day: Day) -> String { "До \(dayMonth(day))" }

    static func minutes(_ n: Int) -> String { "\(n) мин" }

    /// Время уведомления «08:00».
    static func time(hour: Int, minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
