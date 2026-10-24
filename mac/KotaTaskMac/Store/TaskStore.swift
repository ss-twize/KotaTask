import Foundation
import Observation
import SwiftUI

/// Единственный источник правды о задачах и категориях. Аналог связки
/// `TaskViewModel` + репозитории + Room в Android.
///
/// Каждое пользовательское изменение снимает снимок «до» и регистрирует его в
/// `UndoManager` окна — так ⌘Z отменяет выполнение, удаление, перенос и правку.
@MainActor
@Observable
final class TaskStore {
    private(set) var tasks: [TaskItem] = []
    private(set) var projects: [Category] = []
    private(set) var locations: [Category] = []
    private(set) var taskTypes: [Category] = []

    /// Растёт при каждом изменении — на него подписаны уведомления.
    private(set) var revision = 0

    /// Проблема с файлом данных, которую нужно показать пользователю.
    var alertMessage: String?

    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private let persistence: Persistence?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// Пока файл не прочитан, писать нельзя: иначе пустой снимок затрёт задачи
    /// (например, если приложение закроют до появления окна).
    @ObservationIgnored private var isLoaded = false
    /// Файл старого формата (без ручного порядка) — порядок нужно задать один раз.
    /// См. `seedManualOrderIfNeeded`.
    private(set) var needsOrderSeeding = false

    /// `persistence == nil` — хранилище в памяти (тесты, превью).
    init(persistence: Persistence?) {
        self.persistence = persistence
    }

    // MARK: - Загрузка и запись

    func load() {
        guard let persistence else { return }
        switch persistence.load() {
        case .empty:
            break
        case .loaded(let snapshot):
            apply(snapshot)
            needsOrderSeeding = snapshot.formatVersion < 2
        case .recovered(let snapshot, let message):
            apply(snapshot)
            needsOrderSeeding = snapshot.formatVersion < 2
            alertMessage = message
            isLoaded = true
            save()
        case .failed(let message):
            // Повреждённый файл уже отложен в сторону — новый можно писать с чистого листа.
            alertMessage = message
        }
        isLoaded = true
    }

