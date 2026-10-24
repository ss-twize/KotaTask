import SwiftUI

/// Адаптивная сетка карточек: на узком окне — одна колонка, на широком — несколько.
/// Перестановки при смене сортировки и появление/исчезновение карточек анимируются пружиной.
struct TaskGrid: View {
    let cards: [TaskCardModel]
    let mode: CardMode
    let today: Day
    var minimumColumnWidth: CGFloat = 320
    var selection: Set<String>? = nil
    var onToggleSelection: (TaskItem) -> Void = { _ in }
    var onAction: (TaskAction, TaskItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(cards) { card in
                TaskCardView(
                    model: card,
                    mode: mode,
                    today: today,
                    isSelecting: selection != nil,
                    isSelected: selection?.contains(card.id) ?? false,
                    onAction: { onAction($0, card.task) },
                    onToggleSelection: { onToggleSelection(card.task) }
                )
                .transition(cardTransition)
            }
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: cards.map(\.id))
    }

    private var cardTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }
}

/// Сетка карточек, которая сама отправляет действия в модель приложения.
struct ConnectedTaskGrid: View {
    @Environment(AppModel.self) private var model
    let tasks: [TaskItem]
    let mode: CardMode
    var hideProject = false
    var showScore = true

    var body: some View {
        TaskGrid(
            cards: model.cards(for: tasks, hideProject: hideProject, showScore: showScore),
            mode: mode,
            today: model.clock.today
        ) { action, task in
            model.perform(action, on: task)
        }
    }
}
