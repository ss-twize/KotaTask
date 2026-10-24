import Foundation

/// Уровень нагрузки дня — «светофор» на экранах «Сегодня» и «Стек».
enum LoadLevel: Sendable {
    case ok, warn, over
    /// Контроль перегрузки выключен: показываем объём, но без оценки.
    case neutral

    var title: String {
        switch self {
        case .ok: "В норме"
        case .warn: "Плотно"
        case .over: "Перегруз"
        case .neutral: "Без лимита"
        }
    }
}

struct DayLoad: Equatable, Sendable {
    static let limitRange = 120...960
    static let limitStep = 10
    static let defaultLimit = 180
    static let defaultBoost = 0.2

    var minutes: Int
    var count: Int
    var limit: Int
    var isControlEnabled: Bool

    /// Порог «Плотно» — половина лимита, целочисленно, как в Android.
    var halfMark: Int { limit / 2 }

    var level: LoadLevel {
        guard isControlEnabled else { return .neutral }
        if minutes < halfMark { return .ok }
        if minutes < limit { return .warn }
        return .over
    }

    /// Доля заполнения шкалы, 0…1.
    var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(Double(minutes) / Double(limit), 1)
    }
}
