import Foundation
import Testing
@testable import KotaTask

private let boardToday = Day(year: 2026, month: 10, day: 24)
private let boardNoon = Calendar.kota.date(bySettingHour: 12, minute: 0, second: 0, of: boardToday.date())!

private func item(
    _ id: String,
    duration: Int? = 30,
    status: TaskStatus = .stack,
    parent: String? = nil,
    project: String? = nil,
    sortIndex: Double = 0,
    importance: Importance = .medium,
    deadline: Day? = nil,
    daysOld: Double = 0
) -> TaskItem {
    TaskItem(
        id: id, title: id, deadline: deadline, duration: duration, importance: importance, status: status,
        created: boardNoon.addingTimeInterval(-daysOld * 86_400), projectId: project,
        parentId: parent, sortIndex: sortIndex
    )
}

// MARK: - Task 1: время родителя и подзадач

@Suite("Время родителя и подзадач")
struct TaskTreeTests {

    @Test func hiddenColumnFlagRoundTrips() throws {
        var project = KotaTask.Category(id: "p", name: "P")
        project.hiddenOnBoard = true
        let back = try JSONDecoder().decode(KotaTask.Category.self, from: JSONEncoder().encode(project))
        #expect(back.hiddenOnBoard)
        let legacy = try JSONDecoder().decode(KotaTask.Category.self, from: Data(#"{"id":"x","name":"X"}"#.utf8))
        #expect(!legacy.hiddenOnBoard, "старые файлы — все колонки видны")
    }

    @Test func legacyJSONDecodes() throws {
        let withDuration = #"{"id":"a","title":"A","duration":45,"status":"Стек","created":1792000000000}"#
        let old = try JSONDecoder().decode(TaskItem.self, from: Data(withDuration.utf8))
        #expect(old.parentId == nil)
        #expect(old.sortIndex == 0)
        #expect(old.duration == 45)

        let withoutDuration = #"{"id":"b","title":"B","status":"Стек","created":1792000000000}"#
        let noTime = try JSONDecoder().decode(TaskItem.self, from: Data(withoutDuration.utf8))
        #expect(noTime.duration == nil)
    }

    @Test func roundTripKeepsNewFields() throws {
        let original = item("x", duration: nil, parent: "p", sortIndex: 2.5)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.parentId == "p")
        #expect(decoded.sortIndex == 2.5)
        #expect(decoded.duration == nil)
    }

    @Test func singleTaskDefaultsTo30() {
        let solo = item("solo", duration: nil)
        #expect(TaskTree.timeMode(solo, in: [solo]) == .single(30))
        #expect(TaskTree.effectiveMinutes(solo, in: [solo]) == 30)
    }

    @Test func bigTaskWinsOverSubtasks() {
        let parent = item("p", duration: 120)
        let all = [parent, item("c1", duration: 30, parent: "p"), item("c2", duration: 45, parent: "p")]
        #expect(TaskTree.timeMode(parent, in: all) == .bigTask(120))
        #expect(TaskTree.effectiveMinutes(parent, in: all) == 120)
    }

    @Test func blockSumsOpenChildren() {
        let parent = item("p", duration: nil)
        let all = [
            parent,
            item("c1", duration: 30, parent: "p"),
            item("c2", duration: 45, parent: "p"),
            item("c3", duration: 90, status: .archive, parent: "p"),
        ]
        #expect(TaskTree.timeMode(parent, in: all) == .block(75))
        #expect(TaskTree.effectiveMinutes(parent, in: all) == 75)
    }

    @Test func subtaskWithoutTimeInBigTask() {
        let parent = item("p", duration: 120)
        let child = item("c", duration: nil, parent: "p")
        let all = [parent, child]
        #expect(TaskTree.timeMode(child, in: all) == .subtask(own: nil, parentHasOwn: true))
        #expect(TaskTree.effectiveMinutes(child, in: all) == 0)
    }

    @Test func todayLoadNoDoubleCount() {
        let parent = item("p", duration: nil, status: .today)
        let inToday = item("c1", duration: 30, status: .today, parent: "p")
        let inStack = item("c2", duration: 45, parent: "p")
        #expect(TaskTree.todayLoadMinutes([parent, inToday, inStack]) == 75)

        let parentInStack = item("p", duration: nil)
        #expect(TaskTree.todayLoadMinutes([parentInStack, inToday, inStack]) == 30)
    }

    @Test func priorityUsesEffectiveMinutes() {
        let parent = item("p", duration: nil)
        let tree = [parent, item("c", duration: 10, parent: "p")]
        let solo = item("solo", duration: 10)
        let load = LoadContext(dayLoadMinutes: 0, overloadLimitMinutes: 180, loadDurationBoost: 0.2)
        let parentScore = PriorityCalculator.score(parent, minutes: TaskTree.effectiveMinutes(parent, in: tree),
                                                   coefficients: .defaults, load: load, today: boardToday, now: boardNoon)
        let soloScore = PriorityCalculator.score(solo, minutes: TaskTree.effectiveMinutes(solo, in: [solo]),
                                                 coefficients: .defaults, load: load, today: boardToday, now: boardNoon)
        #expect(abs(parentScore - soloScore) < 1e-9)
    }

    // MARK: Task 6: подзадачи в остальных экранах и форма

    @Test func parentLabelNamesParentAndProject() {
        let tree = [item("Запуск", project: "site"), item("Макет", parent: "Запуск", project: "site"), item("Solo")]
        let names = ["site": "Сайт"]
        let child = tree[1]
        #expect(TaskTree.parentLabel(for: child, in: tree, projectName: { names[$0 ?? ""] }) == "↳ Запуск · Сайт")
        #expect(TaskTree.parentLabel(for: child, in: tree, projectName: { _ in nil }) == "↳ Запуск",
                "без проекта или с выключенными проектами — только родитель")
        #expect(TaskTree.parentLabel(for: tree[0], in: tree, projectName: { names[$0 ?? ""] }) == nil)
        #expect(TaskTree.parentLabel(for: item("x", parent: "нет"), in: tree, projectName: { _ in nil }) == nil,
                "родителя нет — подписи нет")
    }

    @Test func completionChoiceOnlyForParentWithOpenSubtasks() {
        let tree = [item("p"), item("c", parent: "p"), item("q"), item("d", status: .archive, parent: "q")]
        #expect(TaskTree.needsCompletionChoice(tree[0], in: tree))
        #expect(!TaskTree.needsCompletionChoice(tree[2], in: tree), "все подзадачи закрыты — спрашивать нечего")
        #expect(!TaskTree.needsCompletionChoice(tree[1], in: tree))
    }

    @Test func emptyDurationAllowedOnlyInTree() {
        let tree = [item("p"), item("c", parent: "p"), item("solo")]
        #expect(TaskTree.allowsEmptyDuration(tree[0], in: tree))
        #expect(TaskTree.allowsEmptyDuration(tree[1], in: tree))
        #expect(!TaskTree.allowsEmptyDuration(tree[2], in: tree))
    }

    @Test func durationHintForTree() {
        let parent = item("p", duration: 60)
        let tree = [parent, item("c1", duration: 30, parent: "p"), item("c2", duration: 45, parent: "p"),
                    item("done", duration: 20, status: .archive, parent: "p")]
        #expect(TaskTree.durationHint(for: parent, durationText: "60", in: tree) == "У подзадач в сумме 75 мин",
                "сумма — по открытым подзадачам")
        #expect(TaskTree.durationHint(for: parent, durationText: "", in: tree) == "Пусто — время считается из подзадач")

        let bigTask = [parent, item("c", duration: nil, parent: "p")]
        #expect(TaskTree.durationHint(for: parent, durationText: "60", in: bigTask) == "Пусто — время считается из подзадач")
        #expect(TaskTree.durationHint(for: bigTask[1], durationText: "", in: bigTask) == "Пусто — время входит в родителя")
        #expect(TaskTree.durationHint(for: item("solo"), durationText: "", in: [item("solo")]) == nil)
    }
}

