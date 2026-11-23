import SwiftUI

/// Корень окна: онбординг при первом запуске, иначе сайдбар и выбранный раздел.
/// Здесь же живут общие модальные окна: форма задачи, подтверждения, алерты категорий.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        ZStack {
            if model.settings.onboardingDone {
                mainSplit
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: model.settings.onboardingDone)
        .frame(minWidth: 680, minHeight: 560)
        .tint(Palette.accent)
        .onAppear {
            model.store.undoManager = undoManager
            model.start()
        }
        .onChange(of: undoManager) { _, manager in model.store.undoManager = manager }
        .onChange(of: model.settings.theme) { _, _ in model.applyTheme() }
        .onChange(of: model.settings.splitToday) { _, _ in model.normalizeSelection() }
        .onChange(of: model.settings.calendarEnabled) { _, _ in model.normalizeSelection() }
        .onChange(of: model.settings.projectsEnabled) { _, _ in model.normalizeSelection() }
        .onChange(of: model.settings.locationsEnabled) { _, _ in model.normalizeSelection() }
        .onChange(of: model.settings.taskTypesEnabled) { _, _ in model.normalizeSelection() }
        .onChange(of: model.settings.notificationsEnabled) { _, _ in model.rescheduleNotifications() }
        .onChange(of: model.settings.notificationHour) { _, _ in model.rescheduleNotifications() }
        .onChange(of: model.settings.notificationMinute) { _, _ in model.rescheduleNotifications() }
        .onChange(of: model.store.revision) { _, _ in model.rescheduleNotifications() }
        .alert(
            "Данные KotaTask",
            isPresented: Binding(get: { model.store.alertMessage != nil }, set: { if !$0 { model.store.alertMessage = nil } })
        ) {
            Button("Показать в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([model.store.dataFileURL ?? Persistence.standard().fileURL])
            }
            Button("ОК", role: .cancel) {}
        } message: {
            Text(model.store.alertMessage ?? "")
        }
    }

    private var mainSplit: some View {
        @Bindable var model = model
        return NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView(selection: model.selection)
                .toolbar {
                    ToolbarItem {
                        Button {
                            model.showsTaskExport = true
                        } label: {
                            Label("Экспорт", systemImage: "square.and.arrow.up")
                        }
                        .help("Весь стек и задачи на сегодня — текстом для чата или нейросети")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.presentNewTask()
                        } label: {
                            Label("Новая задача", systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                        .help("Новая задача (⌘N)")
                    }
                }
        }
        .overlay(alignment: .bottom) { ToastHost() }
        .sheet(item: $model.formRequest) { request in
            TaskFormView(request: request)
        }
        .sheet(isPresented: $model.showsTaskExport) {
            TaskExportView(text: TaskTextExport.render(model.store.snapshot))
        }
        .alert(
            "Удалить задачу?",
            isPresented: Binding(get: { model.taskPendingDeletion != nil }, set: { if !$0 { model.taskPendingDeletion = nil } }),
            presenting: model.taskPendingDeletion
        ) { task in
            Button("Удалить", role: .destructive) { model.confirmDeletion(of: task) }
            Button("Отмена", role: .cancel) {}
        } message: { task in
            let subtasks = TaskTree.children(of: task.id, in: model.store.tasks).count
            Text(subtasks > 0
                 ? "«\(task.title)»\n\nВместе с ней удалятся подзадачи: \(subtasks).\n\nОтменить удаление можно через ⌘Z."
                 : "«\(task.title)»\n\nОтменить удаление можно через ⌘Z.")
        }
        // Заголовок постоянный: у confirmationDialog с меняющимся при закрытии заголовком
        // диалог на macOS оставался висеть после выбора варианта.
        .alert(
            "Выполнить задачу с подзадачами?",
            isPresented: Binding(get: { model.parentPendingCompletion != nil }, set: { if !$0 { model.parentPendingCompletion = nil } }),
            presenting: model.parentPendingCompletion
        ) { task in
            Button("Выполнить вместе с подзадачами") { model.completeParent(task, closingSubtasks: true) }
            Button("Только задачу — подзадачи станут отдельными") { model.completeParent(task, closingSubtasks: false) }
            Button("Отмена", role: .cancel) {}
        } message: { task in
            Text("«\(task.title)»: открытых подзадач — \(TaskTree.openChildren(of: task.id, in: model.store.tasks).count).\n\nОтменить можно через ⌘Z.")
        }
        .confirmationDialog(
            "Удалить «\(model.categoryPendingDeletion?.category.name ?? "")»?",
            isPresented: Binding(get: { model.categoryPendingDeletion != nil }, set: { if !$0 { model.categoryPendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: model.categoryPendingDeletion
        ) { pending in
            Button("Удалить", role: .destructive) { model.deleteCategory(pending.kind, pending.category) }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Задачи из этой папки не удалятся — они просто потеряют привязку.")
        }
        .sheet(item: $model.categoryEdit) { edit in
            CategoryNameSheet(edit: edit)
        }
    }
}

/// Экран выбранного раздела.
struct DetailView: View {
    let selection: SidebarItem?

    var body: some View {
        Group {
            switch selection {
            case .today: TodayView()
            case .board, nil: BoardView()
            case .project(let id): ProjectListView(projectId: id).id("project-\(id)")
            case .calendar: CalendarView()
            case .archive: ArchiveView()
            case .category(let kind, let id): CategoryTasksView(kind: kind, categoryId: id).id("\(kind.rawValue)-\(id ?? "none")")
            }
        }
        .transition(.opacity)
    }
}

/// Ввод названия категории: создание и переименование.
struct CategoryNameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let edit: CategoryEdit
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var isRename: Bool {
        if case .rename = edit.mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: edit.kind.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text(isRename ? "Переименовать" : edit.kind.newItemPrompt)
                    .font(.system(size: 17, weight: .bold))
            }
            TextField("Название", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            FieldError(message: error)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isRename ? "Сохранить" : "Создать", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .animation(Motion.snappy, value: error)
        .onAppear {
            if case .rename(let category) = edit.mode { name = category.name }
            focused = true
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Введите название"
            return
        }
        switch edit.mode {
        case .create:
            if let created = model.store.addCategory(edit.kind, name: trimmed) {
                edit.onCreated?(created)
            }
        case .rename(let category):
            model.store.renameCategory(edit.kind, id: category.id, to: trimmed)
        }
        dismiss()
    }
}

/// Плавающее подтверждение действия с кнопкой «Отменить».
struct ToastHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let toast = model.toast {
                HStack(spacing: 10) {
                    Image(systemName: toast.symbol)
                        .foregroundStyle(toast.tint)
                        .font(.system(size: 15, weight: .semibold))
                        .symbolEffect(.bounce, value: toast.id)
                    Text(toast.message)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    if toast.undoable && toast.revision == model.store.revision {
                        Button("Отменить") { model.undo() }
                            .buttonStyle(.borderless)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.accentInk)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .id(toast.id)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.bottom, 22)
        .animation(Motion.bouncy, value: model.toast)
    }
}
