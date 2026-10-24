import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Куда упадёт перетаскиваемая карточка.
enum DropTarget: Equatable {
    /// Вставка в колонку или в список подзадач; `position == nil` — в конец.
    case insert(TaskContainer, position: Int?)
    /// Сделать подзадачей карточки `parentId`.
    case nest(parentId: String)
}

/// Общее состояние перетаскивания на доске. Живёт в `AppModel.boardDrag`.
///
/// Полезная нагрузка системного drag-and-drop — просто текст с id, а принимают перенос
/// только наши цели и только пока здесь записано, что тащится именно задача или колонка:
/// чужой текст из других приложений задачей не станет.
@MainActor
@Observable
final class BoardDragState {
    static let payloadPrefix = "kotatask-task:"

    private(set) var draggingTaskId: String?
    private(set) var draggingProjectId: String?
    /// Откуда начали тащить карточку — для правила «при поиске внутри своей колонки не переставляем».
    private(set) var sourceContainer: TaskContainer?
    /// Высота перетаскиваемой карточки — такой же высоты раскрывается слот.
    private(set) var draggedHeight: CGFloat = 60
    var target: DropTarget?
    /// Шапка колонки, над которой держат перетаскиваемую колонку.
    var projectTarget: String?

    @ObservationIgnored private var watchdog: Task<Void, Never>?

    var isActive: Bool { draggingTaskId != nil || draggingProjectId != nil }

    func beginTask(_ id: String, from container: TaskContainer, height: CGFloat) -> NSItemProvider {
        draggingTaskId = id
        sourceContainer = container
        draggedHeight = min(max(height, 44), 160)
        target = nil
        startWatchdog()
        return NSItemProvider(object: (Self.payloadPrefix + id) as NSString)
    }

    func beginProject(_ id: String) -> NSItemProvider {
        draggingProjectId = id
        projectTarget = nil
        startWatchdog()
        return NSItemProvider(object: ("kotatask-project:" + id) as NSString)
    }

    func end() {
        draggingTaskId = nil
        draggingProjectId = nil
        sourceContainer = nil
        target = nil
        projectTarget = nil
        watchdog?.cancel()
        watchdog = nil
    }

    /// Бросок мимо всех целей системным колбэком не сообщается. Пока идёт перенос, кнопка мыши
    /// зажата; как только её отпустили, а перенос всё ещё «активен» — значит, его отменили.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.isActive else { return }
                if NSEvent.pressedMouseButtons == 0 {
                    // Даём performDrop завершиться первым.
                    try? await Task.sleep(for: .milliseconds(250))
                    if self.isActive && NSEvent.pressedMouseButtons == 0 { self.end() }
                    return
                }
            }
        }
    }
}

// MARK: - Цели броска

/// Колонка или лист проекта.
struct ColumnDropDelegate: DropDelegate {
    let scope: ProjectScope
    let frames: [(id: String, frame: CGRect)]
    let reorderEnabled: Bool
    let model: AppModel

    private var drag: BoardDragState { model.boardDrag }
    private var container: TaskContainer { .column(scope) }

    func validateDrop(info: DropInfo) -> Bool { drag.draggingTaskId != nil }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(Motion.snappy) {
            switch drag.target {
            case .insert(let c, _) where c == container: drag.target = nil
            case .nest(let parentId) where frames.contains(where: { $0.id == parentId }): drag.target = nil
            default: break
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let id = drag.draggingTaskId, let target = drag.target else { drag.end(); return false }
        model.drop(taskId: id, on: target)
        drag.end()
        return true
    }

    private func update(_ info: DropInfo) {
        guard let dragged = drag.draggingTaskId else { return }
        let others = frames.filter { $0.id != dragged }
        // Поиск или фильтр: в своей колонке не переставляем, в чужую — в конец.
        if !reorderEnabled {
            let next: DropTarget? = drag.sourceContainer == container ? nil : .insert(container, position: nil)
            if drag.target != next { withAnimation(Motion.snappy) { drag.target = next } }
            return
        }
        var slotIndex: Int?
        if case .insert(let c, let p) = drag.target, c == container { slotIndex = p }
        let result = DropGeometry.target(
            at: info.location.y, frames: others, slotIndex: slotIndex, slotHeight: drag.draggedHeight,
            canNest: { model.store.canPlace(dragged, into: .parent($0)) }
        )
        let next: DropTarget = result.nestInto.map { .nest(parentId: $0) } ?? .insert(container, position: result.position)
        if drag.target != next { withAnimation(Motion.snappy) { drag.target = next } }
    }
}

/// Раскрытый список подзадач: перестановка подзадач и вложение задачи на конкретное место.
struct SubtaskDropDelegate: DropDelegate {
    let parentId: String
    let frames: [(id: String, frame: CGRect)]
    let model: AppModel

    private var drag: BoardDragState { model.boardDrag }
    private var container: TaskContainer { .parent(parentId) }

    func validateDrop(info: DropInfo) -> Bool {
        guard let id = drag.draggingTaskId else { return false }
        return model.store.canPlace(id, into: container)
    }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if case .insert(let c, _) = drag.target, c == container {
            withAnimation(Motion.snappy) { drag.target = nil }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let id = drag.draggingTaskId, let target = drag.target else { drag.end(); return false }
        model.drop(taskId: id, on: target)
        drag.end()
        return true
    }

    private func update(_ info: DropInfo) {
        guard let dragged = drag.draggingTaskId else { return }
        var slotIndex: Int?
        if case .insert(let c, let p) = drag.target, c == container { slotIndex = p }
        let result = DropGeometry.target(
            at: info.location.y, frames: frames.filter { $0.id != dragged }, slotIndex: slotIndex,
            slotHeight: 26, canNest: { _ in false }
        )
        let next = DropTarget.insert(container, position: result.position)
        if drag.target != next { withAnimation(Motion.snappy) { drag.target = next } }
    }
}

/// Шапка колонки проекта: перестановка колонок.
struct ColumnHeaderDropDelegate: DropDelegate {
    let projectId: String
    let model: AppModel

    private var drag: BoardDragState { model.boardDrag }

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged = drag.draggingProjectId else { return false }
        return dragged != projectId
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        withAnimation(Motion.snappy) { drag.projectTarget = projectId }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        validateDrop(info: info) ? DropProposal(operation: .move) : DropProposal(operation: .forbidden)
    }

    func dropExited(info: DropInfo) {
        if drag.projectTarget == projectId { withAnimation(Motion.snappy) { drag.projectTarget = nil } }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = drag.draggingProjectId else { return false }
        withAnimation(Motion.standard) { model.store.moveProjectColumn(dragged, onto: projectId) }
        drag.end()
        return true
    }
}

// MARK: - Вид перетаскивания

/// Превью карточки под курсором: приподнята и чуть наклонена.
struct DragPreviewCard: View {
    let title: String
    let importance: Importance
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Palette.importanceStripe(importance)).frame(width: 3)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(width: 250, alignment: .leading)
        }
        .background(Palette.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Palette.accent, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
        .rotationEffect(.degrees(reduceMotion ? 0 : -2.5))
        .scaleEffect(reduceMotion ? 1 : 1.03)
        .padding(24)
    }
}

/// Раскрывшийся слот: место, куда упадёт карточка.
struct DropSlot: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Palette.accent.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .frame(height: height)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }
}
