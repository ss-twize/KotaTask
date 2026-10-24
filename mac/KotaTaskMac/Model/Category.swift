import Foundation

/// Проект, локация или тип задачи. Ось хранится не в самой записи, а в том,
/// в каком из трёх списков хранилища она лежит — как три таблицы в Android.
struct Category: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var created: Date
    var updated: Date
    /// Порядок колонок на доске «Общий» (используется у проектов).
    var sortIndex: Double

    init(id: String = UUID().uuidString.lowercased(), name: String, created: Date = .now, updated: Date = .now, sortIndex: Double = 0) {
        self.id = id
        self.name = name
        self.created = created
        self.updated = updated
        self.sortIndex = sortIndex
    }
}

extension Category: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, created, updated, sortIndex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        created = Date(milliseconds: try c.decodeIfPresent(Int64.self, forKey: .created) ?? Date.now.milliseconds)
        updated = Date(milliseconds: try c.decodeIfPresent(Int64.self, forKey: .updated) ?? Date.now.milliseconds)
        sortIndex = try c.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(created.milliseconds, forKey: .created)
        try c.encode(updated.milliseconds, forKey: .updated)
        try c.encode(sortIndex, forKey: .sortIndex)
    }
}

/// Фильтр по одной оси категорий: «все», «без категории» или конкретная.
enum CategoryFilter: Hashable, Sendable {
    case any
    case none
    case only(String)

    func matches(_ id: String?) -> Bool {
        switch self {
        case .any: true
        case .none: id == nil
        case .only(let wanted): id == wanted
        }
    }
}