// MARK: - Task 2: ручной порядок и колонки

@Suite("Ручной порядок и колонки")
struct ManualOrderTests {
    @Test func hiddenProjectsLeaveTheBoard() {
        var hidden = KotaTask.Category(id: "B", name: "B", sortIndex: 1)
        hidden.hiddenOnBoard = true
        let projects = [KotaTask.Category(id: "A", name: "A", sortIndex: 0), hidden]
        let columns = BoardQueries.columns(all: [item("a", project: "A"), item("b", project: "B")], projects: projects)
        #expect(columns.map(\.title) == [BoardQueries.noProjectTitle, "A"], "«Без проекта» остаётся всегда")
    }

    let context = SortContext(
        coefficients: .defaults,
        load: LoadContext(dayLoadMinutes: 0, overloadLimitMinutes: 180, loadDurationBoost: 0.2),
        projectNames: [:], today: boardToday, now: boardNoon
    )

    @Test func insertBetweenNeighbours() {
        let siblings = [item("a", sortIndex: 1), item("b", sortIndex: 2)]
        #expect(ManualOrder.index(insertingAt: 1, among: siblings) == 1.5)
        #expect(ManualOrder.index(insertingAt: 0, among: siblings) == 0)
        #expect(ManualOrder.index(insertingAt: 2, among: siblings) == 3)
        #expect(ManualOrder.index(insertingAt: 0, among: []) == 0)
    }

