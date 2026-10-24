import Foundation

/// Как считается время задачи. Пока родитель и подзадачи связаны, по времени они одно целое,
/// а режим пользователь выбирает тем, где задаёт длительность.
enum TimeMode: Equatable, Sendable {
    /// Обычная задача без подзадач.
    case single(Int)
    /// «Большая задача»: время задано у родителя целиком.
    case bigTask(Int)
    /// «Блок задач»: у родителя своего времени нет, оно равно сумме открытых подзадач.
    case block(Int)
    /// Подзадача: своё время (если задано) и задано ли время у родителя.
    case subtask(own: Int?, parentHasOwn: Bool)
}

/// Связи родитель — подзадачи и итоговое время. Чистые функции над массивом задач.
enum TaskTree {

    /// Все подзадачи родителя в ручном порядке.
    static func children(of id: String, in all: [TaskItem]) -> [TaskItem] {
        ManualOrder.sorted(all.filter { $0.parentId == id })
    }

    /// Подзадачи, которые ещё не выполнены.
    static func openChildren(of id: String, in all: [TaskItem]) -> [TaskItem] {
        children(of: id, in: all).filter(\.isActive)
    }

    static func hasChildren(_ id: String, in all: [TaskItem]) -> Bool {
        all.contains { $0.parentId == id }
    }

    static func timeMode(_ task: TaskItem, in all: [TaskItem]) -> TimeMode {
        if let parentId = task.parentId {
            let parentHasOwn = all.first { $0.id == parentId }?.duration != nil
            return .subtask(own: task.duration, parentHasOwn: parentHasOwn)
        }
        guard hasChildren(task.id, in: all) else {
            return .single(task.duration ?? TaskItem.defaultDuration)
        }
        if let own = task.duration { return .bigTask(own) }
        let sum = openChildren(of: task.id, in: all).reduce(0) { $0 + ($1.duration ?? 0) }
        return .block(sum)
    }

    static func effectiveMinutes(_ task: TaskItem, in all: [TaskItem]) -> Int {
        switch timeMode(task, in: all) {
        case .single(let m), .bigTask(let m), .block(let m): m
        case .subtask(let own, _): own ?? 0
        }
    }

    /// Нагрузка дня без двойного счёта: подзадача, чей родитель тоже в «Сегодня»,
    /// уже входит во время родителя.
    static func todayLoadMinutes(_ all: [TaskItem]) -> Int {
        let todayIds = Set(all.lazy.filter { $0.status == .today }.map(\.id))
        return all.reduce(0) { total, task in
            guard task.status == .today else { return total }
            if let parentId = task.parentId, todayIds.contains(parentId) { return total }
            return total + effectiveMinutes(task, in: all)
        }
    }

    /// Итоговое время каждой задачи — чтобы не пересчитывать дерево при сортировке.
    static func effectiveMinutesMap(_ all: [TaskItem]) -> [String: Int] {
        Dictionary(all.map { ($0.id, effectiveMinutes($0, in: all)) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Подзадачи вне доски и в форме

    /// Подпись подзадачи в «Сегодня», архиве и папках: «↳ Родитель · Проект».
    /// `projectName` возвращает nil, если проекта нет или ось проектов выключена.
    static func parentLabel(for task: TaskItem, in all: [TaskItem], projectName: (String?) -> String?) -> String? {
        guard let parentId = task.parentId, let parent = all.first(where: { $0.id == parentId }) else { return nil }
        guard let project = projectName(parent.projectId) else { return "↳ \(parent.title)" }
        return "↳ \(parent.title) · \(project)"
    }

    /// Выполнить задачу сразу нельзя — сначала спросить, что делать с открытыми подзадачами.
    static func needsCompletionChoice(_ task: TaskItem, in all: [TaskItem]) -> Bool {
        !openChildren(of: task.id, in: all).isEmpty
    }

    /// Родитель и подзадача могут быть без своего времени; обычная задача — нет (30 мин по умолчанию).
    static func allowsEmptyDuration(_ task: TaskItem, in all: [TaskItem]) -> Bool {
        task.parentId != nil || hasChildren(task.id, in: all)
    }

    /// Подсказка под полем длительности: что значит пустое поле и не расходится ли время родителя с подзадачами.
    static func durationHint(for task: TaskItem, durationText: String, in all: [TaskItem]) -> String? {
        if task.parentId != nil { return "Пусто — время входит в родителя" }
        guard hasChildren(task.id, in: all) else { return nil }
        let childrenSum = openChildren(of: task.id, in: all).reduce(0) { $0 + ($1.duration ?? 0) }
        let parentHasOwn = !durationText.trimmingCharacters(in: .whitespaces).isEmpty
        if parentHasOwn && childrenSum > 0 { return "У подзадач в сумме \(RuFormat.minutes(childrenSum))" }
        return "Пусто — время считается из подзадач"
    }
}
