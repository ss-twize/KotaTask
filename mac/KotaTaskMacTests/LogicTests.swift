import Foundation
import Testing
@testable import KotaTask

private let today = Day(year: 2026, month: 10, day: 22)
private let noon = Calendar.kota.date(bySettingHour: 12, minute: 0, second: 0, of: today.date())!

private func task(
    _ title: String,
    deadline: Day? = nil,
    start: Day? = nil,
    importance: Importance = .medium,
    duration: Int = 30,
    status: TaskStatus = .stack,
    daysOld: Double = 0,
    project: String? = nil,
    location: String? = nil,
    type: String? = nil,
    deferred: Day? = nil,
    purpose: String = ""
) -> TaskItem {
    TaskItem(
        title: title, deadline: deadline, deadlineStart: start, purpose: purpose, duration: duration,
        importance: importance, status: status, created: noon.addingTimeInterval(-daysOld * 86_400),
        projectId: project, locationId: location, taskTypeId: type, deferredDate: deferred
    )
}

// MARK: - Алгоритм приоритета

@Suite("Алгоритм приоритета")
struct PriorityCalculatorTests {

    @Test("Пять зон дедлайна и пустой дедлайн", arguments: [
        (nil as Int?, 0.3), (-1, 1.0), (0, 0.9), (1, 0.7), (3, 0.7), (4, 0.5), (7, 0.5), (8, 0.2), (30, 0.2),
    ])
    func deadlineZones(offset: Int?, expected: Double) {
        let deadline = offset.map { today.adding(days: $0) }
        #expect(PriorityCalculator.deadlineScore(deadline, today: today) == expected)
    }

    @Test func importance() {
        #expect(PriorityCalculator.importanceScore(.high) == 1.0)
        #expect(PriorityCalculator.importanceScore(.medium) == 0.6)
        #expect(PriorityCalculator.importanceScore(.low) == 0.2)
    }

    @Test("База длительности", arguments: [(5, 1.0), (15, 1.0), (16, 0.8), (30, 0.8), (60, 0.6), (120, 0.4), (121, 0.2)])
    func durationBase(minutes: Int, expected: Double) {
        #expect(PriorityCalculator.durationScore(minutes: minutes, dayLoad: 0, overloadLimit: 180, boost: 0.2) == expected)
    }

    @Test("Бонус включается строго выше половины порога и не превышает 1")
    func durationBoost() {
        #expect(PriorityCalculator.durationScore(minutes: 60, dayLoad: 90, overloadLimit: 180, boost: 0.2) == 0.6)
        #expect(abs(PriorityCalculator.durationScore(minutes: 60, dayLoad: 91, overloadLimit: 180, boost: 0.2) - 0.8) < 1e-9)
        #expect(PriorityCalculator.durationScore(minutes: 10, dayLoad: 500, overloadLimit: 180, boost: 0.2) == 1.0)
    }

    @Test func ageGrowsLinearlyForFiveDays() {
        #expect(PriorityCalculator.ageScore(created: noon, now: noon) == 0)
        #expect(PriorityCalculator.ageScore(created: noon.addingTimeInterval(-2.5 * 86_400), now: noon) == 0.4)
        #expect(PriorityCalculator.ageScore(created: noon.addingTimeInterval(-5 * 86_400), now: noon) == 1.0)
        #expect(PriorityCalculator.ageScore(created: noon.addingTimeInterval(86_400), now: noon) == 0)
    }

    @Test("Итоговый скор с дефолтными весами")
    func fullScore() {
        let t = task("Отчёт", deadline: today, importance: .high, duration: 30, daysOld: 2)
        let load = LoadContext(dayLoadMinutes: 0, overloadLimitMinutes: 180, loadDurationBoost: 0.2)
        let score = PriorityCalculator.score(t, minutes: 30, coefficients: .defaults, load: load, today: today, now: noon)
        #expect(abs(score - 0.875) < 1e-9)
    }

    @Test("Выключенный контроль перегрузки убирает бонус")
    func disabledLoad() {
        let t = task("Мелочь", duration: 60)
        let on = PriorityCalculator.score(t, minutes: 60, coefficients: .defaults,
                                          load: LoadContext(dayLoadMinutes: 1000, overloadLimitMinutes: 180, loadDurationBoost: 0.2),
                                          today: today, now: noon)
        let off = PriorityCalculator.score(t, minutes: 60, coefficients: .defaults, load: .disabled(dayLoadMinutes: 1000), today: today, now: noon)
        #expect(on > off)
    }
}

// MARK: - Выборки и сортировки

@Suite("Выборки и сортировки")
struct TaskQueriesTests {
    let context = SortContext(
        coefficients: .defaults,
        load: LoadContext(dayLoadMinutes: 0, overloadLimitMinutes: 180, loadDurationBoost: 0.2),
        projectNames: ["p1": "Альфа", "p2": "Бета"],
        today: today, now: noon
    )

