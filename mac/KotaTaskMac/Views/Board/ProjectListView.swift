import SwiftUI

/// Лист одного проекта: те же карточки и тот же ручной порядок, что в его колонке на «Общем».
struct ProjectListView: View {
    @Environment(AppModel.self) private var model
    let projectId: String

    var body: some View {
        let project = model.store.category(.project, id: projectId)
        let tasks = BoardQueries.topLevel(in: .project(projectId), all: model.store.tasks)
        let column = BoardColumn(scope: .project(projectId), title: project?.name ?? "", tasks: tasks)

        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: project?.name ?? "Проект", subtitle: "Проект · \(RuFormat.tasksCount(tasks.count))") {
                if let project {
                    Menu {
                        ProjectVisibilityButton(project: project)
                        Divider()
                        Button("Переименовать…", systemImage: "pencil") {
                            model.categoryEdit = CategoryEdit(kind: .project, mode: .rename(project))
                        }
                        Button("Удалить…", systemImage: "trash", role: .destructive) {
                            model.categoryPendingDeletion = (.project, project)
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
                    .help("Действия с проектом")
                }
            }
            BoardColumnView(column: column, context: model.sortContext, width: nil, reorderEnabled: true, showsHeader: false)
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .navigationTitle(project?.name ?? "Проект")
    }
}

/// «Скрыть с «Общего»» / «Показать на «Общем»» — в меню листа проекта и в сайдбаре.
struct ProjectVisibilityButton: View {
    @Environment(AppModel.self) private var model
    let project: Category

    var body: some View {
        if project.hiddenOnBoard {
            Button("Показать на «Общем»", systemImage: "eye") { model.setProjectHidden(project, false) }
        } else {
            Button("Скрыть с «Общего»", systemImage: "eye.slash") { model.setProjectHidden(project, true) }
        }
    }
}
