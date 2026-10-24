import Foundation

/// Куда кладётся задача: в колонку (проект / без проекта / все) или внутрь родителя.
enum TaskContainer: Hashable, Sendable {
    case column(ProjectScope)
    case parent(String)
}

/// Операции доски. Каждая — одно действие ⌘Z.
extension TaskStore {

    /// Можно ли положить задачу сюда. Вложенность — один уровень: нельзя в себя, в подзадачу
    /// и нельзя вкладывать задачу, у которой уже есть свои подзадачи.
    func canPlace(_ taskId: String, into container: TaskContainer) -> Bool {
        guard task(id: taskId) != nil else { return false }
        switch container {
        case .column:
            return true
        case .parent(let parentId):
            guard parentId != taskId, let parent = task(id: parentId), parent.parentId == nil else { return false }
            return !TaskTree.hasChildren(taskId, in: tasks)
        }
    }

    /// Кладёт задачу в колонку или в родителя на позицию (`nil` — в конец).
    /// Подзадачи переезжают в проект родителя вместе с ним.
    @discardableResult
    func place(_ taskId: String, into container: TaskContainer, at position: Int?) -> Bool {
        guard canPlace(taskId, into: container), let moving = task(id: taskId) else { return false }
        let actionName: String = switch container {
        case .parent: "Вложение задачи"
        case .column: moving.parentId != nil ? "Вынос подзадачи" : "Перемещение задачи"
        }
        mutate(actionName) { s in Self.applyPlacement(&s.tasks, taskId: taskId, container: container, position: position) }
        return true
    }

    /// Кому задачу можно сделать подзадачей из контекстного меню: задачи её колонки, куда вложение допустимо.
    func nestCandidates(for id: String) -> [TaskItem] {
        guard let moving = task(id: id) else { return [] }
        let scope = Self.scope(of: moving.parentId.flatMap { task(id: $0) } ?? moving)
        return BoardQueries.topLevel(in: scope, all: tasks).filter {
            $0.id != moving.parentId && canPlace(id, into: .parent($0.id))
        }
    }

    /// Делает подзадачу отдельной задачей — в колонке родителя сразу после него.
    func makeStandalone(_ id: String) {
        guard let child = task(id: id), let parentId = child.parentId else { return }
        let scope = Self.scope(of: task(id: parentId) ?? child)
        let columnTasks = BoardQueries.topLevel(in: scope, all: tasks)
        let position = columnTasks.firstIndex { $0.id == parentId }.map { $0 + 1 }
        place(id, into: .column(scope), at: position)
    }

