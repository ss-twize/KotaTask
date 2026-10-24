import Foundation
import Testing
@testable import KotaTask

private func values(_ title: String, project: String? = nil) -> ValidatedTask {
    ValidatedTask(title: title, deadlineStart: nil, deadline: nil, importance: .medium, duration: 30,
                  purpose: "", projectId: project, locationId: nil, taskTypeId: nil)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "KotaTaskTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

@MainActor
@Suite("Хранилище")
struct StoreTests {

    @Test func lifecycleOfTask() {
        let store = TaskStore(persistence: nil)
        let t = store.addTask(values("Задача"))
        #expect(store.task(id: t.id)?.status == .stack)

        store.deferTask(id: t.id, to: Day.today().adding(days: 2))
        #expect(store.task(id: t.id)?.isDeferred == true)

        store.moveToToday(id: t.id)
        #expect(store.task(id: t.id)?.status == .today)
        #expect(store.task(id: t.id)?.isDeferred == false, "ручной перенос снимает отложенность")

        store.complete(id: t.id)
        #expect(store.task(id: t.id)?.status == .archive)
        #expect(store.task(id: t.id)?.completed != nil)

        store.clearArchive()
        #expect(store.tasks.isEmpty)
    }

    @Test func promotesOnlyDueDeferredStackTasks() {
        let store = TaskStore(persistence: nil)
        let today = Day.today()
        let due = store.addTask(values("Пора"))
        let later = store.addTask(values("Рано"))
        store.deferTask(id: due.id, to: today)
        store.deferTask(id: later.id, to: today.adding(days: 1))

        #expect(store.promoteDueDeferred(today: today) == 1)
        #expect(store.task(id: due.id)?.status == .today)
        #expect(store.task(id: due.id)?.deferredDate == nil)
        #expect(store.task(id: later.id)?.status == .stack)
    }

    @Test func deletingCategoryUnlinksTasks() throws {
        let store = TaskStore(persistence: nil)
        let project = try #require(store.addCategory(.project, name: "  Сайт  "))
        #expect(project.name == "Сайт")
        let t = store.addTask(values("Вёрстка", project: project.id))

        store.deleteCategory(.project, id: project.id)
        #expect(store.projects.isEmpty)
        #expect(store.task(id: t.id) != nil, "задача не удаляется вместе с папкой")
        #expect(store.task(id: t.id)?.projectId == nil)
    }

    @Test func emptyCategoryNameIgnored() {
        let store = TaskStore(persistence: nil)
        #expect(store.addCategory(.location, name: "   ") == nil)
        #expect(store.locations.isEmpty)
    }

    @Test func undoAndRedo() {
        let store = TaskStore(persistence: nil)
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo

        undo.beginUndoGrouping()
        let t = store.addTask(values("Отменяемая"))
        undo.endUndoGrouping()

        undo.beginUndoGrouping()
        store.complete(id: t.id)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Выполнение задачи")

        undo.undo()
        #expect(store.task(id: t.id)?.status == .stack)
        undo.redo()
        #expect(store.task(id: t.id)?.status == .archive)
    }

    @Test func debugBuildNeverUsesRealDataFolder() {
        let support = URL(filePath: "/Users/me/Library/Application Support", directoryHint: .isDirectory)
        let demo = ["KOTATASK_DATA_DIR": "/tmp/demo"]
        #expect(Persistence.dataDirectory(environment: [:], isDebug: false, applicationSupport: support).lastPathComponent == "KotaTask")
        #expect(Persistence.dataDirectory(environment: demo, isDebug: false, applicationSupport: support).lastPathComponent == "KotaTask",
                "в Release переменная не действует")
        #expect(Persistence.dataDirectory(environment: [:], isDebug: true, applicationSupport: support).lastPathComponent == "KotaTask Debug",
                "Debug, запущенная из Finder или Spotlight, не трогает настоящие данные")
        #expect(Persistence.dataDirectory(environment: demo, isDebug: true, applicationSupport: support).path() == "/tmp/demo/")
    }

    @Test func persistsAndReloads() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = Persistence(directory: dir)

        let store = TaskStore(persistence: persistence)
        store.load()
        let project = try #require(store.addCategory(.project, name: "Дом"))
        store.addTask(values("Полить цветы", project: project.id))
        store.flush()

        let reloaded = TaskStore(persistence: persistence)
        reloaded.load()
        #expect(reloaded.tasks.map(\.title) == ["Полить цветы"])
        #expect(reloaded.projects.map(\.name) == ["Дом"])
        #expect(reloaded.tasks.first?.projectId == project.id)
    }

    @Test("Повреждённый файл не перезаписывается, данные поднимаются из копии")
    func recoversFromBackup() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = Persistence(directory: dir)

        let good = StoreSnapshot(tasks: [TaskItem(title: "Спасённая")])
        try persistence.save(good, now: .now.addingTimeInterval(-86_400))
        try persistence.save(good, now: .now) // создаёт копию за сегодня
        #expect(persistence.backupFiles().count == 1)

        try Data("{ не json".utf8).write(to: persistence.fileURL)
        guard case .recovered(let snapshot, _) = persistence.load() else {
            Issue.record("ожидалось восстановление из копии"); return
        }
        #expect(snapshot.tasks.map(\.title) == ["Спасённая"])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        #expect(leftovers.contains { $0.hasPrefix("kotatask.corrupt-") })
    }

    @Test("До чтения файла запись запрещена — пустой снимок не затирает задачи")
    func noWritesBeforeLoad() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = Persistence(directory: dir)
        try persistence.save(StoreSnapshot(tasks: [TaskItem(title: "Важная")]))

        let store = TaskStore(persistence: persistence)
        store.flush() // например, приложение закрыли до появления окна
        guard case .loaded(let snapshot) = persistence.load() else {
            Issue.record("файл должен остаться читаемым"); return
        }
        #expect(snapshot.tasks.map(\.title) == ["Важная"])
    }

    @Test("Сбой ежедневной копии не блокирует основную запись")
    func backupFailureDoesNotBlockSave() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = Persistence(directory: dir)
        try persistence.save(StoreSnapshot(tasks: [TaskItem(title: "Старая")]), now: .now.addingTimeInterval(-86_400))
        // Вместо папки Backups лежит файл — создать копию не получится.
        try Data().write(to: persistence.backupsDirectory)

        try persistence.save(StoreSnapshot(tasks: [TaskItem(title: "Новая")]))
        guard case .loaded(let snapshot) = persistence.load() else {
            Issue.record("основной файл должен записаться"); return
        }
        #expect(snapshot.tasks.map(\.title) == ["Новая"])
    }

    @Test("Отмена снимка, снятого до полуночи, не оставляет отложенную задачу в стеке")
    func undoReappliesDuePromotion() {
        let store = TaskStore(persistence: nil)
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo

        let today = Day.today()
        let deferred = TaskItem(title: "Отложенная", status: .stack, deferredDate: today)
        let other = TaskItem(title: "Другая", status: .today)
        store.replaceAll(with: StoreSnapshot(tasks: [deferred, other]))

        undo.beginUndoGrouping()
        store.complete(id: other.id)          // снимок «до» ещё держит отложенную задачу в стеке
        undo.endUndoGrouping()
        store.promoteDueDeferred(today: today) // наступила полночь

        undo.undo()
        #expect(store.task(id: other.id)?.status == .today)
        #expect(store.task(id: deferred.id)?.status == .today)
        #expect(store.task(id: deferred.id)?.deferredDate == nil)
    }

    @Test func keepsSevenBackups() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = Persistence(directory: dir)
        let snapshot = StoreSnapshot(tasks: [TaskItem(title: "x")])
        for offset in (0...10).reversed() {
            try persistence.save(snapshot, now: .now.addingTimeInterval(Double(-offset) * 86_400))
        }
        #expect(persistence.backupFiles().count == Persistence.backupsToKeep)
    }

    @Test func settingsUseAndroidKeysAndDefaults() {
        let suite = "KotaTaskTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.coefficients == .defaults)
        #expect(settings.overloadLimitMinutes == 180)
        #expect(settings.assistanceLevel == .standard)
        #expect(settings.isDeferEnabled == false)

        settings.deferEnabledFlag = true
        settings.splitToday = false
        #expect(settings.isDeferEnabled == false, "откладывание требует разделения «Сегодня»/«Стек»")
        #expect(defaults.bool(forKey: "feat_defer"))

        settings.customRequired = [.purpose]
        #expect(defaults.bool(forKey: "custom_req_purpose"))
        #expect(AppSettings(defaults: defaults).customRequired == [.purpose])
    }
}
