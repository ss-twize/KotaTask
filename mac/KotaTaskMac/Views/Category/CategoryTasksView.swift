import SwiftUI

/// Активные задачи одной папки. `categoryId == nil` — системная папка «Без …».
struct CategoryTasksView: View {
    @Environment(AppModel.self) private var model
    let kind: CategoryKind
    let categoryId: String?
    @State private var sort: SortMode?

    var body: some View {
        let category = model.store.category(kind, id: categoryId)
        let title = category?.name ?? kind.noneTitle
        let mode = sort ?? model.settings.defaultSortMode
        let tasks = TaskQueries.active(model.store.tasks).filter { $0.categoryId(for: kind) == categoryId }
        let sorted = TaskQueries.sort(tasks, by: mode, context: model.sortContext)

        ScreenScroll {
            ScreenHeader(title: title, subtitle: "\(kind.singularTitle) · \(RuFormat.tasksCount(tasks.count))") {
                HStack(spacing: 8) {
                    SortMenu(selection: Binding(get: { mode }, set: { sort = $0 }))
                    if let category {
                        Menu {
                            Button("Переименовать…", systemImage: "pencil") {
                                model.categoryEdit = CategoryEdit(kind: kind, mode: .rename(category))
                            }
                            Button("Удалить…", systemImage: "trash", role: .destructive) {
                                model.categoryPendingDeletion = (kind, category)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(Palette.surface, in: Circle())
                                .overlay(Circle().strokeBorder(Palette.borderSubtle))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Действия с папкой")
                    }
                    Button {
                        model.presentNewTask(prefill: kind, categoryId: categoryId)
                    } label: {
                        Label("Задача", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Новая задача в этой папке")
                }
            }

            if sorted.isEmpty {
                EmptyState(symbol: kind.symbol, title: "Нет задач", subtitle: "Создайте задачу прямо в этой папке")
            } else {
                // В папке проекта метка проекта на карточках избыточна.
                ConnectedTaskGrid(
                    tasks: sorted,
                    mode: .byStatus(deferEnabled: model.settings.isDeferEnabled),
                    hideProject: kind == .project
                )
            }
        }
        .navigationTitle(title)
        .animation(Motion.standard, value: sorted.isEmpty)
    }
}