    /// Создание строкой, как в Напоминаниях: только название, остальное — умолчания.
    @discardableResult
    func quickAdd(title: String, into container: TaskContainer, now: Date = .now) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var task = TaskItem(title: trimmed, importance: .medium, status: .stack, created: now)
        switch container {
        case .column(let scope):
            task.duration = TaskItem.defaultDuration
            switch scope {
            case .none: task.projectId = nil
            case .project(let id): task.projectId = id
            case .all: break
            }
            task.sortIndex = ManualOrder.index(insertingAt: .max, among: BoardQueries.topLevel(in: scope, all: tasks))
        case .parent(let parentId):
            guard let parent = self.task(id: parentId), parent.parentId == nil else { return nil }
            task.duration = nil
            task.parentId = parentId
            task.projectId = parent.projectId
            task.sortIndex = ManualOrder.index(insertingAt: .max, among: TaskTree.children(of: parentId, in: tasks))
        }
        let created = task
        mutate("Создание задачи") { $0.tasks.append(created) }
        return created
    }

    /// Выполняет родителя. `closingSubtasks` — закрыть и открытые подзадачи; иначе они становятся
    /// отдельными задачами в той же колонке сразу под бывшим родителем.
    func completeParent(_ id: String, closingSubtasks: Bool, now: Date = .now) {
        mutate("Выполнение задачи") { s in
            guard let i = s.tasks.firstIndex(where: { $0.id == id }) else { return }
            let parent = s.tasks[i]
            let open = TaskTree.openChildren(of: id, in: s.tasks)
            if !closingSubtasks {
                let scope = Self.scope(of: parent)
                let column = BoardQueries.topLevel(in: scope, all: s.tasks)
                let lower = parent.sortIndex
                let upper = column.firstIndex { $0.id == id }
                    .flatMap { $0 + 1 < column.count ? column[$0 + 1].sortIndex : nil } ?? lower + 1
                for (k, child) in open.enumerated() {
                    guard let j = s.tasks.firstIndex(where: { $0.id == child.id }) else { continue }
                    s.tasks[j].parentId = nil
                    s.tasks[j].projectId = parent.projectId
                    s.tasks[j].sortIndex = lower + (upper - lower) * Double(k + 1) / Double(open.count + 1)
                }
            } else {
                for child in open {
                    guard let j = s.tasks.firstIndex(where: { $0.id == child.id }) else { continue }
                    s.tasks[j].status = .archive
                    s.tasks[j].completed = now
                }
            }
            s.tasks[i].status = .archive
            s.tasks[i].completed = now
            Self.renumberIfNeeded(&s.tasks, siblings: BoardQueries.topLevel(in: Self.scope(of: parent), all: s.tasks))
        }
    }

    /// Возвращает выполненную задачу в стек на прежнее место.
    func reopen(_ id: String) {
        mutate("Возврат задачи") { s in
            guard let i = s.tasks.firstIndex(where: { $0.id == id }), s.tasks[i].status == .archive else { return }
            s.tasks[i].status = .stack
            s.tasks[i].completed = nil
        }
    }

    /// Переставляет колонку проекта на позицию среди проектов («Без проекта» всегда первая).
    func moveProjectColumn(_ projectId: String, to position: Int) {
        mutate("Перестановка колонок") { s in
            let others = s.projects.filter { $0.id != projectId }
                .sorted { $0.sortIndex != $1.sortIndex ? $0.sortIndex < $1.sortIndex
                          : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard let i = s.projects.firstIndex(where: { $0.id == projectId }) else { return }
            s.projects[i].sortIndex = ManualOrder.index(insertingAt: position, amongIndices: others.map(\.sortIndex))
            let ordered = s.projects.sorted { $0.sortIndex < $1.sortIndex }
            if zip(ordered, ordered.dropFirst()).contains(where: { $1.sortIndex - $0.sortIndex < ManualOrder.minimumGap }) {
                for (n, project) in ordered.enumerated() {
                    if let j = s.projects.firstIndex(where: { $0.id == project.id }) { s.projects[j].sortIndex = Double(n) }
                }
            }
        }
    }

    /// Бросок шапки колонки на шапку другой: правее исходного места — встаёт после цели, левее — перед ней.
    /// Иначе последней колонку было бы не сделать.
    func moveProjectColumn(_ projectId: String, onto targetId: String) {
        let order = categories(.project).map(\.id)
        guard projectId != targetId, let from = order.firstIndex(of: projectId), let to = order.firstIndex(of: targetId) else { return }
        let others = order.filter { $0 != projectId }
        guard let target = others.firstIndex(of: targetId) else { return }
        moveProjectColumn(projectId, to: from < to ? target + 1 : target)
    }

    /// Один раз задаёт ручной порядок старым данным — тот, что пользователь видел в стеке.
    /// Системное действие, без записи в отмену.
    func seedManualOrderIfNeeded(mode: SortMode, context: SortContext) {
        guard needsOrderSeeding else { return }
        let order = BoardQueries.initialOrder(all: tasks, mode: mode, context: context)
        var next = snapshot
        for i in next.tasks.indices {
            if let index = order[next.tasks[i].id] { next.tasks[i].sortIndex = index }
        }
        let byName = next.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for (n, project) in byName.enumerated() {
            if let j = next.projects.firstIndex(where: { $0.id == project.id }) { next.projects[j].sortIndex = Double(n) }
        }
        apply(next)
        markOrderSeeded()
        save()
    }

    // MARK: - Внутреннее

    static func scope(of task: TaskItem) -> ProjectScope {
        task.projectId.map(ProjectScope.project) ?? .none
    }

    static func applyPlacement(_ tasks: inout [TaskItem], taskId: String, container: TaskContainer, position: Int?) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let siblings: [TaskItem] = switch container {
        case .column(let scope): BoardQueries.topLevel(in: scope, all: tasks).filter { $0.id != taskId }
        case .parent(let parentId): TaskTree.children(of: parentId, in: tasks).filter { $0.id != taskId }
        }
        tasks[i].sortIndex = ManualOrder.index(insertingAt: position ?? siblings.count, among: siblings)
        switch container {
        case .column(let scope):
            tasks[i].parentId = nil
            switch scope {
            case .none: tasks[i].projectId = nil
            case .project(let id): tasks[i].projectId = id
            case .all: break
            }
            let project = tasks[i].projectId
            for j in tasks.indices where tasks[j].parentId == taskId { tasks[j].projectId = project }
        case .parent(let parentId):
            tasks[i].parentId = parentId
            tasks[i].projectId = tasks.first { $0.id == parentId }?.projectId
        }
        let updated = ManualOrder.sorted(siblings + [tasks[i]])
        renumberIfNeeded(&tasks, siblings: updated)
    }

    static func renumberIfNeeded(_ tasks: inout [TaskItem], siblings: [TaskItem]) {
        guard ManualOrder.needsRenumbering(siblings) else { return }
        let map = ManualOrder.renumbered(siblings)
        for j in tasks.indices { if let index = map[tasks[j].id] { tasks[j].sortIndex = index } }
    }
}
