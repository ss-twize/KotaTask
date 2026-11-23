import Foundation

/// Черновик формы: то, что пользователь набрал, до проверки.
struct TaskDraft: Equatable, Sendable {
    var title = ""
    var deadlineStart: Day?
    var deadline: Day?
    var importance: Importance = .medium
    var durationText = ""
    var purpose = ""
    var projectId: String?
    var locationId: String?
    var taskTypeId: String?

    init() {}

    init(task: TaskItem) {
        title = task.title
        deadlineStart = task.deadlineStart
        deadline = task.deadline
        importance = task.importance
        durationText = task.duration.map(String.init) ?? ""
        purpose = task.purpose
        projectId = task.projectId
        locationId = task.locationId
        taskTypeId = task.taskTypeId
    }

    func categoryId(for kind: CategoryKind) -> String? {
        switch kind {
        case .project: projectId
        case .location: locationId
        case .taskType: taskTypeId
        }
    }

    mutating func setCategoryId(_ id: String?, for kind: CategoryKind) {
        switch kind {
        case .project: projectId = id
        case .location: locationId = id
        case .taskType: taskTypeId = id
        }
    }
}

enum FormField: Hashable, Sendable {
    case title, deadlineStart, deadline, duration, purpose
    case category(CategoryKind)
}

/// Что видно в форме и что обязательно — снимок настроек на момент открытия формы.
struct FormConfig: Equatable, Sendable {
    var assistance: AssistanceLevel
    var customRequired: Set<RequirableField>
    var showDuration: Bool
    var showPurpose: Bool
    var visibleCategories: Set<CategoryKind>
    /// Родитель и подзадача могут быть без своего времени (режимы «Блок задач» и «Большая задача»).
    var allowsEmptyDuration: Bool = false

    static let everything = FormConfig(
        assistance: .minimal, customRequired: [], showDuration: true, showPurpose: true,
        visibleCategories: Set(CategoryKind.allCases)
    )

    func isVisible(_ field: RequirableField) -> Bool {
        switch field {
        case .deadlineStart, .deadline: true
        case .duration: showDuration
        case .purpose: showPurpose
        case .project, .location, .taskType: field.categoryKind.map(visibleCategories.contains) ?? false
        }
    }

    /// Обязательность по таблице уровней помощи. Скрытое поле обязательным не бывает —
    /// иначе оно заблокировало бы сохранение без возможности заполнить.
    func isRequired(_ field: RequirableField) -> Bool {
        guard isVisible(field) else { return false }
        switch assistance {
        case .minimal:
            return false
        case .standard:
            return field == .deadline
        case .advanced:
            return field == .deadline || field == .duration || field == .purpose
        case .custom:
            return customRequired.contains(field)
        }
    }
}

/// Проверенные значения, готовые к записи в задачу.
struct ValidatedTask: Equatable, Sendable {
    var title: String
    var deadlineStart: Day?
    var deadline: Day?
    var importance: Importance
    var duration: Int?
    var purpose: String
    var projectId: String?
    var locationId: String?
    var taskTypeId: String?

    func apply(to task: inout TaskItem) {
        task.title = title
        task.deadlineStart = deadlineStart
        task.deadline = deadline
        task.importance = importance
        task.duration = duration
        task.purpose = purpose
        task.projectId = projectId
        task.locationId = locationId
        task.taskTypeId = taskTypeId
        task.needsDetails = false
    }
}

enum ValidationOutcome: Equatable, Sendable {
    case valid(ValidatedTask)
    case invalid([FormField: String])
}

/// Валидация формы по уровню помощи — порт `AddTaskFragment.submitTask()`.
/// В отличие от Android возвращает сразу все ошибки, чтобы подсветить поля разом.
enum TaskValidator {

    static func validate(_ draft: TaskDraft, config: FormConfig) -> ValidationOutcome {
        var errors: [FormField: String] = [:]

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            errors[.title] = "Введите название задачи"
        }

        if config.isRequired(.deadline) && draft.deadline == nil {
            errors[.deadline] = "Укажите дедлайн"
        }

        if config.isRequired(.deadlineStart) && draft.deadlineStart == nil {
            errors[.deadlineStart] = "Укажите начало дедлайна"
        }
        if let start = draft.deadlineStart, let end = draft.deadline, start > end {
            errors[.deadlineStart] = "Начало не может быть позже дедлайна"
        }

        // Длительность 1…600 минут: 0 ломал расчёт приоритета, мусор вроде 999999 — график нагрузки.
        var duration: Int? = config.allowsEmptyDuration ? nil : TaskItem.defaultDuration
        let rawDuration = draft.durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawDuration.isEmpty {
            // У родителя и подзадачи пустое поле — это режим времени, а не пропуск.
            if config.isRequired(.duration) && !config.allowsEmptyDuration {
                errors[.duration] = "Укажите длительность"
            }
        } else if let value = Int(rawDuration), TaskItem.durationRange.contains(value) {
            duration = value
        } else {
            errors[.duration] = "Введите от 1 до 600 минут"
        }

        let purpose = draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        if config.isRequired(.purpose) && purpose.isEmpty {
            errors[.purpose] = "Опишите цель задачи"
        }

        for kind in CategoryKind.allCases {
            let field: RequirableField = switch kind {
            case .project: .project
            case .location: .location
            case .taskType: .taskType
            }
            if config.isRequired(field) && draft.categoryId(for: kind) == nil {
                errors[.category(kind)] = kind.requiredError
            }
        }

        guard errors.isEmpty else { return .invalid(errors) }
        return .valid(ValidatedTask(
            title: title,
            deadlineStart: draft.deadlineStart,
            deadline: draft.deadline,
            importance: draft.importance,
            duration: duration,
            purpose: purpose,
            projectId: draft.projectId,
            locationId: draft.locationId,
            taskTypeId: draft.taskTypeId
        ))
    }
}
