import SwiftUI

/// Колонка доски или лист проекта: шапка, карточки в ручном порядке, строка «+ Новая задача».
struct BoardColumnView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let column: BoardColumn
    let context: SortContext
    /// Ширина колонки на доске; nil — лист проекта (растягивается до 720 pt).
    let width: CGFloat?
    /// Выключено при активном поиске или фильтре: перестановка внутри колонки запрещена.
    let reorderEnabled: Bool
    var showsHeader = true

    @State private var addRequested = false
    @State private var cardFrames: [String: CGRect] = [:]

    private var container: TaskContainer { .column(column.scope) }
    private var spaceName: String { "board-column-\(column.scope)" }

    var body: some View {
        let cards = model.boardCards(column.tasks, context: context)
        let drag = model.boardDrag
        let slot = slotIndex(cards: cards)
        let space = spaceName
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader { header }
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: DropGeometry.gap) {
                    ForEach(Array(visibleOrder(cards).enumerated()), id: \.element.card.id) { _, entry in
                        if entry.slotBefore {
                            DropSlot(height: drag.draggedHeight)
                        }
                        BoardCard(card: entry.card, today: model.clock.today, container: container)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { cardFrames[entry.card.id] = $0 }
                            .transition(cardTransition)
                    }
                    if slot == .end {
                        DropSlot(height: drag.draggedHeight)
                    }
                    InlineTaskField(container: container, placeholder: "Новая задача", externalTrigger: $addRequested)
                }
                .padding(.bottom, 24)
                .padding(.horizontal, 2)
                .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: cards.map(\.id))
                .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: slot)
            }
            .scrollIndicators(.automatic)
            .coordinateSpace(.named(space))
            .onDrop(of: [.plainText], delegate: ColumnDropDelegate(
                scope: column.scope,
                frames: cards.compactMap { card in cardFrames[card.id].map { (card.id, $0) } },
                reorderEnabled: reorderEnabled,
                model: model
            ))
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private enum Slot: Equatable { case none, before(String), end }

    /// Где сейчас раскрыт слот: перед какой карточкой (без учёта перетаскиваемой) или в конце.
    private func slotIndex(cards: [BoardCardModel]) -> Slot {
        guard case .insert(let c, let position) = model.boardDrag.target, c == container else { return .none }
        let others = cards.filter { $0.id != model.boardDrag.draggingTaskId }
        guard let position, position < others.count else { return .end }
        return .before(others[position].id)
    }

    private func visibleOrder(_ cards: [BoardCardModel]) -> [(card: BoardCardModel, slotBefore: Bool)] {
        let slot = slotIndex(cards: cards)
        return cards.map { card in (card, slot == .before(card.id)) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(column.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text("\(column.tasks.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
                .contentTransition(.numericText(value: Double(column.tasks.count)))
            Spacer(minLength: 4)
            Menu {
                Button("Новая задача", systemImage: "plus") { addRequested = true }
                if case .project(let id) = column.scope, let project = model.store.category(.project, id: id) {
                    Button("Скрыть с «Общего»", systemImage: "eye.slash") { model.setProjectHidden(project, true) }
                    Divider()
                    Button("Переименовать…", systemImage: "pencil") {
                        model.categoryEdit = CategoryEdit(kind: .project, mode: .rename(project))
                    }
                    Button("Удалить…", systemImage: "trash", role: .destructive) {
                        model.categoryPendingDeletion = (.project, project)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 22, height: 18)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isHeaderTarget ? Palette.accent : Palette.borderSubtle)
                .frame(height: isHeaderTarget ? 2 : 1)
        }
        .background(isHeaderTarget ? Palette.accentSoft.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .modifier(ProjectHeaderDrag(scope: column.scope, model: model))
        .animation(Motion.snappy, value: isHeaderTarget)
    }

    private var isHeaderTarget: Bool {
        if case .project(let id) = column.scope { return model.boardDrag.projectTarget == id }
        return false
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.92).combined(with: .opacity)
        )
    }
}

/// Шапку колонки проекта можно перетащить на другую шапку — колонки поменяются местами.
private struct ProjectHeaderDrag: ViewModifier {
    let scope: ProjectScope
    let model: AppModel

    func body(content: Content) -> some View {
        if case .project(let id) = scope {
            content
                .onDrag { model.boardDrag.beginProject(id) }
                .onDrop(of: [.plainText], delegate: ColumnHeaderDropDelegate(projectId: id, model: model))
                .help("Перетащите шапку, чтобы переставить колонку")
        } else {
            content
        }
    }
}
