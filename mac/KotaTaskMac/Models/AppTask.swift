import Foundation
import SwiftData

@Model
final class AppTask {
    var id: UUID
    var title: String
    var note: String
    var statusRaw: String
    var priority: Double
    var urgency: Int
    var importance: Int
    var effort: Int
    var dueDate: Date?
    var endDate: Date?
    var isDateRange: Bool
    var createdAt: Date
    var completedAt: Date?
    var isArchived: Bool
    var projectId: UUID?
    var locationId: UUID?
    var taskTypeId: UUID?

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    init(
        title: String,
        note: String = "",
        urgency: Int = 3,
        importance: Int = 3,
        effort: Int = 3,
        dueDate: Date? = nil,
        isDateRange: Bool = false,
        endDate: Date? = nil,
        projectId: UUID? = nil,
        locationId: UUID? = nil,
        taskTypeId: UUID? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.note = note
        self.statusRaw = TaskStatus.todo.rawValue
        self.priority = 0.0
        self.urgency = urgency
        self.importance = importance
        self.effort = effort
        self.dueDate = dueDate
        self.isDateRange = isDateRange
        self.endDate = endDate
        self.createdAt = Date()
        self.isArchived = false
        self.projectId = projectId
        self.locationId = locationId
        self.taskTypeId = taskTypeId
    }
}
