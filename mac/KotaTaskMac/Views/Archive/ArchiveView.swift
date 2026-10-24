import SwiftUI

/// Архив выполненных задач: по убыванию времени выполнения, режим выбора и массовое удаление.
struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var confirmSelected = false
    @State private var confirmAll = false

    var body: some View {
        let archived = TaskQueries.archive(model.store.tasks)

        ScreenScroll {
            ScreenHeader(title: "Архив", subtitle: "Что уже сделано") {
                if !archived.isEmpty {
                    HStack(spacing: 8) {
                        if selecting {
                            Button(selected.count == archived.count ? "Снять выбор" : "Выбрать все") {
                                withAnimation(Motion.snappy) {
                                    selected = selected.count == archived.count ? [] : Set(archived.map(\.id))
                                }
                            }
                            .buttonStyle(.bordered)
                            Button("Удалить выбранные", role: .destructive) { confirmSelected = true }
                                .buttonStyle(.bordered)
                                .disabled(selected.isEmpty)
                        } else {
                            Button("Очистить архив", role: .destructive) { confirmAll = true }
                                .buttonStyle(.bordered)
                        }
                        Button(selecting ? "Готово" : "Выбрать") {
                            withAnimation(Motion.standard) {
                                selecting.toggle()
                                if !selecting { selected = [] }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.regular)
                    .transition(.opacity)
                }
            }

            if archived.isEmpty {
                EmptyState(symbol: "archivebox", title: "Архив пуст", subtitle: "Выполненные задачи появятся здесь")
            } else {
                TaskGrid(
                    cards: model.cards(for: archived, showScore: false),
                    mode: .archive,
                    today: model.clock.today,
                    selection: selecting ? selected : nil,
                    onToggleSelection: { task in
                        withAnimation(Motion.snappy) {
                            if selected.contains(task.id) { selected.remove(task.id) } else { selected.insert(task.id) }
                        }
                    },
                    onAction: { action, task in model.perform(action, on: task) }
                )
            }
        }
        .navigationTitle("Архив")
        .animation(Motion.standard, value: archived.isEmpty)
        .confirmationDialog(
            "Удалить выбранные?",
            isPresented: $confirmSelected,
            titleVisibility: .visible
        ) {
            Button("Удалить \(RuFormat.tasksCount(selected.count))", role: .destructive) {
                withAnimation(Motion.standard) { model.store.delete(ids: selected) }
                model.showToast("Удалено: \(RuFormat.tasksCount(selected.count))", symbol: "trash.fill", tint: Palette.error)
                selected = []
                selecting = false
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будет удалено \(RuFormat.tasksCount(selected.count)). Отменить можно через ⌘Z.")
        }
        .confirmationDialog(
            "Удалить весь архив?",
            isPresented: $confirmAll,
            titleVisibility: .visible
        ) {
            Button("Удалить \(RuFormat.tasksCount(archived.count))", role: .destructive) {
                let count = archived.count
                withAnimation(Motion.standard) { model.store.clearArchive() }
                model.showToast("Архив очищен: \(RuFormat.tasksCount(count))", symbol: "trash.fill", tint: Palette.error)
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будет удалено \(RuFormat.tasksCount(archived.count)). Отменить можно через ⌘Z.")
        }
    }
}