    @Test func repeatedInsertionKeepsStrictOrder() {
        var list = [item("a", sortIndex: 0), item("b", sortIndex: 1)]
        for n in 1...60 {
            let index = ManualOrder.index(insertingAt: 1, among: ManualOrder.sorted(list))
            list.append(item("n\(n)", sortIndex: index))
            if ManualOrder.needsRenumbering(ManualOrder.sorted(list)) {
                let map = ManualOrder.renumbered(ManualOrder.sorted(list))
                list = list.map { var t = $0; t.sortIndex = map[t.id] ?? t.sortIndex; return t }
            }
        }
        let sorted = ManualOrder.sorted(list)
        #expect(sorted.map(\.id) == ["a"] + (1...60).reversed().map { "n\($0)" } + ["b"])
        #expect(zip(sorted, sorted.dropFirst()).allSatisfy { $0.sortIndex < $1.sortIndex })
    }

    @Test func columnsStartWithNoProject() {
        let projects = [KotaTask.Category(id: "B", name: "B", sortIndex: 1), KotaTask.Category(id: "A", name: "A", sortIndex: 0)]
        let all = [
            item("free"),
            item("inA", project: "A"),
            item("todayB", status: .today, project: "B"),
            item("child", parent: "inA", project: "A"),
            item("done", status: .archive, project: "A"),
        ]
        let columns = BoardQueries.columns(all: all, projects: projects)
        #expect(columns.map(\.title) == ["Без проекта", "A", "B"])
        #expect(columns.map(\.scope) == [.none, .project("A"), .project("B")])
        #expect(columns[0].tasks.map(\.id) == ["free"])
        #expect(columns[1].tasks.map(\.id) == ["inA"])
        #expect(columns[2].tasks.map(\.id) == ["todayB"])
    }

    @Test func searchMatchesParentByChild() {
        var child = item("c", parent: "p")
        child.title = "Скрипт звонка"
        let parent = item("p")
        let all = [parent, child]
        #expect(BoardQueries.matches(parent, query: "скрипт", location: .any, taskType: .any, all: all))
        #expect(!BoardQueries.matches(parent, query: "бухгалтер", location: .any, taskType: .any, all: all))
    }

    @Test func initialOrderFollowsPriority() {
        let far = item("far", importance: .low, deadline: boardToday.adding(days: 30))
        let urgent = item("urgent", importance: .high, deadline: boardToday.adding(days: -1))
        let order = BoardQueries.initialOrder(all: [far, urgent], mode: .priority, context: context)
        #expect((order["urgent"] ?? 99) < (order["far"] ?? 0))
    }
}

// MARK: - Task 3: операции хранилища

@MainActor
private func boardStore(_ tasks: [TaskItem], projects: [KotaTask.Category] = []) -> TaskStore {
    let store = TaskStore(persistence: nil)
    store.replaceAll(with: StoreSnapshot(tasks: tasks, projects: projects))
    return store
}

@MainActor
@Suite("Доска: операции")
struct BoardStoreTests {
    let ab = [KotaTask.Category(id: "A", name: "A", sortIndex: 0), KotaTask.Category(id: "B", name: "B", sortIndex: 1)]

    /// Значения формы для задачи с другим проектом.
    func formValues(_ task: TaskItem, project: String?) -> ValidatedTask {
        ValidatedTask(title: task.title, deadlineStart: task.deadlineStart, deadline: task.deadline,
                      importance: task.importance, duration: task.duration, purpose: task.purpose,
                      projectId: project, locationId: task.locationId, taskTypeId: task.taskTypeId)
    }