    @Test func priorityPutsUrgentFirst() {
        let far = task("Далёкая", deadline: today.adding(days: 30), importance: .low)
        let urgent = task("Горящая", deadline: today.adding(days: -1), importance: .high)
        let sorted = TaskQueries.sort([far, urgent], by: .priority, context: context)
        #expect(sorted.map(\.title) == ["Горящая", "Далёкая"])
    }

    @Test func deadlineSortSendsEmptyToTheEnd() {
        let none = task("Без срока")
        let later = task("Позже", deadline: today.adding(days: 5))
        let sooner = task("Раньше", deadline: today.adding(days: 1))
        #expect(TaskQueries.sort([none, later, sooner], by: .deadline, context: context).map(\.title) == ["Раньше", "Позже", "Без срока"])
    }

    @Test func byProjectGroupsByNameAndNilLast() {
        let a = task("Задача Б", project: "p2")
        let b = task("Задача без проекта")
        let c = task("Задача А", project: "p1")
        #expect(TaskQueries.sort([a, b, c], by: .byProject, context: context).map(\.title)
                == ["Задача А", "Задача Б", "Задача без проекта"])
    }

    @Test func importanceThenTitle() {
        let list = [task("б", importance: .low), task("в", importance: .high), task("а", importance: .high)]
        #expect(TaskQueries.sort(list, by: .importance, context: context).map(\.title) == ["а", "в", "б"])
    }

    @Test("Равные элементы сохраняют порядок «новые сверху»")
    func stableBaseOrder() {
        let old = task("Старая", duration: 30, daysOld: 3)
        let new = task("Новая", duration: 30, daysOld: 1)
        #expect(TaskQueries.sort([old, new], by: .duration, context: context).map(\.title) == ["Новая", "Старая"])
    }

    @Test func categoryFilters() {
        let list = [task("1", location: "l1"), task("2", location: nil), task("3", location: "l2", type: "t1")]
        #expect(TaskQueries.filter(list, location: .any).count == 3)
        #expect(TaskQueries.filter(list, location: .none).map(\.title) == ["2"])
        #expect(TaskQueries.filter(list, location: .only("l2"), taskType: .only("t1")).map(\.title) == ["3"])
    }

    @Test func searchIsCaseInsensitiveOverTitleAndPurpose() {
        let list = [task("Купить МОЛОКО"), task("Звонок", purpose: "обсудить молоко"), task("Другое")]
        #expect(TaskQueries.search(list, query: "молоко").count == 2)
        #expect(TaskQueries.search(list, query: "  ").count == 3)
    }

    @Test("Календарь: диапазон, точка и отложенные")
    func calendarDays() {
        let ranged = task("Диапазон", deadline: today.adding(days: 3), start: today.adding(days: 1))
        let fromCreation = task("От создания", deadline: today.adding(days: 2), daysOld: 1)
        let deferred = task("Отложена", deferred: today.adding(days: 5))
        let archived = task("Архив", deadline: today.adding(days: 2), status: .archive)
        let all = [ranged, fromCreation, deferred, archived]

        #expect(TaskQueries.tasks(on: today, in: all, mode: .range).map(\.title) == ["От создания"])
        #expect(TaskQueries.tasks(on: today.adding(days: 2), in: all, mode: .range).map(\.title).sorted() == ["Диапазон", "От создания"])
        #expect(TaskQueries.tasks(on: today.adding(days: 2), in: all, mode: .point).map(\.title) == ["От создания"])
        #expect(TaskQueries.tasks(on: today.adding(days: 5), in: all, mode: .point).map(\.title) == ["Отложена"])
    }

    @Test func archiveSortedByCompletionDesc() {
        var first = task("Первая", status: .archive); first.completed = noon
        var second = task("Вторая", status: .archive); second.completed = noon.addingTimeInterval(60)
        #expect(TaskQueries.archive([first, second, task("Активная")]).map(\.title) == ["Вторая", "Первая"])
    }

    @Test func activeCountIgnoresArchive() {
        let list = [task("1", project: "p1"), task("2", status: .archive, project: "p1"), task("3")]
        #expect(TaskQueries.activeCount(list, kind: .project, id: "p1") == 1)
        #expect(TaskQueries.activeCount(list, kind: .project, id: nil) == 1)
    }
}

// MARK: - Нагрузка дня

@Suite("Нагрузка дня")
struct DayLoadTests {
    @Test("Светофор: половина порога и порог", arguments: [(0, LoadLevel.ok), (89, .ok), (90, .warn), (179, .warn), (180, .over)])
    func levels(minutes: Int, expected: LoadLevel) {
        #expect(DayLoad(minutes: minutes, count: 1, limit: 180, isControlEnabled: true).level == expected)
    }

