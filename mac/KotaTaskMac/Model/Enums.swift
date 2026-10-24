import Foundation

/// Статус задачи. Сырые значения — русские литералы, как в Android (ADR-007),
/// поэтому JSON совместим с `kotatask_backup.json`.
enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case stack = "Стек"
    case today = "Сегодня"
    case archive = "Архив"

    var isActive: Bool { self != .archive }
}

enum Importance: String, CaseIterable, Identifiable, Sendable {
    case high = "Высокая"
    case medium = "Средняя"
    case low = "Низкая"

    var id: String { rawValue }
    var title: String { rawValue }

    /// Порядок сортировки «Важность»: высокая → средняя → низкая.
    var rank: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }
}

extension Importance: Codable {
    /// Неизвестное значение трактуется как «Средняя» — так же, как `else -> 0.6f` в Android.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Importance(rawValue: raw) ?? .medium
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum SortMode: String, CaseIterable, Identifiable, Sendable {
    case priority, importance, deadline, age, alphabetical, byProject, duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priority: "По приоритету"
        case .importance: "Важность"
        case .deadline: "Дедлайн"
        case .age: "Возраст задачи"
        case .alphabetical: "По алфавиту"
        case .byProject: "По проектам"
        case .duration: "По времени"
        }
    }

    var symbol: String {
        switch self {
        case .priority: "wand.and.stars"
        case .importance: "flag"
        case .deadline: "calendar.badge.clock"
        case .age: "hourglass"
        case .alphabetical: "textformat"
        case .byProject: "folder"
        case .duration: "timer"
        }
    }
}

/// Три независимые оси категоризации (ADR-006).
enum CategoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case project, location, taskType

    var id: String { rawValue }

    var pluralTitle: String {
        switch self {
        case .project: "Проекты"
        case .location: "Локации"
        case .taskType: "Типы задач"
        }
    }

    var singularTitle: String {
        switch self {
        case .project: "Проект"
        case .location: "Локация"
        case .taskType: "Тип задачи"
        }
    }

    /// Подпись системной папки задач без категории.
    var noneTitle: String {
        switch self {
        case .project: "Без проекта"
        case .location: "Без локации"
        case .taskType: "Без типа"
        }
    }

    /// Плейсхолдер пикера в форме.
    var notSelectedTitle: String {
        switch self {
        case .project: "Не выбран"
        case .location: "Не выбрана"
        case .taskType: "Не выбран"
        }
    }

    var addTitle: String {
        switch self {
        case .project: "Добавить проект…"
        case .location: "Добавить локацию…"
        case .taskType: "Добавить тип задачи…"
        }
    }

    var newItemPrompt: String {
        switch self {
        case .project: "Новый проект"
        case .location: "Новая локация"
        case .taskType: "Новый тип задачи"
        }
    }

    var requiredError: String {
        switch self {
        case .project: "Выберите проект"
        case .location: "Выберите локацию"
        case .taskType: "Выберите тип задачи"
        }
    }

    /// Подпись фильтра на экране стека («Локация: все» / «Без локации»).
    var filterLabel: String {
        switch self {
        case .project: "Проект"
        case .location: "Локация"
        case .taskType: "Тип"
        }
    }

    var symbol: String {
        switch self {
        case .project: "folder"
        case .location: "mappin.and.ellipse"
        case .taskType: "tag"
        }
    }
}

/// Уровень помощи при создании задачи — сколько полей обязательно.
enum AssistanceLevel: String, CaseIterable, Identifiable, Sendable {
    case minimal, standard, advanced, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: "Минимальный"
        case .standard: "Стандартный"
        case .advanced: "Продвинутый"
        case .custom: "Свой"
        }
    }

    var subtitle: String {
        switch self {
        case .minimal: "Только название задачи"
        case .standard: "Название, дедлайн, важность"
        case .advanced: "Все основные поля обязательны"
        case .custom: "Настройте обязательные поля вручную"
        }
    }
}

enum CalendarMode: String, CaseIterable, Identifiable, Sendable {
    case range, point

    var id: String { rawValue }

    var title: String {
        switch self {
        case .range: "Весь диапазон"
        case .point: "Только в день дедлайна"
        }
    }

    var shortTitle: String {
        switch self {
        case .range: "Диапазон"
        case .point: "Точка"
        }
    }

    var subtitle: String {
        switch self {
        case .range: "Задача видна каждый день диапазона"
        case .point: "Задача видна только в день срока"
        }
    }
}

enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case light, dark, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Светлая"
        case .dark: "Тёмная"
        case .system: "Как в системе"
        }
    }

    var symbol: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .system: "circle.lefthalf.filled"
        }
    }
}

/// Поля формы, которые можно сделать обязательными на уровне «Свой».
/// «Важность» из Android сюда не входит: у неё всегда есть значение, и требование
/// там ни на что не влияло — пользователь видел неработающий переключатель.
enum RequirableField: String, CaseIterable, Identifiable, Sendable {
    case deadlineStart, deadline, duration, purpose, project, location, taskType

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deadlineStart: "Начало дедлайна"
        case .deadline: "Дедлайн"
        case .duration: "Продолжительность"
        case .purpose: "Цель / назначение"
        case .project: "Проект"
        case .location: "Локация"
        case .taskType: "Тип задачи"
        }
    }

    var defaultsKey: String {
        switch self {
        case .deadlineStart: "custom_req_deadline_start"
        case .deadline: "custom_req_deadline"
        case .duration: "custom_req_duration"
        case .purpose: "custom_req_purpose"
        case .project: "custom_req_project"
        case .location: "custom_req_location"
        case .taskType: "custom_req_task_type"
        }
    }

    var categoryKind: CategoryKind? {
        switch self {
        case .project: .project
        case .location: .location
        case .taskType: .taskType
        default: nil
        }
    }
}
