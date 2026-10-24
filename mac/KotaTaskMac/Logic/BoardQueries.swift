import Foundation

/// Какая колонка: без проекта, конкретный проект или все задачи сразу
/// (когда ось «Проекты» выключена — тогда проект задачи не учитывается).
enum ProjectScope: Hashable, Sendable {
    case none
    case project(String)
    case all

    func contains(_ task: TaskItem) -> Bool {
        switch self {
        case .none: task.projectId == nil
        case .project(let id): task.projectId == id
        case .all: true
        }
    }
}

/// Колонка доски «Общий».
struct BoardColumn: Identifiable, Sendable {
    let scope: ProjectScope
    let title: String
    /// Активные задачи верхнего уровня в ручном порядке.
    let tasks: [TaskItem]
    var id: ProjectScope { scope }
}

/// Выборки доски. Чистые функции.
enum BoardQueries {
    static let noProjectTitle = "Без проекта"

    /// «Без проекта», затем проекты по `sortIndex` и имени.
    static func columns(all: [TaskItem], projects: [Category]) -> [BoardColumn] {
        let ordered = projects.filter { !$0.hiddenOnBoard }.sorted {
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return [BoardColumn(scope: .none, title: noProjectTitle, tasks: topLevel(in: .none, all: all))]
            + ordered.map { BoardColumn(scope: .project($0.id), title: $0.name, tasks: topLevel(in: .project($0.id), all: all)) }
    }

    /// Активные задачи верхнего уровня колонки в ручном порядке.
    static func topLevel(in scope: ProjectScope, all: [TaskItem]) -> [TaskItem] {
        ManualOrder.sorted(all.filter { $0.parentId == nil && $0.isActive && scope.contains($0) })
    }

    /// Подходит ли карточка под поиск и фильтры. Родитель подходит, если подходит он сам
    /// или любая его подзадача, — иначе поиск по подзадаче не находил бы ничего.
    static func matches(_ task: TaskItem, query: String, location: CategoryFilter, taskType: CategoryFilter, all: [TaskItem]) -> Bool {
        let family = [task] + TaskTree.children(of: task.id, in: all)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return family.contains { member in
            let textOK = q.isEmpty || member.title.localizedCaseInsensitiveContains(q)
                || member.purpose.localizedCaseInsensitiveContains(q)
            return textOK && location.matches(member.locationId) && taskType.matches(member.taskTypeId)
        }
    }

    /// Начальный ручной порядок для старых данных: тот, что пользователь видел в стеке.
    /// Индексы 0, 1, 2… для каждой колонки и для подзадач каждого родителя.
    static func initialOrder(all: [TaskItem], mode: SortMode, context: SortContext) -> [String: Double] {
        var result: [String: Double] = [:]
        func assign(_ group: [TaskItem]) {
            for (i, task) in TaskQueries.sort(group, by: mode, context: context).enumerated() {
                result[task.id] = Double(i)
            }
        }
        let topLevel = all.filter { $0.parentId == nil }
        for group in Dictionary(grouping: topLevel, by: \.projectId).values { assign(group) }
        for group in Dictionary(grouping: all.filter { $0.parentId != nil }, by: \.parentId).values { assign(group) }
        return result
    }
}