    @Test func editingParentProjectMovesSubtasks() {
        let store = boardStore([item("p", project: "A"), item("c", parent: "p", project: "A")], projects: ab)
        store.updateTask(id: "p", with: formValues(store.task(id: "p")!, project: "B"))
        #expect(store.task(id: "p")?.projectId == "B")
        #expect(store.task(id: "c")?.projectId == "B", "подзадачи всегда в проекте родителя")
    }

    @Test func editingSubtaskKeepsParentProject() {
        let store = boardStore([item("p", project: "A"), item("c", parent: "p", project: "A")], projects: ab)
        store.updateTask(id: "c", with: formValues(store.task(id: "c")!, project: "B"))
        #expect(store.task(id: "c")?.projectId == "A")
        #expect(store.task(id: "c")?.parentId == "p")
    }

    // MARK: Финальное ревью

    @Test func hidingProjectColumnIsUndoable() {
        let store = boardStore([item("a", project: "A")], projects: ab)
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        undo.beginUndoGrouping()
        store.setProjectHidden("A", true)
        undo.endUndoGrouping()
        #expect(store.category(.project, id: "A")?.hiddenOnBoard == true)
        #expect(store.task(id: "a")?.projectId == "A", "задачи остаются в проекте")
        #expect(undo.undoActionName == "Скрытие колонки")
        undo.undo()
        #expect(store.category(.project, id: "A")?.hiddenOnBoard == false)
    }