    @Test func neutralWhenDisabled() {
        #expect(DayLoad(minutes: 999, count: 1, limit: 180, isControlEnabled: false).level == .neutral)
    }
}

// MARK: - Валидация формы

@Suite("Валидация формы")
struct TaskValidatorTests {
    func config(_ level: AssistanceLevel, custom: Set<RequirableField> = [], showDuration: Bool = true) -> FormConfig {
        FormConfig(assistance: level, customRequired: custom, showDuration: showDuration, showPurpose: true,
                   visibleCategories: Set(CategoryKind.allCases))
    }

    func errors(_ draft: TaskDraft, _ config: FormConfig) -> [FormField: String] {
        if case .invalid(let e) = TaskValidator.validate(draft, config: config) { return e }
        return [:]
    }

    @Test func titleAlwaysRequired() {
        #expect(errors(TaskDraft(), config(.minimal))[.title] != nil)
    }

    @Test func levelsTable() {
        var draft = TaskDraft()
        draft.title = "Задача"
        #expect(errors(draft, config(.minimal)).isEmpty)
        #expect(Set(errors(draft, config(.standard)).keys) == [.deadline])
        #expect(Set(errors(draft, config(.advanced)).keys) == [.deadline, .duration, .purpose])
        #expect(Set(errors(draft, config(.custom, custom: [.project, .deadlineStart])).keys) == [.category(.project), .deadlineStart])
    }

    @Test func hiddenFieldIsNeverRequired() {
        var draft = TaskDraft()
        draft.title = "Задача"
        draft.deadline = today
        draft.purpose = "Зачем"
        #expect(errors(draft, config(.advanced, showDuration: false)).isEmpty)
    }

    @Test("Длительность: пусто → 30, вне 1…600 — ошибка", arguments: [("", 30), ("1", 1), ("600", 600)])
    func durationAccepted(text: String, expected: Int) {
        var draft = TaskDraft()
        draft.title = "Задача"
        draft.durationText = text
        guard case .valid(let v) = TaskValidator.validate(draft, config: config(.minimal)) else {
            Issue.record("ожидалась валидная форма"); return
        }
        #expect(v.duration == expected)
    }

    @Test func emptyDurationAllowedForTree() {
        var draft = TaskDraft()
        draft.title = "Задача"
        var tree = config(.minimal)
        tree.allowsEmptyDuration = true
        guard case .valid(let forTree) = TaskValidator.validate(draft, config: tree),
              case .valid(let plain) = TaskValidator.validate(draft, config: config(.minimal)) else {
            Issue.record("ожидалась валидная форма"); return
        }
        #expect(forTree.duration == nil, "родитель и подзадача могут быть без своего времени")
        #expect(plain.duration == 30, "обычная задача — по-прежнему 30 минут")
    }

    @Test func emptyDurationAllowedForTreeEvenWhenRequired() {
        var draft = TaskDraft()
        draft.title = "Задача"
        draft.deadline = today
        draft.purpose = "Зачем"
        var tree = config(.advanced)
        tree.allowsEmptyDuration = true
        #expect(errors(draft, tree)[.duration] == nil, "иначе «Блок задач» недостижим на продвинутом уровне")
        #expect(errors(draft, config(.advanced))[.duration] != nil)
    }

    @Test(arguments: ["0", "601", "abc", "-5"])
    func durationRejected(text: String) {
        var draft = TaskDraft()
        draft.title = "Задача"
        draft.durationText = text
        #expect(errors(draft, config(.minimal))[.duration] == "Введите от 1 до 600 минут")
    }

    @Test func startAfterDeadlineRejected() {
        var draft = TaskDraft()
        draft.title = "Задача"
        draft.deadline = today
        draft.deadlineStart = today.adding(days: 1)
        #expect(errors(draft, config(.minimal))[.deadlineStart] != nil)
    }
}

// MARK: - Форматы

@Suite("Русские форматы")
struct RuFormatTests {
    @Test(arguments: [(1, "задача"), (2, "задачи"), (5, "задач"), (11, "задач"), (12, "задач"),
                      (21, "задача"), (22, "задачи"), (25, "задач"), (111, "задач"), (0, "задач")])
    func plural(n: Int, word: String) {
        #expect(RuFormat.taskWord(n) == word)
    }

    @Test func deadlineChip() {
        #expect(RuFormat.deadlineChip(start: nil, end: today, today: today) == "Сегодня")
        #expect(RuFormat.deadlineChip(start: nil, end: today.adding(days: -1), today: today).hasPrefix("Просрочено · 21"))
        #expect(RuFormat.deadlineChip(start: today, end: today.adding(days: 2), today: today).contains("→"))
        #expect(RuFormat.deadlineChip(start: today, end: today, today: today) == "Сегодня")
    }
}