    /// Немедленная запись (выход из приложения).
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        writeNow()
    }

    private func writeNow() {
        guard let persistence, isLoaded else { return }
        do {
            try persistence.save(snapshot)
        } catch {
            alertMessage = "Не удалось сохранить данные: \(error.localizedDescription)"
        }
    }

    /// Запись с задержкой: серию быстрых изменений пишем одним файлом.
    func save() {
        revision += 1
        guard persistence != nil else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    /// Файл данных — для «Показать в Finder».
    var dataFileURL: URL? { persistence?.fileURL }

    var snapshot: StoreSnapshot {
        StoreSnapshot(tasks: tasks, projects: projects, locations: locations, taskTypes: taskTypes)
    }

    func apply(_ s: StoreSnapshot) {
        tasks = s.tasks
        projects = s.projects
        locations = s.locations
        taskTypes = s.taskTypes
    }

    // MARK: - Отмена

    /// Выполняет изменение и регистрирует его отмену под именем `actionName`.
    func mutate(_ actionName: String, _ body: (inout StoreSnapshot) -> Void) {
        let before = snapshot
        var after = before
        body(&after)
        guard after != before else { return }
        apply(after)
        registerUndo(restoring: before, actionName: actionName)
        save()
    }

    private func registerUndo(restoring target: StoreSnapshot, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let current = store.snapshot
                withAnimation(Motion.standard) { store.apply(target) }
                // Регистрация внутри отмены становится повтором (⇧⌘Z).
                store.registerUndo(restoring: current, actionName: actionName)
                store.save()
                // Снимок мог быть снят до полуночи: отложенная задача, чей день уже
                // наступил, вернулась бы в стек и застряла там до следующей смены дня.
                store.promoteDueDeferred(today: .today())
            }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - Чтение

    func task(id: String) -> TaskItem? { tasks.first { $0.id == id } }

    func categories(_ kind: CategoryKind) -> [Category] {
        let list: [Category] = switch kind {
        case .project: projects
        case .location: locations
        case .taskType: taskTypes
        }
        // Проекты — в порядке колонок доски, остальные оси — по имени.
        return list.sorted {
            if kind == .project, $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func category(_ kind: CategoryKind, id: String?) -> Category? {
        guard let id else { return nil }
        return snapshot.categories(kind).first { $0.id == id }
    }

    func categoryName(_ kind: CategoryKind, id: String?) -> String? {
        category(kind, id: id)?.name
    }

    var projectNames: [String: String] {
        Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Задачи

    @discardableResult
    func addTask(_ values: ValidatedTask, now: Date = .now) -> TaskItem {
        var task = TaskItem(title: values.title, status: .stack, created: now)
        values.apply(to: &task)
        // В конец своей колонки, как задача, созданная строкой.
        task.sortIndex = ManualOrder.index(insertingAt: .max, among: BoardQueries.topLevel(in: Self.scope(of: task), all: tasks))
        let created = task
        mutate("Создание задачи") { $0.tasks.append(created) }
        return created
    }

    func updateTask(id: String, with values: ValidatedTask) {
        mutate("Изменение задачи") { s in
            guard let i = s.tasks.firstIndex(where: { $0.id == id }) else { return }
            let parent = s.tasks[i].parentId.flatMap { parentId in s.tasks.first { $0.id == parentId } }
            let oldProject = s.tasks[i].projectId
            values.apply(to: &s.tasks[i])
            // Подзадачи всегда в проекте родителя: у подзадачи проект не меняется,
            // а сменил его родитель — переезжают и подзадачи.
            if let parent { s.tasks[i].projectId = parent.projectId }
            let project = s.tasks[i].projectId
            // Сменили проект в форме — задача встаёт в конец новой колонки, а не на случайное место.
            if parent == nil, project != oldProject {
                let column = BoardQueries.topLevel(in: Self.scope(of: s.tasks[i]), all: s.tasks).filter { $0.id != id }
                s.tasks[i].sortIndex = ManualOrder.index(insertingAt: .max, among: column)
            }
            for j in s.tasks.indices where s.tasks[j].parentId == id { s.tasks[j].projectId = project }
        }
    }

    func complete(id: String, now: Date = .now) {
        modifyTask(id, actionName: "Выполнение задачи") {
            $0.status = .archive
            $0.completed = now
        }
    }

    /// Ручной перенос в «Сегодня» снимает отложенность.
    func moveToToday(id: String) {
        modifyTask(id, actionName: "Перенос в «Сегодня»") {
            $0.status = .today
            $0.deferredDate = nil
        }
    }

    func moveToStack(id: String) {
        modifyTask(id, actionName: "Перенос в стек") { $0.status = .stack }
    }

    func deferTask(id: String, to day: Day) {
        modifyTask(id, actionName: "Откладывание задачи") { $0.deferredDate = day }
    }

    func undefer(id: String) {
        modifyTask(id, actionName: "Снятие отложенности") { $0.deferredDate = nil }
    }

    /// Удаляет задачу вместе с её подзадачами.
    func delete(id: String) {
        mutate("Удаление задачи") { s in s.tasks.removeAll { $0.id == id || $0.parentId == id } }
    }

    func delete(ids: Set<String>) {
        mutate(ids.count == 1 ? "Удаление задачи" : "Удаление задач") { s in
            s.tasks.removeAll { ids.contains($0.id) || ($0.parentId.map(ids.contains) ?? false) }
        }
    }

    func clearArchive() {
        mutate("Очистка архива") { $0.tasks.removeAll { $0.status == .archive } }
    }

    /// Переносит в «Сегодня» отложенные задачи, чей день наступил. Системное действие,
    /// поэтому без записи в отмену. Возвращает число перенесённых задач.
    @discardableResult
    func promoteDueDeferred(today: Day) -> Int {
        var count = 0
        var next = tasks
        for i in next.indices {
            guard next[i].status == .stack, let day = next[i].deferredDate, day <= today else { continue }
            next[i].status = .today
            next[i].deferredDate = nil
            count += 1
        }
        guard count > 0 else { return 0 }
        withAnimation(Motion.standard) { tasks = next }
        save()
        return count
    }

    private func modifyTask(_ id: String, actionName: String, _ change: (inout TaskItem) -> Void) {
        mutate(actionName) { s in
            guard let i = s.tasks.firstIndex(where: { $0.id == id }) else { return }
            change(&s.tasks[i])
        }
    }

    // MARK: - Категории

    @discardableResult
    func addCategory(_ kind: CategoryKind, name: String) -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var category = Category(name: trimmed)
        if kind == .project {
            // Новый проект встаёт последней колонкой.
            category.sortIndex = (projects.map(\.sortIndex).max() ?? -1) + 1
        }
        mutate("Создание: \(kind.singularTitle.lowercased())") { s in
            s.setCategories(s.categories(kind) + [category], for: kind)
        }
        return category
    }

    func renameCategory(_ kind: CategoryKind, id: String, to name: String, now: Date = .now) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate("Переименование") { s in
            var list = s.categories(kind)
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].name = trimmed
            list[i].updated = now
            s.setCategories(list, for: kind)
        }
    }

    /// Удаляет категорию и отвязывает от неё задачи — задачи не пропадают.
    func deleteCategory(_ kind: CategoryKind, id: String) {
        mutate("Удаление: \(kind.singularTitle.lowercased())") { s in
            s.setCategories(s.categories(kind).filter { $0.id != id }, for: kind)
            for i in s.tasks.indices where s.tasks[i].categoryId(for: kind) == id {
                s.tasks[i].setCategoryId(nil, for: kind)
            }
        }
    }

    /// Порядок задан — больше не сидировать.
    func markOrderSeeded() { needsOrderSeeding = false }

    /// Для тестов и превью.
    func replaceAll(with snapshot: StoreSnapshot) {
        apply(snapshot)
        save()
    }
}
