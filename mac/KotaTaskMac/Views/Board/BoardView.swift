import SwiftUI

/// «Проекты → Общий»: все проекты колонками. Если ось «Проекты» выключена — один список «Задачи».
struct BoardView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var locationFilter: CategoryFilter = .any
    @State private var typeFilter: CategoryFilter = .any

    var body: some View {
        let settings = model.settings
        let all = model.store.tasks
        let context = model.sortContext
        let projectsOn = settings.projectsEnabled
        let location = settings.locationsEnabled ? effective(locationFilter, .location) : .any
        let taskType = settings.taskTypesEnabled ? effective(typeFilter, .taskType) : .any
        let filtering = !query.trimmingCharacters(in: .whitespaces).isEmpty || location != .any || taskType != .any
        let rawColumns = projectsOn
            ? BoardQueries.columns(all: all, projects: model.store.categories(.project))
            : [BoardColumn(scope: .all, title: "Задачи", tasks: BoardQueries.topLevel(in: .all, all: all))]
        let columns = filtering
            ? rawColumns.map { column in
                BoardColumn(scope: column.scope, title: column.title, tasks: column.tasks.filter {
                    BoardQueries.matches($0, query: query, location: location, taskType: taskType, all: all)
                })
            }
            : rawColumns
        let total = rawColumns.reduce(0) { $0 + $1.tasks.count }
        let projectCount = rawColumns.count - 1

        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(
                title: projectsOn ? "Общий" : "Задачи",
                subtitle: projectsOn
                    ? "\(projectCount) \(RuFormat.plural(projectCount, one: "проект", few: "проекта", many: "проектов")) · \(RuFormat.tasksCount(total))"
                    : RuFormat.tasksCount(total)
            ) {
                if projectsOn {
                    HStack(spacing: 8) {
                        HiddenColumnsMenu()
                        Button {
                            model.categoryEdit = CategoryEdit(kind: .project, mode: .create)
                        } label: {
                            Label("Проект", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .help("Новый проект — новая колонка")
                    }
                    .animation(Motion.snappy, value: model.store.categories(.project).filter(\.hiddenOnBoard).count)
                }
            }

            HStack(spacing: 10) {
                TodayLoadPill(minutes: TaskTree.todayLoadMinutes(all))
                BoardFilterBar(locationFilter: $locationFilter, typeFilter: $typeFilter)
            }

            if projectsOn {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(columns) { column in
                            BoardColumnView(column: column, context: context, width: 280, reorderEnabled: !filtering)
                        }
                    }
                    .padding(.bottom, 6)
                    .animation(Motion.standard, value: columns.map(\.id))
                }
                .scrollIndicators(.visible)
            } else if let column = columns.first {
                BoardColumnView(column: column, context: context, width: nil, reorderEnabled: !filtering, showsHeader: false)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.canvas)
        .navigationTitle(projectsOn ? "Общий" : "Задачи")
        .searchable(text: $query, placement: .toolbar, prompt: "Поиск по задачам…")
    }

    /// Фильтр по удалённой категории ведёт себя как «все».
    private func effective(_ filter: CategoryFilter, _ kind: CategoryKind) -> CategoryFilter {
        if case .only(let id) = filter, model.store.category(kind, id: id) == nil { return .any }
        return filter
    }
}

/// Сколько минут уже в «Сегодня» — цвет светофора нагрузки.
struct TodayLoadPill: View {
    @Environment(AppModel.self) private var model
    let minutes: Int

    var body: some View {
        let load = model.settings.dayLoad(minutes: minutes, count: 0)
        HStack(spacing: 6) {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(Palette.loadInk(load.level))
            Text("\(minutes)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.loadInk(load.level))
                .contentTransition(.numericText(value: Double(minutes)))
            Text("мин в «Сегодня»")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.borderSubtle))
        .animation(Motion.standard, value: minutes)
    }
}

/// Фильтры по локации и типу (перенесены со старого экрана «Стек»).
struct BoardFilterBar: View {
    @Environment(AppModel.self) private var model
    @Binding var locationFilter: CategoryFilter
    @Binding var typeFilter: CategoryFilter

    var body: some View {
        HStack(spacing: 8) {
            if model.settings.locationsEnabled {
                filterMenu(kind: .location, selection: $locationFilter)
            }
            if model.settings.taskTypesEnabled {
                filterMenu(kind: .taskType, selection: $typeFilter)
            }
            if effective(locationFilter, .location) != .any || effective(typeFilter, .taskType) != .any {
                Button {
                    withAnimation(Motion.standard) {
                        locationFilter = .any
                        typeFilter = .any
                    }
                } label: {
                    Label("Сбросить", systemImage: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textTertiary)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Spacer()
        }
        .animation(Motion.snappy, value: locationFilter)
        .animation(Motion.snappy, value: typeFilter)
    }

    private func effective(_ filter: CategoryFilter, _ kind: CategoryKind) -> CategoryFilter {
        if case .only(let id) = filter, model.store.category(kind, id: id) == nil { return .any }
        return filter
    }

    private func filterMenu(kind: CategoryKind, selection: Binding<CategoryFilter>) -> some View {
        let categories = model.store.categories(kind)
        let current = effective(selection.wrappedValue, kind)
        let title: String = switch current {
        case .any: "\(kind.filterLabel): все"
        case .none: "Без \(kind.filterLabel.lowercased())"
        case .only(let id): categories.first { $0.id == id }?.name ?? "\(kind.filterLabel): все"
        }
        return CapsuleMenu(title: title, symbol: kind.symbol, isActive: current != .any) {
            Picker(kind.filterLabel, selection: Binding(
                get: { current },
                set: { newValue in withAnimation(Motion.standard) { selection.wrappedValue = newValue } }
            )) {
                Text("\(kind.filterLabel): все").tag(CategoryFilter.any)
                if !categories.isEmpty {
                    Divider()
                    ForEach(categories) { category in
                        Text(category.name).tag(CategoryFilter.only(category.id))
                    }
                }
                Divider()
                Text("Без \(kind.filterLabel.lowercased())").tag(CategoryFilter.none)
            }
            .pickerStyle(.inline)
        }
    }
}

/// «Скрыто: N» — возвращает скрытые колонки на доску. Пока скрытых нет, не показывается.
private struct HiddenColumnsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let hidden = model.store.categories(.project).filter(\.hiddenOnBoard)
        if !hidden.isEmpty {
            Menu {
                ForEach(hidden) { project in
                    Button(project.name, systemImage: "eye") { model.setProjectHidden(project, false) }
                }
                Divider()
                Button("Показать все", systemImage: "eye") { model.showAllProjectColumns() }
            } label: {
                Label("Скрыто: \(hidden.count)", systemImage: "eye.slash")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()
            .help("Скрытые колонки — вернуть на «Общий»")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}
