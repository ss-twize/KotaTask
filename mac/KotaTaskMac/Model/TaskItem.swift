import Foundation

/// Задача. Поля и их JSON-имена повторяют Android-модель `Task` и формат её бэкапа v2:
/// даты — ISO-строки или "", время — миллисекунды эпохи, пустая категория — "".
/// Мёртвые поля Android (`assignee`, legacy `parent`) не переносятся.
struct TaskItem: Identifiable, Hashable, Sendable {
    static let defaultDuration = 30
    static let durationRange = 1...600

    var id: String
    var title: String
    var deadline: Day?
    /// Начало диапазона дедлайна. nil — диапазон начинается с даты создания.
    var deadlineStart: Day?
    var purpose: String
    /// Длительность в минутах. nil — не задана: так бывает только у родителя
    /// (время = сумма подзадач) или у подзадачи (время входит в родителя). См. `TaskTree`.
    var duration: Int?
    var importance: Importance
    var status: TaskStatus
    var created: Date
    var completed: Date?
    var projectId: String?
    var locationId: String?
    var taskTypeId: String?
    /// День, в который задача сама перейдёт из «Стека» в «Сегодня». nil — не отложена.
    var deferredDate: Day?
    /// Родитель, если это подзадача. Вложенность — один уровень.
    var parentId: String?
    /// Ручной порядок: в колонке проекта для задачи верхнего уровня, внутри родителя — для подзадачи.
    var sortIndex: Double

    init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        deadline: Day? = nil,
        deadlineStart: Day? = nil,
        purpose: String = "",
        duration: Int? = TaskItem.defaultDuration,
        importance: Importance = .medium,
        status: TaskStatus = .stack,
        created: Date = .now,
        completed: Date? = nil,
        projectId: String? = nil,
        locationId: String? = nil,
        taskTypeId: String? = nil,
        deferredDate: Day? = nil,
        parentId: String? = nil,
        sortIndex: Double = 0
    ) {
        self.id = id
        self.title = title
        self.deadline = deadline
        self.deadlineStart = deadlineStart
        self.purpose = purpose
        self.duration = duration
        self.importance = importance
        self.status = status
        self.created = created
        self.completed = completed
        self.projectId = projectId
        self.locationId = locationId
        self.taskTypeId = taskTypeId
        self.deferredDate = deferredDate
        self.parentId = parentId
        self.sortIndex = sortIndex
    }

    var isActive: Bool { status.isActive }
    var isDeferred: Bool { deferredDate != nil }

    /// День создания в текущем часовом поясе — начало диапазона по умолчанию.
    var createdDay: Day { Day(created) }

    /// Фактическое начало диапазона: явное или дата создания.
    var effectiveRangeStart: Day? {
        guard let deadline else { return nil }
        return deadlineStart ?? min(createdDay, deadline)
    }

    func categoryId(for kind: CategoryKind) -> String? {
        switch kind {
        case .project: projectId
        case .location: locationId
        case .taskType: taskTypeId
        }
    }

    mutating func setCategoryId(_ id: String?, for kind: CategoryKind) {
        switch kind {
        case .project: projectId = id
        case .location: locationId = id
        case .taskType: taskTypeId = id
        }
    }
}

extension TaskItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, deadline, deadlineStart, purpose, duration, importance, status
        case created, completed, projectId, locationId, taskTypeId, deferredDate
        case parentId, sortIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        deadline = Day(iso: try c.decodeIfPresent(String.self, forKey: .deadline) ?? "")
        deadlineStart = Day(iso: try c.decodeIfPresent(String.self, forKey: .deadlineStart) ?? "")
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        importance = try c.decodeIfPresent(Importance.self, forKey: .importance) ?? .medium
        let rawStatus = try c.decodeIfPresent(String.self, forKey: .status) ?? TaskStatus.stack.rawValue
        status = TaskStatus(rawValue: rawStatus) ?? .stack
        let createdMs = try c.decodeIfPresent(Int64.self, forKey: .created)
        created = createdMs.map { Date(milliseconds: $0) } ?? .now
        let completedMs = try c.decodeIfPresent(Int64.self, forKey: .completed) ?? 0
        completed = completedMs > 0 ? Date(milliseconds: completedMs) : nil
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)?.nilIfEmpty
        locationId = try c.decodeIfPresent(String.self, forKey: .locationId)?.nilIfEmpty
        taskTypeId = try c.decodeIfPresent(String.self, forKey: .taskTypeId)?.nilIfEmpty
        deferredDate = Day(iso: try c.decodeIfPresent(String.self, forKey: .deferredDate) ?? "")
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)?.nilIfEmpty
        sortIndex = try c.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(deadline?.iso ?? "", forKey: .deadline)
        try c.encode(deadlineStart?.iso ?? "", forKey: .deadlineStart)
        try c.encode(purpose, forKey: .purpose)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encode(importance, forKey: .importance)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(created.milliseconds, forKey: .created)
        try c.encode(completed?.milliseconds ?? 0, forKey: .completed)
        try c.encode(projectId ?? "", forKey: .projectId)
        try c.encode(locationId ?? "", forKey: .locationId)
        try c.encode(taskTypeId ?? "", forKey: .taskTypeId)
        try c.encode(deferredDate?.iso ?? "", forKey: .deferredDate)
        try c.encode(parentId ?? "", forKey: .parentId)
        try c.encode(sortIndex, forKey: .sortIndex)
    }
}

extension Date {
    init(milliseconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    var milliseconds: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