    @Test func formTaskGoesToEndOfColumn() {
        let store = boardStore([item("a", project: "A", sortIndex: -2), item("b", project: "A", sortIndex: -1),
                                item("c", project: "A", sortIndex: 0)], projects: ab)
        let created = store.addTask(formValues(item("new"), project: "A"))
        #expect(BoardQueries.topLevel(in: .project("A"), all: store.tasks).last?.id == created.id,
                "новая задача — в конец колонки, как строкой")
    }

    @Test func changingProjectInFormMovesToEndOfNewColumn() {
        let store = boardStore([item("x", project: "A", sortIndex: -5), item("b1", project: "B", sortIndex: 0),
                                item("b2", project: "B", sortIndex: 1)], projects: ab)
        store.updateTask(id: "x", with: formValues(store.task(id: "x")!, project: "B"))
        #expect(BoardQueries.topLevel(in: .project("B"), all: store.tasks).map(\.id) == ["b1", "b2", "x"])

        var renamed = formValues(store.task(id: "b1")!, project: "B")
        renamed.title = "Новое имя"
        store.updateTask(id: "b1", with: renamed)
        #expect(BoardQueries.topLevel(in: .project("B"), all: store.tasks).map(\.id) == ["b1", "b2", "x"],
                "без смены проекта место не меняется")
    }

    @Test func columnDropOntoHeaderGoesToItsSide() {
        let store = boardStore([], projects: ab + [KotaTask.Category(id: "C", name: "C", sortIndex: 2)])
        store.moveProjectColumn("A", onto: "C")
        #expect(store.categories(.project).map(\.id) == ["B", "C", "A"], "вправо — после цели: колонку можно сделать последней")
        store.moveProjectColumn("A", onto: "B")
        #expect(store.categories(.project).map(\.id) == ["A", "B", "C"], "влево — перед целью")
    }

    @Test func nestCandidatesAreValidParentsInSameColumn() {
        let store = boardStore([
            item("t", project: "A"), item("p", project: "A"), item("c", parent: "p", project: "A"),
            item("other", project: "B"), item("done", status: .archive, project: "A"),
        ], projects: ab)
        #expect(store.nestCandidates(for: "t").map(\.id) == ["p"])
        #expect(store.nestCandidates(for: "c").map(\.id) == ["t"], "подзадаче — другие родители колонки, не свой")
        #expect(store.nestCandidates(for: "p").isEmpty, "родителя с подзадачами не вложить")
    }

    @Test func moveBetweenColumnsCarriesSubtasks() {
        let store = boardStore([
            item("p", project: "A"), item("c1", parent: "p", project: "A"), item("c2", parent: "p", project: "A"),
            item("b1", project: "B"),
        ], projects: ab)
        #expect(store.place("p", into: .column(.project("B")), at: 0))
        #expect(["p", "c1", "c2"].allSatisfy { store.task(id: $0)?.projectId == "B" })
        #expect(BoardQueries.topLevel(in: .project("B"), all: store.tasks).map(\.id) == ["p", "b1"])
    }

    @Test func nestAndDetach() {
        let store = boardStore([
            item("P", project: "A", sortIndex: 0), item("X", project: "B", sortIndex: 1), item("Y", project: "A", sortIndex: 2),
        ], projects: ab)
        #expect(store.place("X", into: .parent("P"), at: nil))
        #expect(store.task(id: "X")?.parentId == "P")
        #expect(store.task(id: "X")?.projectId == "A")

        store.makeStandalone("X")
        #expect(store.task(id: "X")?.parentId == nil)
        #expect(BoardQueries.topLevel(in: .project("A"), all: store.tasks).map(\.id) == ["P", "X", "Y"])
    }

    @Test func placeRejectsInvalidNesting() {
        let store = boardStore([item("P"), item("c", parent: "P"), item("Q")])
        let before = store.snapshot
        #expect(!store.place("P", into: .parent("P"), at: nil))
        #expect(!store.place("P", into: .parent("c"), at: nil))
        #expect(!store.place("P", into: .parent("Q"), at: nil))
        #expect(!store.place("Q", into: .parent("c"), at: nil))
        #expect(store.snapshot == before)
    }

    @Test func placeAtEndWhenPositionNil() {
        let store = boardStore([
            item("t", project: "A"), item("b1", project: "B", sortIndex: 0), item("b2", project: "B", sortIndex: 1),
        ], projects: ab)
        #expect(store.place("t", into: .column(.project("B")), at: nil))
        #expect(BoardQueries.topLevel(in: .project("B"), all: store.tasks).map(\.id) == ["b1", "b2", "t"])
    }

    @Test func quickAddDefaults() throws {
        let store = boardStore([item("b1", project: "B", sortIndex: 5)], projects: ab)
        let task = try #require(store.quickAdd(title: "  Позвонить  ", into: .column(.project("B"))))
        #expect(task.title == "Позвонить")
        #expect(task.importance == .medium)
        #expect(task.deadline == nil)
        #expect(task.duration == 30)
        #expect(task.status == .stack)
        #expect(BoardQueries.topLevel(in: .project("B"), all: store.tasks).last?.id == task.id)

        let sub = try #require(store.quickAdd(title: "Шаг", into: .parent("b1")))
        #expect(sub.duration == nil)
        #expect(sub.parentId == "b1")
        #expect(sub.projectId == "B")
        #expect(store.quickAdd(title: "   ", into: .column(.none)) == nil)
    }

    @Test func completeParentDetachesOpenSubtasks() {
        let tasks = [
            item("P", project: "A", sortIndex: 0),
            item("c1", parent: "P", project: "A"),
            item("c2", status: .archive, parent: "P", project: "A"),
            item("N", project: "A", sortIndex: 1),
        ]
        let detach = boardStore(tasks, projects: ab)
        detach.completeParent("P", closingSubtasks: false)
        #expect(detach.task(id: "P")?.status == .archive)
        #expect(detach.task(id: "c1")?.parentId == nil)
        #expect(BoardQueries.topLevel(in: .project("A"), all: detach.tasks).map(\.id) == ["c1", "N"])
        #expect(detach.task(id: "c2")?.parentId == "P")

        let close = boardStore(tasks, projects: ab)
        close.completeParent("P", closingSubtasks: true)
        #expect(close.task(id: "P")?.status == .archive)
        #expect(close.task(id: "c1")?.status == .archive)
        #expect(close.task(id: "c1")?.parentId == "P")
    }

    @Test func reopenSubtask() {
        var done = item("c", status: .archive, parent: "P")
        done.completed = boardNoon
        let store = boardStore([item("P"), done])
        store.reopen("c")
        #expect(store.task(id: "c")?.status == .stack)
        #expect(store.task(id: "c")?.completed == nil)
        #expect(store.task(id: "c")?.parentId == "P")
    }

    @Test func deleteParentDeletesChildren() {
        let store = boardStore([item("P"), item("c1", parent: "P"), item("c2", parent: "P"), item("other")])
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        undo.beginUndoGrouping()
        store.delete(id: "P")
        undo.endUndoGrouping()
        #expect(store.tasks.map(\.id) == ["other"])
        undo.undo()
        #expect(Set(store.tasks.map(\.id)) == ["P", "c1", "c2", "other"])
    }

    @Test func deletingProjectKeepsTreesTogether() {
        let store = boardStore([item("P", project: "A"), item("c", parent: "P", project: "A")], projects: ab)
        store.deleteCategory(.project, id: "A")
        #expect(store.task(id: "P")?.projectId == nil)
        #expect(store.task(id: "c")?.projectId == nil)
        #expect(store.task(id: "c")?.parentId == "P")
    }

    @Test func undoRestoresCrossColumnMove() {
        let store = boardStore([item("p", project: "A", sortIndex: 7), item("c", parent: "p", project: "A")], projects: ab)
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        undo.beginUndoGrouping()
        store.place("p", into: .column(.project("B")), at: 0)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Перемещение задачи")
        undo.undo()
        #expect(store.task(id: "p")?.projectId == "A")
        #expect(store.task(id: "p")?.sortIndex == 7)
        #expect(store.task(id: "c")?.projectId == "A")
    }

    @Test func columnReorder() {
        let store = boardStore([], projects: ab + [KotaTask.Category(id: "C", name: "C", sortIndex: 2)])
        store.moveProjectColumn("C", to: 0)
        #expect(store.categories(.project).map(\.id) == ["C", "A", "B"])
    }

    @Test func seedingRunsOnceForLegacyFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "KotaBoard-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let persistence = Persistence(directory: dir)
        let legacy = """
        {"version":1,"tasks":[
          {"id":"b","title":"Бета","duration":30,"status":"Стек","created":1792000000000},
          {"id":"a","title":"Альфа","duration":30,"status":"Стек","created":1792000001000}
        ]}
        """
        try Data(legacy.utf8).write(to: persistence.fileURL)

        let store = TaskStore(persistence: persistence)
        store.load()
        #expect(store.needsOrderSeeding)
        let context = SortContext(coefficients: .defaults,
                                  load: LoadContext(dayLoadMinutes: 0, overloadLimitMinutes: 180, loadDurationBoost: 0.2),
                                  projectNames: [:], today: boardToday, now: boardNoon)
        store.seedManualOrderIfNeeded(mode: .alphabetical, context: context)
        #expect(BoardQueries.topLevel(in: .none, all: store.tasks).map(\.id) == ["a", "b"])
        store.flush()

        let reloaded = TaskStore(persistence: persistence)
        reloaded.load()
        #expect(!reloaded.needsOrderSeeding)
        #expect(BoardQueries.topLevel(in: .none, all: reloaded.tasks).map(\.id) == ["a", "b"])
    }
}

