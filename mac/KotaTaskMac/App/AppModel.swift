import AppKit
import Observation
import SwiftUI

/// Пункт сайдбара.
enum SidebarItem: Hashable {
    case today
    /// «Проекты → Общий»: доска с колонками-проектами (или список «Задачи», если проекты выключены).
    case board
    /// Лист одного проекта.
    case project(String)
    case calendar
    case archive
    /// Папка категории; `id == nil` — системная папка «Без …».
    case category(CategoryKind, String?)
}

/// Что открыть в форме задачи.
struct TaskFormRequest: Identifiable {
    enum Mode: Equatable {
        case create(prefill: CategoryKind?, categoryId: String?)
        case edit(taskId: String)
    }

    let id = UUID()
    let mode: Mode
}

/// Действие с задачей с карточки или из контекстного меню.
enum TaskAction {
    case complete, toToday, toStack, delete, edit, undefer
    case deferTo(Day)
}

/// Короткое подтверждение внизу окна с кнопкой «Отменить».
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let symbol: String
    let tint: Color
    let undoable: Bool
    /// Ревизия хранилища сразу после действия. Кнопка «Отменить» видна, только пока
    /// после него ничего не менялось, — иначе она отменила бы чужое действие.
    let revision: Int
}

/// Редактирование категории через алерт с полем ввода.
struct CategoryEdit: Identifiable {
    enum Mode { case create, rename(Category) }
    let id = UUID()
    let kind: CategoryKind
    let mode: Mode
    /// Выбрать созданную категорию в форме задачи.
    var onCreated: ((Category) -> Void)?
}

