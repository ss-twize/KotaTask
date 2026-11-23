import Foundation
import Testing
@testable import KotaTask

@Suite("Текстовый экспорт")
struct ExportTests {
    @Test func activeTasksFieldsAndLegend() {
        let now = Date(timeIntervalSince1970: 0)
        let task = TaskItem(id: "draft", title: "Позвонить", deadline: Day(iso: "2026-11-23"),
                            deadlineStart: Day(iso: "2026-11-21"), purpose: "Контекст",
                            duration: 45, importance: .high, status: .today, created: now,
                            projectId: "p", locationId: "l", taskTypeId: "t",
                            deferredDate: Day(iso: "2026-11-22"), needsDetails: true)
        let snapshot = StoreSnapshot(
            tasks: [task, TaskItem(id: "stack", title: "Запас"), TaskItem(id: "archived", title: "Секрет архива", status: .archive)],
            projects: [KotaTask.Category(id: "p", name: "Проект")],
            locations: [KotaTask.Category(id: "l", name: "Дом")],
            taskTypes: [KotaTask.Category(id: "t", name: "Звонок")]
        )
        let text = TaskTextExport.render(snapshot)
        for value in ["Всего: 2.", "Контекст", "2026-11-23", "2026-11-21", "Проект", "Дом", "Звонок",
                      "1970-01-01T00:00:00Z", "2026-11-22", "Да", "| draft |", "| stack |"] {
            #expect(text.contains(value))
        }
        #expect(!text.contains("Секрет архива"))
        #expect(text.range(of: "Пояснения столбцов")!.lowerBound < text.range(of: "| draft |")!.lowerBound)
    }

    @Test func subtasksAndEffectiveMinutes() {
        let parent = TaskItem(id: "p", title: "Родитель", duration: nil, sortIndex: 0)
        let child = TaskItem(id: "c", title: "Шаг", duration: 45, parentId: "p", sortIndex: 1)
        let text = TaskTextExport.render(StoreSnapshot(tasks: [parent, child]))
        #expect(text.contains("| p | Стек | Родитель | — | — | — | — | 45 |"))
        #expect(text.contains("| Нет | p | Родитель |"))
        #expect(text.contains("| c |"))
    }

    @Test func escapingAndLargeExport() {
        let tasks = (0..<2500).map { i in
            TaskItem(id: "task-\(i)", title: "Строка | \(i)\nпродолжение\\", purpose: "а\tб")
        }
        let text = TaskTextExport.render(StoreSnapshot(tasks: tasks))
        #expect(text.contains("Строка \\| 2499\\nпродолжение\\\\"))
        #expect(text.contains("а\\tб"))
        #expect(text.split(separator: "\n").filter { $0.hasPrefix("| task-") }.count == 2500)
    }

    @Test func oldAndNewDraftFlagRoundTrip() throws {
        let old = Data(#"{"version":2,"tasks":[{"id":"a","title":"Старая","duration":30}]}"#.utf8)
        #expect(try Persistence.decode(old).tasks.first?.needsDetails == false)
        let task = TaskItem(title: "Черновик", needsDetails: true)
        let decoded = try Persistence.decode(Persistence.encode(StoreSnapshot(tasks: [task])))
        #expect(decoded.tasks.first?.needsDetails == true)
    }

    @Test @MainActor func fullFormClearsDraftMarker() {
        let store = TaskStore(persistence: nil)
        let draft = TaskItem(id: "a", title: "На бегу", needsDetails: true)
        store.replaceAll(with: StoreSnapshot(tasks: [draft]))
        store.updateTask(id: draft.id, with: ValidatedTask(
            title: "Уточнённая", deadlineStart: nil, deadline: nil, importance: .medium,
            duration: 30, purpose: "Контекст", projectId: nil, locationId: nil, taskTypeId: nil
        ))
        #expect(store.task(id: draft.id)?.needsDetails == false)
    }
}
