import Foundation

/// Ячейка месячной сетки.
struct CalendarCell: Identifiable, Hashable, Sendable {
    let day: Day
    let isCurrentMonth: Bool
    var id: Day { day }
}

/// Цвет сектора «пончика» — по приоритету правил Android `CalendarCellView.taskColor`.
enum DonutTone: Sendable {
    case deferred, today, high, medium, low
}

enum CalendarMonth {

    /// Сетка месяца с понедельника: добираем дни соседних месяцев до полных недель.
    static func cells(for month: YearMonth) -> [CalendarCell] {
        let first = month.firstDay
        let leading = first.weekdayIndex
        let total = leading + month.numberOfDays
        let rows = Int((Double(total) / 7).rounded(.up))
        let start = first.adding(days: -leading)
        return (0..<(rows * 7)).map { offset in
            let day = start.adding(days: offset)
            return CalendarCell(day: day, isCurrentMonth: day.year == month.year && day.month == month.month)
        }
    }

    /// Радиус сектора как доля максимального: экспоненциальное насыщение.
    /// 0 мин → 0.52, 60 мин → ~0.82, 240 мин → ~0.99; длиннее — асимптотически 1.0.
    static func radiusRatio(durationMinutes: Int) -> Double {
        let d = Double(max(durationMinutes, 0))
        let progress = 1 - exp(-d / 60)
        return 0.52 + progress * 0.48
    }

    static func tone(for task: TaskItem, on day: Day) -> DonutTone {
        if let deferred = task.deferredDate, deferred == day { return .deferred }
        if task.status == .today { return .today }
        switch task.importance {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}
