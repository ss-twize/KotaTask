import SwiftUI

/// Сайдбар вместо нижней навигации Android: разделы и папки трёх осей категорий.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var dropHighlight: SidebarItem?

    var body: some View {
        @Bindable var model = model
        let settings = model.settings
        let all = model.store.tasks

        List(selection: $model.selection) {
            Section {
                if settings.splitToday {
                    Label("Сегодня", systemImage: "sun.max")
                        .badge(TaskQueries.tasks(all, status: .today).count)
                        .tag(SidebarItem.today)
                        .modifier(SidebarDropTarget(item: .today, highlight: $dropHighlight) { id in
                            model.dropOnToday(taskId: id)
                        })
                }
                if !settings.projectsEnabled {
                    Label("Задачи", systemImage: "checklist")
                        .badge(BoardQueries.topLevel(in: .all, all: all).count)
                        .tag(SidebarItem.board)
                }
                if settings.calendarEnabled {
                    Label("Календарь", systemImage: "calendar")
                        .tag(SidebarItem.calendar)
                }
                Label("Архив", systemImage: "archivebox")
                    .tag(SidebarItem.archive)
            }

            if settings.projectsEnabled {
                Section {
                    Label("Общий", systemImage: "rectangle.split.3x1")
                        .badge(BoardQueries.topLevel(in: .all, all: all).count)
                        .tag(SidebarItem.board)
                    ForEach(model.store.categories(.project)) { project in
                        Label(project.name, systemImage: CategoryKind.project.symbol)
                            .badge(BoardQueries.topLevel(in: .project(project.id), all: all).count)
                            .tag(SidebarItem.project(project.id))
                            .contextMenu { projectMenu(project) }
                            .modifier(SidebarDropTarget(item: .project(project.id), highlight: $dropHighlight) { id in
                                model.dropOnProject(taskId: id, projectId: project.id)
                            })
                    }
                } header: {
                    sectionHeader(.project)
                }
            }

            ForEach(CategoryKind.allCases.filter { $0 != .project && settings.isCategoryEnabled($0) }) { kind in
                Section {
                    ForEach(model.store.categories(kind)) { category in
                        Label(category.name, systemImage: kind.symbol)
                            .badge(TaskQueries.activeCount(all, kind: kind, id: category.id))
                            .tag(SidebarItem.category(kind, category.id))
                            .contextMenu {
                                Button("Новая задача здесь…", systemImage: "plus") {
                                    model.presentNewTask(prefill: kind, categoryId: category.id)
                                }
                                Divider()
                                Button("Переименовать…", systemImage: "pencil") {
                                    model.categoryEdit = CategoryEdit(kind: kind, mode: .rename(category))
                                }
                                Button("Удалить…", systemImage: "trash", role: .destructive) {
                                    model.categoryPendingDeletion = (kind, category)
                                }
                            }
                    }
                    Label(kind.noneTitle, systemImage: "tray")
                        .foregroundStyle(Palette.textTertiary)
                        .badge(TaskQueries.activeCount(all, kind: kind, id: nil))
                        .tag(SidebarItem.category(kind, nil))
                } header: {
                    sectionHeader(kind)
                }
            }
        }
        .listStyle(.sidebar)
        .animation(Motion.standard, value: model.store.revision)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button {
                    openSettings()
                } label: {
                    Label("Настройки", systemImage: "gearshape")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(.borderless)
                Spacer()
                Button {
                    model.openURL(AppModel.donateURL)
                } label: {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Palette.carnation)
                }
                .buttonStyle(.borderless)
                .help("Поддержать проект")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
    }

    private func sectionHeader(_ kind: CategoryKind) -> some View {
        HStack {
            Text(kind.pluralTitle)
            Spacer()
            Button {
                model.categoryEdit = CategoryEdit(kind: kind, mode: .create)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderless)
            .help(kind.addTitle)
        }
    }

    @ViewBuilder
    private func projectMenu(_ project: Category) -> some View {
        Button("Переименовать…", systemImage: "pencil") {
            model.categoryEdit = CategoryEdit(kind: .project, mode: .rename(project))
        }
        Button("Удалить…", systemImage: "trash", role: .destructive) {
            model.categoryPendingDeletion = (.project, project)
        }
    }
}

/// Пункт сайдбара, на который можно бросить карточку с доски.
private struct SidebarDropTarget: ViewModifier {
    @Environment(AppModel.self) private var model
    let item: SidebarItem
    @Binding var highlight: SidebarItem?
    let perform: (String) -> Void

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(highlight == item ? Palette.accent.opacity(0.3) : .clear)
                    .padding(.horizontal, -6)
            )
            .onDrop(of: [.plainText], isTargeted: Binding(
                get: { highlight == item },
                set: { targeted in
                    guard model.boardDrag.draggingTaskId != nil else { return }
                    withAnimation(Motion.snappy) {
                        if targeted { highlight = item } else if highlight == item { highlight = nil }
                    }
                }
            )) { _ in
                defer { highlight = nil }
                guard let id = model.boardDrag.draggingTaskId else { return false }
                perform(id)
                model.boardDrag.end()
                return true
            }
    }
}