/// Корневое состояние приложения: хранилище, настройки, навигация и модальные окна.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// Под тестами хостовое приложение не должно трогать настоящие данные и уведомления.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Папка данных для отладки из переменной `KOTATASK_DATA_DIR` (только Debug-сборка).
    static var debugSandboxDirectory: URL? {
        #if DEBUG
        ProcessInfo.processInfo.environment["KOTATASK_DATA_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        #else
        nil
        #endif
    }

    let store: TaskStore
    let settings: AppSettings
    let clock = DayClock()
    let notifications = NotificationScheduler()
    let boardDrag = BoardDragState()

    var selection: SidebarItem? = .today
    var formRequest: TaskFormRequest?
    var toast: Toast?
    var categoryEdit: CategoryEdit?
    var categoryPendingDeletion: (kind: CategoryKind, category: Category)?
    var taskPendingDeletion: TaskItem?
    /// Родитель с открытыми подзадачами, которого просят выполнить, — ждёт ответа в диалоге.
    var parentPendingCompletion: TaskItem?
    /// Раскрытые подзадачи на доске — переживают смену экрана.
    var expandedParents: Set<String> = []

    @ObservationIgnored private var toastDismissal: Task<Void, Never>?
    @ObservationIgnored private var started = false

    private init() {
        if Self.isRunningTests {
            store = TaskStore(persistence: nil)
            settings = AppSettings(defaults: UserDefaults(suiteName: "KotaTask.TestHost") ?? .standard)
        } else if let sandbox = Self.debugSandboxDirectory {
            // Отладка: отдельная папка данных и отдельные настройки, настоящие не трогаем.
            store = TaskStore(persistence: Persistence(directory: sandbox))
            settings = AppSettings(defaults: UserDefaults(suiteName: "KotaTask.Sandbox") ?? .standard)
        } else {
            store = TaskStore(persistence: .standard())
            settings = AppSettings()
        }
    }

    // MARK: - Запуск

    func start() {
        guard !started else { return }
        started = true
        store.load()
        store.seedManualOrderIfNeeded(mode: settings.defaultSortMode, context: sortContext)
        applyTheme()
        if selection == .today && !settings.splitToday { selection = .board }

        guard !Self.isRunningTests else { return }
        clock.onDayChange = { [weak self] day in self?.dayDidChange(day) }
        clock.start()
        // Догоняем переносы, пропущенные, пока приложение было закрыто.
        store.promoteDueDeferred(today: clock.today)
        notifications.configure()
        rescheduleNotifications()
    }

    private func dayDidChange(_ day: Day) {
        let moved = store.promoteDueDeferred(today: day)
        if moved > 0 {
            showToast("В «Сегодня» перенесено: \(RuFormat.tasksCount(moved))", symbol: "sunrise", tint: Palette.deferPurple, undoable: false)
        }
        rescheduleNotifications()
    }

    func applyTheme() {
        NSApp?.appearance = switch settings.theme {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }

    func rescheduleNotifications() {
        guard !Self.isRunningTests else { return }
        let context = sortContext
        notifications.reschedule(
            tasks: store.tasks,
            enabled: settings.notificationsEnabled,
            hour: settings.notificationHour,
            minute: settings.notificationMinute,
            order: { TaskQueries.sort($0, by: .priority, context: context) }
        )
    }

    /// Флаги поменялись — уводим выделение с исчезнувших разделов.
    func normalizeSelection() {
        switch selection {
        case .today where !settings.splitToday:
            selection = .board
        case .calendar where !settings.calendarEnabled:
            selection = settings.splitToday ? .today : .board
        case .project(let id):
            if !settings.projectsEnabled || store.category(.project, id: id) == nil { selection = .board }
        case .category(let kind, let id):
            if !settings.isCategoryEnabled(kind) || (id != nil && store.category(kind, id: id) == nil) {
                selection = settings.splitToday ? .today : .board
            }
        case nil:
            selection = settings.splitToday ? .today : .board
        default:
            break
        }
    }

    // MARK: - Производные данные для экранов

    var sortContext: SortContext {
        SortContext(
            coefficients: settings.coefficients,
            load: settings.loadContext(todayMinutes: TaskQueries.todayLoadMinutes(store.tasks)),
            projectNames: store.projectNames,
            today: clock.today,
            now: .now,
            minutes: TaskTree.effectiveMinutesMap(store.tasks)
        )
    }

    /// Готовые данные карточек: скор и подписи категорий.
    func cards(for tasks: [TaskItem], hideProject: Bool = false, showScore: Bool = true) -> [TaskCardModel] {
        let context = sortContext
        let withScore = showScore && settings.smartSort
        let projects = settings.projectsEnabled && !hideProject
        let locations = settings.locationsEnabled
        let all = store.tasks
        return tasks.map { task in
            // У подзадачи проект — родителя, поэтому строку проекта заменяет «↳ Родитель · Проект».
            let parentLabel = TaskTree.parentLabel(for: task, in: all) { id in
                projects ? store.categoryName(.project, id: id) : nil
            }
            return TaskCardModel(
                task: task,
                score: withScore ? context.score(task) : nil,
                timeLabel: Self.timeLabel(TaskTree.timeMode(task, in: all)),
                locationName: locations ? store.categoryName(.location, id: task.locationId) : nil,
                projectName: projects && parentLabel == nil ? store.categoryName(.project, id: task.projectId) : nil,
                parentLabel: parentLabel,
                needsCompletionChoice: TaskTree.needsCompletionChoice(task, in: all)
            )
        }
    }

    /// Подпись чипа времени: «45 мин», «Σ 165 мин», «время в родителе» или ничего.
    static func timeLabel(_ mode: TimeMode) -> String? {
        switch mode {
        case .single(let m), .bigTask(let m): RuFormat.minutes(m)
        case .block(let m): "Σ \(RuFormat.minutes(m))"
        case .subtask(let own?, _): RuFormat.minutes(own)
        case .subtask(nil, true): "время в родителе"
        case .subtask(nil, false): nil
        }
    }

    /// Данные карточек доски: подзадачи, скор и подписи времени считаются один раз на экран.
    func boardCards(_ tasks: [TaskItem], context: SortContext) -> [BoardCardModel] {
        let all = store.tasks
        let withScore = settings.smartSort
        let deadlineRequired = settings.formConfig.isRequired(.deadline)
        return tasks.map { task in
            let children = TaskTree.children(of: task.id, in: all)
            return BoardCardModel(
                task: task,
                children: children,
                score: withScore ? context.score(task) : nil,
                timeLabel: Self.timeLabel(TaskTree.timeMode(task, in: all)),
                childTimeLabels: Dictionary(children.map { ($0.id, Self.timeLabel(TaskTree.timeMode($0, in: all))) },
                                            uniquingKeysWith: { a, _ in a }),
                missingDeadline: deadlineRequired && task.deadline == nil
            )
        }
    }

    // MARK: - Действия

    /// Создание строкой на доске. Возвращает false, если название пустое.
    @discardableResult
    func quickAdd(_ title: String, into container: TaskContainer) -> Bool {
        var created: TaskItem?
        withAnimation(Motion.standard) { created = store.quickAdd(title: title, into: container) }
        guard created != nil else { return false }
        rescheduleNotifications()
        return true
    }

    /// Бросок карточки на доске или в листе проекта.
    func drop(taskId: String, on target: DropTarget) {
        switch target {
        case .insert(let container, let position):
            withAnimation(Motion.standard) { _ = store.place(taskId, into: container, at: position) }
        case .nest(let parentId):
            var placed = false
            withAnimation(Motion.standard) {
                placed = store.place(taskId, into: .parent(parentId), at: nil)
                if placed { expandedParents.insert(parentId) }
            }
            if placed, let parent = store.task(id: parentId) {
                showToast("Стала подзадачей «\(parent.title)»", symbol: "text.badge.plus", tint: Palette.accent)
            }
        }
        rescheduleNotifications()
    }

    /// Бросок карточки на пункт сайдбара «Сегодня».
    func dropOnToday(taskId: String) {
        guard let task = store.task(id: taskId), task.status != .today else { return }
        perform(.toToday, on: task)
    }

    /// Бросок карточки на проект в сайдбаре.
    func dropOnProject(taskId: String, projectId: String) {
        moveToProject(taskId: taskId, projectId: projectId)
    }

    /// Перенос в конец колонки проекта (`nil` — «Без проекта»): бросок на сайдбар или пункт меню.
    func moveToProject(taskId: String, projectId: String?) {
        let scope: ProjectScope = projectId.map { .project($0) } ?? .none
        var placed = false
        withAnimation(Motion.standard) { placed = store.place(taskId, into: .column(scope), at: nil) }
        guard placed else { return }
        let name = projectId.flatMap { store.category(.project, id: $0)?.name } ?? "Без проекта"
        showToast("Перенесено в «\(name)»", symbol: "folder.fill", tint: Palette.accent)
    }

    func makeStandalone(_ task: TaskItem) {
        withAnimation(Motion.standard) { store.makeStandalone(task.id) }
        showToast("Подзадача стала отдельной задачей", symbol: "arrow.up.right.square", tint: Palette.accent)
    }

    func reopen(_ task: TaskItem) {
        withAnimation(Motion.standard) { store.reopen(task.id) }
        rescheduleNotifications()
    }

    func presentNewTask(prefill kind: CategoryKind? = nil, categoryId: String? = nil) {
        formRequest = TaskFormRequest(mode: .create(prefill: kind, categoryId: categoryId))
    }

    func presentEdit(_ task: TaskItem) {
        formRequest = TaskFormRequest(mode: .edit(taskId: task.id))
    }

    func perform(_ action: TaskAction, on task: TaskItem) {
        switch action {
        case .edit:
            presentEdit(task)
        case .delete:
            taskPendingDeletion = task
        case .complete:
            // Подзадачи не остаются привязанными к выполненному родителю — сначала спросим, что с ними делать.
            guard !TaskTree.needsCompletionChoice(task, in: store.tasks) else {
                parentPendingCompletion = task
                return
            }
            withAnimation(Motion.standard) { store.complete(id: task.id) }
            showToast("Задача выполнена", symbol: "checkmark.circle.fill", tint: Palette.success)
        case .toToday:
            withAnimation(Motion.standard) { store.moveToToday(id: task.id) }
            showToast("Перемещено в «Сегодня»", symbol: "sun.max.fill", tint: Palette.accent)
        case .toStack:
            withAnimation(Motion.standard) { store.moveToStack(id: task.id) }
            showToast("Перемещено в стек", symbol: "square.stack.3d.up.fill", tint: Palette.accent)
        case .deferTo(let day):
            withAnimation(Motion.standard) { store.deferTask(id: task.id, to: day) }
            showToast("Отложено до \(RuFormat.dayMonth(day))", symbol: "clock.fill", tint: Palette.deferPurple)
        case .undefer:
            withAnimation(Motion.standard) { store.undefer(id: task.id) }
            showToast("Отложенность снята", symbol: "clock.badge.xmark", tint: Palette.deferPurple)
        }
        rescheduleNotifications()
    }

    /// Ответ диалога выполнения родителя: закрыть подзадачи вместе с ним или сделать их отдельными задачами.
    func completeParent(_ task: TaskItem, closingSubtasks: Bool) {
        withAnimation(Motion.standard) { store.completeParent(task.id, closingSubtasks: closingSubtasks) }
        parentPendingCompletion = nil
        showToast(closingSubtasks ? "Выполнено вместе с подзадачами" : "Выполнено, подзадачи стали отдельными",
                  symbol: "checkmark.circle.fill", tint: Palette.success)
        rescheduleNotifications()
    }

    func confirmDeletion(of task: TaskItem) {
        withAnimation(Motion.standard) { store.delete(id: task.id) }
        taskPendingDeletion = nil
        showToast("Задача удалена", symbol: "trash.fill", tint: Palette.error)
        rescheduleNotifications()
    }

    func didSaveForm(created: Bool, fromCategory: Bool) {
        if created {
            showToast("Задача добавлена", symbol: "plus.circle.fill", tint: Palette.accent)
            // Как в Android: новая задача из общего «+» показывается в стеке,
            // а созданная внутри папки остаётся в папке.
            if !fromCategory {
                withAnimation(Motion.standard) { selection = .board }
            }
        }
        rescheduleNotifications()
    }

    func deleteCategory(_ kind: CategoryKind, _ category: Category) {
        withAnimation(Motion.standard) { store.deleteCategory(kind, id: category.id) }
        if selection == .category(kind, category.id) {
            selection = .category(kind, nil)
        }
        if selection == .project(category.id) {
            selection = .board
        }
        categoryPendingDeletion = nil
        showToast("Удалено: «\(category.name)»", symbol: "trash.fill", tint: Palette.error)
    }

    func undo() {
        store.undoManager?.undo()
        toast = nil
        rescheduleNotifications()
    }

    func showToast(_ message: String, symbol: String, tint: Color, undoable: Bool = true) {
        withAnimation(Motion.bouncy) {
            toast = Toast(
                message: message, symbol: symbol, tint: tint,
                undoable: undoable && store.undoManager != nil,
                revision: store.revision
            )
        }
        toastDismissal?.cancel()
        toastDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.standard) { self?.toast = nil }
        }
    }

    func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    static let donateURL = "https://pay.cloudtips.ru/p/e0ddf2ed"
    static let supportEmail = "supportkotatask@gmail.com"
    static let telegramURL = "https://t.me/+j6uyk2SS80liNDNi"
    static let suggestURL = "https://t.me/+dbGPeyjrZsk1Yjgy"
}