// MARK: - Task 5: позиция броска

@Suite("Позиция броска")
struct DropGeometryTests {
    /// Три карточки по 60 pt с зазором 8.
    let frames: [(id: String, frame: CGRect)] = [
        ("a", CGRect(x: 0, y: 0, width: 250, height: 60)),
        ("b", CGRect(x: 0, y: 68, width: 250, height: 60)),
        ("c", CGRect(x: 0, y: 136, width: 250, height: 60)),
    ]

    @Test func insertionByMidline() {
        let noNest: (String) -> Bool = { _ in false }
        #expect(DropGeometry.target(at: 10, frames: frames, slotIndex: nil, slotHeight: 60, canNest: noNest).position == 0)
        #expect(DropGeometry.target(at: 50, frames: frames, slotIndex: nil, slotHeight: 60, canNest: noNest).position == 1)
        #expect(DropGeometry.target(at: 300, frames: frames, slotIndex: nil, slotHeight: 60, canNest: noNest).position == 3)
    }

    @Test func middleHalfNestsWhenAllowed() {
        let hit = DropGeometry.target(at: 98, frames: frames, slotIndex: nil, slotHeight: 60, canNest: { $0 == "b" })
        #expect(hit.nestInto == "b")
        let edge = DropGeometry.target(at: 70, frames: frames, slotIndex: nil, slotHeight: 60, canNest: { $0 == "b" })
        #expect(edge.nestInto == nil)
        #expect(edge.position == 1)
    }

    @Test("Открытый слот не сдвигает расчёт — позиция не прыгает")
    func openSlotIsCompensated() {
        // Слот открыт перед «b»: «b» и «c» на экране ниже на 68.
        let shifted: [(id: String, frame: CGRect)] = [
            ("a", CGRect(x: 0, y: 0, width: 250, height: 60)),
            ("b", CGRect(x: 0, y: 136, width: 250, height: 60)),
            ("c", CGRect(x: 0, y: 204, width: 250, height: 60)),
        ]
        let result = DropGeometry.target(at: 60, frames: shifted, slotIndex: 1, slotHeight: 60, canNest: { _ in false })
        #expect(result.position == 1)
    }
}
