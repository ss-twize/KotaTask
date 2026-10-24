import SwiftUI

/// «План на сегодня»: hero нагрузки и задачи со статусом «Сегодня».
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var sort: SortMode?

    var body: some View {
        let settings = model.settings
        let mode = sort ?? settings.defaultSortMode
        let todayTasks = TaskQueries.tasks(model.store.tasks, status: .today)
        let sorted = TaskQueries.sort(todayTasks, by: mode, context: model.sortContext)
        let load = settings.dayLoad(minutes: TaskTree.todayLoadMinutes(model.store.tasks), count: todayTasks.count)

        ScreenScroll {
            ScreenHeader(title: "План на сегодня", subtitle: "Сфокусируйся на главном") {
                SortMenu(selection: Binding(get: { mode }, set: { sort = $0 }))
            }
            DayLoadHero(load: load)
            if sorted.isEmpty {
                EmptyState(
                    symbol: "sun.max",
                    title: "Свободный день",
                    subtitle: "Добавь задачу из стека или создай новую"
                )
            } else {
                ConnectedTaskGrid(tasks: sorted, mode: .today)
            }
        }
        .navigationTitle("Сегодня")
        .animation(Motion.standard, value: sorted.isEmpty)
    }
}

/// Выбор сортировки — капсула с меню из семи режимов.
struct SortMenu: View {
    @Binding var selection: SortMode

    var body: some View {
        CapsuleMenu(title: selection.title, symbol: "arrow.up.arrow.down") {
            Picker("Сортировка", selection: Binding(
                get: { selection },
                set: { newValue in withAnimation(Motion.standard) { selection = newValue } }
            )) {
                ForEach(SortMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        }
        .help("Сортировка")
    }
}
