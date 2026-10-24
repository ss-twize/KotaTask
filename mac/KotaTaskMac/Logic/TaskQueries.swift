import Foundation

/// Всё, что нужно сортировке «По приоритету» и «По проектам».
struct SortContext: Sendable {
    var coefficients: Coefficients
    var load: LoadContext
    var projectNames: [String: String]
    var today: Day
    var now: Date
    /// Итоговое время задач по id (`TaskTree.effectiveMinutesMap`).
    var minutes: [String: Int]

    init(coefficients: Coefficients, load: LoadContext, projectNames: [String: String],
         today: Day, now: Date, minutes: [String: Int] = [:]) {
        self.coefficients = coefficients
        self.load = load
        self.projectNames = projectNames
        self.today = today
        self.now = now
        self.minutes = minutes
    }

    /// Время задачи для алгоритма; задача вне карты считается одиночной.
    func minutes(for task: TaskItem) -> Int {
        minutes[task.id] ?? task.duration ?? TaskItem.defaultDuration
    }

    func score(_ task: TaskItem) -> Double {
        PriorityCalculator.score(task, minutes: minutes(for: task), coefficients: coefficients,
                                 load: load, today: today, now: now)
    }
}

/// Выборки и сортировки списков. Порт `TaskViewModel.applySortMode / applyCategoryFilters`
/// и группировки календаря. Всё — чистые функции над массивом задач.
enum TaskQueries {

    /// Порядок, в котором Room отдаёт задачи (`ORDER BY created DESC`). От него зависят
    /// равные элементы во всех стабильных сортировках ниже.
    static func baseOrder(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.stableSorted { $0.created > $1.created }
    }

    static func sort(_ tasks: [TaskItem], by mode: SortMode, context: SortContext) -> [TaskItem] {
        let base = baseOrder(tasks)
        switch mode {
        case .priority:
            let scores = Dictionary(base.map { ($0.id, context.score($0)) }, uniquingKeysWith: { a, _ in a })
            return base.stableSorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
        case .importance:
            return base.stableSorted {
                if $0.importance.rank != $1.importance.rank { return $0.importance.rank < $1.importance.rank }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .deadline:
            // Задачи без дедлайна уходят в конец.
            return base.stableSorted {
                switch ($0.deadline, $1.deadline) {
                case let (a?, b?): a < b
                case (_?, nil): true
                default: false
                }
            }
        case .age:
            return base.stableSorted { $0.created < $1.created }
        case .alphabetical:
            return base.stableSorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .byProject:
            // Группируем по имени проекта; задачи без проекта — в конце.
            func name(_ t: TaskItem) -> String? { t.projectId.flatMap { context.projectNames[$0] } }
            return base.stableSorted { a, b in
                switch (name(a), name(b)) {
                case let (x?, y?) where x != y:
                    return x.localizedStandardCompare(y) == .orderedAscending
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    if a.importance.rank != b.importance.rank { return a.importance.rank < b.importance.rank }
                    return a.title.localizedStandardCompare(b.title) == .orderedAscending
                }
            }
        case .duration:
            return base.stableSorted { context.minutes(for: $0) < context.minutes(for: $1) }
        }
    }

    /// Фильтры по трём осям, применяются конъюнктивно.
    static func filter(
        _ tasks: [TaskItem],
        project: CategoryFilter = .any,
        location: CategoryFilter = .any,
        taskType: CategoryFilter = .any
    ) -> [TaskItem] {
        tasks.filter {
            project.matches($0.projectId) && location.matches($0.locationId) && taskType.matches($0.taskTypeId)
        }
    }

    /// Поиск без учёта регистра по названию и цели.
    static func search(_ tasks: [TaskItem], query: String) -> [TaskItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.purpose.localizedCaseInsensitiveContains(q)
        }
    }

    static func tasks(_ all: [TaskItem], status: TaskStatus) -> [TaskItem] {
        all.filter { $0.status == status }
    }

    static func active(_ all: [TaskItem]) -> [TaskItem] {
        all.filter(\.isActive)
    }

    /// Суммарная длительность задач «Сегодня» без двойного счёта подзадач.
    static func todayLoadMinutes(_ all: [TaskItem]) -> Int {
        TaskTree.todayLoadMinutes(all)
    }

    /// Архив: по убыванию времени выполнения.
    static func archive(_ all: [TaskItem]) -> [TaskItem] {
        all.filter { $0.status == .archive }
            .stableSorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
    }

    /// Активные задачи, относящиеся к дню календаря.
    ///
    /// Диапазон — день попадает в `[начало, дедлайн]`, где начало по умолчанию — дата создания.
    /// Точка — только день дедлайна. Отложенная задача видна и в день откладывания:
    /// в Android сетка её показывала, а список под сеткой — нет; здесь они совпадают.
    static func tasks(on day: Day, in all: [TaskItem], mode: CalendarMode) -> [TaskItem] {
        all.filter { task in
            guard task.isActive else { return false }
            if task.status == .stack, task.deferredDate == day { return true }
            guard let deadline = task.deadline else { return false }
            switch mode {
            case .point:
                return deadline == day
            case .range:
                guard let start = task.effectiveRangeStart else { return false }
                return start <= day && day <= deadline
            }
        }
    }

    /// Порядок секторов ячейки: «Сегодня» → высокая → средняя → низкая → по созданию.
    static func cellOrder(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.stableSorted { a, b in
            let ta = a.status == .today ? 0 : 1, tb = b.status == .today ? 0 : 1
            if ta != tb { return ta < tb }
            if a.importance.rank != b.importance.rank { return a.importance.rank < b.importance.rank }
            return a.created < b.created
        }
    }

    /// Порядок списка дня: сначала «Сегодня», затем по названию.
    static func dayListOrder(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.stableSorted { a, b in
            let ta = a.status == .today ? 0 : 1, tb = b.status == .today ? 0 : 1
            if ta != tb { return ta < tb }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Счётчик активных задач в папке (`id == nil` — системная папка «Без …»).
    static func activeCount(_ all: [TaskItem], kind: CategoryKind, id: String?) -> Int {
        all.lazy.filter { $0.isActive && $0.categoryId(for: kind) == id }.count
    }
}

extension Array {
    /// Стабильная сортировка: равные элементы сохраняют исходный порядок,
    /// как `sortedBy` / `sortedWith` в Kotlin.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
