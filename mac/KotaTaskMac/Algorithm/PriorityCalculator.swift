import Foundation

struct PriorityWeights {
    let urgency: Double
    let importance: Double
    let effort: Double
    let deadline: Double

    static let `default` = PriorityWeights(
        urgency: 0.35,
        importance: 0.30,
        effort: 0.20,
        deadline: 0.15
    )

    static func from(settings: AppSettings) -> PriorityWeights {
        PriorityWeights(
            urgency: settings.weightUrgency,
            importance: settings.weightImportance,
            effort: settings.weightEffort,
            deadline: settings.weightDeadline
        )
    }
}

struct PriorityCalculator {

    /// Рассчитывает приоритет задачи. Возвращает значение 0–100.
    static func calculate(
        urgency: Int,
        importance: Int,
        effort: Int,
        dueDate: Date?,
        weights: PriorityWeights
    ) -> Double {
        let urgencyScore    = Double(urgency) / 5.0
        let importanceScore = Double(importance) / 5.0
        let effortScore     = 1.0 - (Double(effort) / 5.0)
        let deadlineScore   = deadlineFactor(dueDate: dueDate)

        let raw = urgencyScore    * weights.urgency
                + importanceScore * weights.importance
                + effortScore     * weights.effort
                + deadlineScore   * weights.deadline

        return (raw * 100).rounded()
    }

    /// Удобный вариант: принимает AppTask и AppSettings.
    static func calculate(task: AppTask, settings: AppSettings) -> Double {
        calculate(
            urgency: task.urgency,
            importance: task.importance,
            effort: task.effort,
            dueDate: task.dueDate,
            weights: PriorityWeights.from(settings: settings)
        )
    }

    /// Дедлайн-фактор: 0.0 (нет дедлайна) → 1.0 (просрочено).
    static func deadlineFactor(dueDate: Date?) -> Double {
        guard let due = dueDate else { return 0.0 }
        let days = Calendar.current.dateComponents([.day], from: .now, to: due).day ?? 0
        switch days {
        case ..<0:   return 1.0
        case 0...1:  return 0.9
        case 2...3:  return 0.7
        case 4...7:  return 0.5
        default:     return 0.2
        }
    }
}