// MARK: - Календарь

@Suite("Календарная сетка")
struct CalendarMonthTests {
    @Test("Октябрь 2026: с понедельника 28 сентября, 5 полных недель")
    func october2026() {
        let cells = CalendarMonth.cells(for: YearMonth(year: 2026, month: 10))
        #expect(cells.count == 35)
        #expect(cells.first?.day == Day(year: 2026, month: 9, day: 28))
        #expect(cells.first?.isCurrentMonth == false)
        #expect(cells.filter(\.isCurrentMonth).count == 31)
        #expect(cells.allSatisfy { cell in cells.firstIndex(of: cell)! % 7 == cell.day.weekdayIndex })
    }

    @Test("Февраль 2027 начинается в понедельник — ровно 4 недели без добора")
    func february2027() {
        let cells = CalendarMonth.cells(for: YearMonth(year: 2027, month: 2))
        #expect(cells.count == 28)
        #expect(cells.allSatisfy { $0.isCurrentMonth })
    }

    @Test("Ноябрь 2026 начинается в воскресенье — 6 недель")
    func november2026() {
        let cells = CalendarMonth.cells(for: YearMonth(year: 2026, month: 11))
        #expect(cells.count == 42)
        #expect(cells[6].day == Day(year: 2026, month: 11, day: 1))
    }

    @Test func radiusCurve() {
        #expect(CalendarMonth.radiusRatio(durationMinutes: 0) == 0.52)
        #expect(abs(CalendarMonth.radiusRatio(durationMinutes: 60) - 0.8234) < 0.001)
        #expect(CalendarMonth.radiusRatio(durationMinutes: 10_000) <= 1.0)
    }

    @Test func toneRules() {
        let deferredDay = today.adding(days: 3)
        #expect(CalendarMonth.tone(for: task("", deferred: deferredDay), on: deferredDay) == .deferred)
        #expect(CalendarMonth.tone(for: task("", importance: .high, status: .today), on: today) == .today)
        #expect(CalendarMonth.tone(for: task("", importance: .low), on: today) == .low)
    }

    @Test func isoParsing() {
        #expect(Day(iso: "2026-02-31") == nil)
        #expect(Day(iso: "") == nil)
        #expect(Day(iso: "2026-10-22") == today)
        #expect(today.iso == "2026-10-22")
    }
}

// MARK: - Уведомления

@Suite("План уведомлений")
struct NotificationPlannerTests {
    @Test func skipsPastTimeAndIncludesDeferredFromItsDay() {
        let morning = Calendar.kota.date(bySettingHour: 9, minute: 0, second: 0, of: today.date())!
        let tasks = [task("Сегодняшняя", status: .today), task("Отложенная", deferred: today.adding(days: 2)), task("Стек")]
        let plans = NotificationPlanner.plans(tasks: tasks, hour: 8, minute: 0, now: morning, days: 3)
        #expect(plans.map(\.day) == [today.adding(days: 1), today.adding(days: 2)])
        #expect(plans[0].taskCount == 1)
        #expect(plans[1].taskCount == 2)
    }

    @Test func bodyTruncatesAfterFive() {
        let body = NotificationPlanner.body(for: (1...7).map { "Задача \($0)" })
        #expect(body.components(separatedBy: "\n").count == 6)
        #expect(body.hasSuffix("и ещё 2…"))
        #expect(NotificationPlanner.body(for: []) == "Нет задач на сегодня")
    }
}

// MARK: - Совместимость формата

@Suite("Формат JSON")
struct CodingTests {
    @Test("Задача из Android-бэкапа v2 читается")
    func decodesAndroidBackupTask() throws {
        let json = """
        {"id":"abc","title":"Позвонить","deadline":"2026-10-25","deadlineStart":"","parent":"","purpose":"",
         "duration":15,"importance":"Высокая","status":"Сегодня","assignee":"","created":1792000000000,
         "completed":0,"projectId":"","locationId":"l1","taskTypeId":"","deferredDate":""}
        """
        let t = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        #expect(t.deadline == Day(year: 2026, month: 10, day: 25))
        #expect(t.deadlineStart == nil)
        #expect(t.status == .today)
        #expect(t.importance == .high)
        #expect(t.projectId == nil)
        #expect(t.locationId == "l1")
        #expect(t.completed == nil)
    }

    @Test func roundTrip() throws {
        var original = task("Туда-обратно", deadline: today, start: today.adding(days: -1), importance: .low,
                            duration: 45, status: .archive, project: "p", deferred: today)
        original.completed = noon
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
        #expect(decoded == original)
    }
}
