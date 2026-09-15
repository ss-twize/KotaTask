import Foundation

enum TaskStatus: String, Codable, CaseIterable {
    case todo       = "todo"
    case inProgress = "inProgress"
    case done       = "done"
    case cancelled  = "cancelled"

    var displayName: String {
        switch self {
        case .todo:       return "К выполнению"
        case .inProgress: return "В работе"
        case .done:       return "Готово"
        case .cancelled:  return "Отменено"
        }
    }
}

enum CategoryKind: String, Codable, CaseIterable {
    case project  = "project"
    case location = "location"
    case taskType = "taskType"

    var displayName: String {
        switch self {
        case .project:  return "Проект"
        case .location: return "Место"
        case .taskType: return "Тип задачи"
        }
    }
}
