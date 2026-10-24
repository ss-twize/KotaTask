import Foundation

/// Веса четырёх факторов приоритета. Сумма не нормализуется — как в Android.
struct Coefficients: Equatable, Sendable {
    var deadline: Double
    var importance: Double
    var duration: Double
    var age: Double

    /// Рабочие дефолты Android (`TaskViewModel.getCoefficients()`), не те, что в `data class`.
    static let defaults = Coefficients(deadline: 0.45, importance: 0.35, duration: 0.10, age: 0.10)
}

/// Контекст нагрузки дня для бонуса коротких задач.
struct LoadContext: Equatable, Sendable {
    var dayLoadMinutes: Int
    var overloadLimitMinutes: Int
    var loadDurationBoost: Double

    /// Контроль перегрузки выключен: порог недостижим, бонуса нет (как в `applySortMode`).
    static func disabled(dayLoadMinutes: Int) -> LoadContext {
        LoadContext(dayLoadMinutes: dayLoadMinutes, overloadLimitMinutes: Int.max / 2, loadDurationBoost: 0)
    }
}

/// Порт `util/PriorityCalculator.kt`. Чистые функции: «сейчас» и «сегодня» передаются явно.
enum PriorityCalculator {

    /// `minutes` — итоговое время задачи (см. `TaskTree.effectiveMinutes`): у родителя-блока это сумма подзадач.
    static func score(
        _ task: TaskItem,
        minutes: Int,
        coefficients c: Coefficients,
        load: LoadContext,
        today: Day,
        now: Date
    ) -> Double {
        deadlineScore(task.deadline, today: today) * c.deadline
            + importanceScore(task.importance) * c.importance
            + durationScore(
                minutes: minutes,
                dayLoad: load.dayLoadMinutes,
                overloadLimit: load.overloadLimitMinutes,
                boost: load.loadDurationBoost
            ) * c.duration
            + ageScore(created: task.created, now: now) * c.age
    }

    /// Пять зон срочности. Без дедлайна — 0.3: «когда-нибудь» чуть срочнее, чем «точно не скоро».
    static func deadlineScore(_ deadline: Day?, today: Day) -> Double {
        guard let deadline else { return 0.3 }
        let daysUntil = today.days(until: deadline)
        switch daysUntil {
        case ..<0: return 1.0
        case 0: return 0.9
        case 1...3: return 0.7
        case 4...7: return 0.5
        default: return 0.2
        }
    }

    static func importanceScore(_ importance: Importance) -> Double {
        switch importance {
        case .high: 1.0
        case .medium: 0.6
        case .low: 0.2
        }
    }

    /// Короткие задачи ценнее; когда нагрузка дня выше половины порога — бонус.
    static func durationScore(minutes: Int, dayLoad: Int, overloadLimit: Int, boost: Double) -> Double {
        let base: Double = switch minutes {
        case ...15: 1.0
        case ...30: 0.8
        case ...60: 0.6
        case ...120: 0.4
        default: 0.2
        }
        let boostThreshold = max(overloadLimit, 1) / 2
        let bonus = dayLoad > boostThreshold ? min(max(boost, 0), 1) : 0
        return min(base + bonus, 1.0)
    }

    /// Линейный рост за первые 5 дней. Дни — целое деление миллисекунд, как в Kotlin.
    static func ageScore(created: Date, now: Date) -> Double {
        let elapsedMs = now.milliseconds - created.milliseconds
        let daysOld = elapsedMs / 86_400_000
        if daysOld >= 5 { return 1.0 }
        return min(max(Double(daysOld) / 5.0, 0), 1)
    }
}
