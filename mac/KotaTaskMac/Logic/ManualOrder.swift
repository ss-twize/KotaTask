import Foundation

/// Ручной порядок карточек: колонки доски, лист проекта, подзадачи внутри родителя.
///
/// Индексы дробные: перестановка меняет одну запись — середину между соседями.
/// Когда соседи сближаются до предела точности, список перенумеровывается.
enum ManualOrder {
    static let minimumGap = 1e-6

    /// По `sortIndex`; при равенстве — новые сверху, как раньше отдавал стек.
    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { a, b in
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            if a.created != b.created { return a.created > b.created }
            return a.id < b.id
        }
    }

    /// Индекс для вставки в позицию `position` среди `siblings`.
    /// `siblings` уже отсортированы и не содержат перемещаемую задачу.
    static func index(insertingAt position: Int, among siblings: [TaskItem]) -> Double {
        index(insertingAt: position, amongIndices: siblings.map(\.sortIndex))
    }

    /// То же для голых индексов (колонки проектов).
    static func index(insertingAt position: Int, amongIndices indices: [Double]) -> Double {
        guard !indices.isEmpty else { return 0 }
        let p = min(max(position, 0), indices.count)
        if p == 0 { return indices[0] - 1 }
        if p == indices.count { return indices[p - 1] + 1 }
        return (indices[p - 1] + indices[p]) / 2
    }

    static func needsRenumbering(_ siblings: [TaskItem]) -> Bool {
        zip(siblings, siblings.dropFirst()).contains { $1.sortIndex - $0.sortIndex < minimumGap }
    }

    /// Индексы 0, 1, 2… в текущем порядке.
    static func renumbered(_ siblings: [TaskItem]) -> [String: Double] {
        Dictionary(siblings.enumerated().map { ($1.id, Double($0)) }, uniquingKeysWith: { a, _ in a })
    }
}
