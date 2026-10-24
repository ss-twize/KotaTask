import SwiftUI

/// Создание и редактирование задачи — порт `AddTaskFragment`.
///
/// Видимость полей и обязательность берутся из настроек на момент открытия формы,
/// как в Android. Ошибки показываются у полей все сразу и исчезают при правке.
struct TaskFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: TaskFormRequest

    @State private var draft = TaskDraft()
    @State private var config: FormConfig = .everything
    @State private var errors: [FormField: String] = [:]
    @State private var loaded = false
    @State private var shake = 0
    @State private var categoryEdit: CategoryEdit?
    @FocusState private var titleFocused: Bool

    private var editingId: String? {
        if case .edit(let id) = request.mode { return id }
        return nil
    }

    /// Редактируемая задача — родитель или подзадача меняют правила поля длительности.
    private var editingTask: TaskItem? { editingId.flatMap(model.store.task(id:)) }

    /// Подсказка под длительностью для родителя и подзадачи; nil — обычная задача.
    private var treeDurationHint: String? {
        editingTask.flatMap { TaskTree.durationHint(for: $0, durationText: draft.durationText, in: model.store.tasks) }
    }

    private var fromCategory: Bool {
        if case .create(let kind, _) = request.mode { return kind != nil }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    TextField("Название", text: $draft.title, prompt: Text("Что нужно сделать?"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .font(.system(size: 15, weight: .medium))
                    FieldError(message: errors[.title])
                } header: {
                    FieldLabel(text: "Название", isRequired: true)
                }

                Section("Сроки") {
                    OptionalDateField(
                        label: "Начало дедлайна",
                        placeholder: "По умолчанию — дата создания",
                        date: $draft.deadlineStart,
                        minimum: editingId == nil ? model.clock.today : nil,
                        isRequired: config.isRequired(.deadlineStart),
                        error: errors[.deadlineStart]
                    )
                    OptionalDateField(
                        label: "Дедлайн",
                        placeholder: "Без дедлайна",
                        date: $draft.deadline,
                        // При редактировании прошедшие даты разрешены, при создании — нет.
                        minimum: editingId == nil ? model.clock.today : nil,
                        isRequired: config.isRequired(.deadline),
                        error: errors[.deadline]
                    )
                }

                Section("Важность") {
                    ImportancePicker(importance: $draft.importance)
                }

                if config.showDuration {
                    Section {
                        durationField
                        FieldError(message: errors[.duration])
                    } header: {
                        Text("Время")
                    } footer: {
                        Text(treeDurationHint.map { "От 1 до 600 минут. \($0)." } ?? "От 1 до 600 минут. Пустое поле — 30 минут.")
                            .foregroundStyle(Palette.textTertiary)
                            .contentTransition(.opacity)
                            .animation(Motion.snappy, value: treeDurationHint)
                    }
                }

                if config.showPurpose {
                    Section {
                        TextField("Цель", text: $draft.purpose, prompt: Text("Почему это важно?"), axis: .vertical)
                            .labelsHidden()
                            .textFieldStyle(.plain)
                            .lineLimit(2...5)
                        FieldError(message: errors[.purpose])
                    } header: {
                        FieldLabel(text: "Цель / контекст", isRequired: config.isRequired(.purpose))
                    }
                }

                let kinds = CategoryKind.allCases.filter { config.visibleCategories.contains($0) }
                if !kinds.isEmpty {
                    Section("Категоризация") {
                        ForEach(kinds) { kind in
                            CategoryMenuField(
                                kind: kind,
                                selection: Binding(
                                    get: { draft.categoryId(for: kind) },
                                    set: { draft.setCategoryId($0, for: kind) }
                                ),
                                categoryEdit: $categoryEdit,
                                isRequired: config.isRequired(requirable(kind)),
                                error: errors[.category(kind)]
                            )
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            footer
        }
        .frame(width: 560)
        .frame(minHeight: 520, idealHeight: 680, maxHeight: 820)
        .background(Palette.canvas)
        .animation(Motion.snappy, value: errors.keys.count)
        .onChange(of: draft) { _, _ in
            if !errors.isEmpty { revalidateSilently() }
        }
        .onAppear(perform: load)
        .sheet(item: $categoryEdit) { edit in
            CategoryNameSheet(edit: edit)
        }
    }

    // MARK: - Шапка и подвал

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: editingId == nil ? "plus.circle.fill" : "pencil.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white, Palette.accent)
                .symbolEffect(.bounce, value: loaded)
            VStack(alignment: .leading, spacing: 2) {
                Text(editingId == nil ? "Новая задача" : "Редактирование")
                    .font(.system(size: 19, weight: .bold))
                Text(editingId == nil ? "Заполни поля — мы сами расставим приоритет" : "Измени любые поля и нажми «Сохранить»")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        HStack {
            if editingId != nil, let id = editingId, let task = model.store.task(id: id) {
                Button("Удалить", role: .destructive) {
                    dismiss()
                    model.perform(.delete, on: task)
                }
            }
            Spacer()
            Button("Отмена") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(editingId == nil ? "Создать задачу" : "Сохранить изменения") { submit() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .modifier(ShakeEffect(animatableData: CGFloat(shake)))
        }
        .controlSize(.large)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var durationField: some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField("", text: $draft.durationText, prompt: Text(config.allowsEmptyDuration ? "—" : "30"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onChange(of: draft.durationText) { _, value in
                        let digits = value.filter(\.isNumber)
                        if digits != value { draft.durationText = digits }
                    }
                Text("мин").foregroundStyle(Palette.textTertiary)
                Stepper("", value: Binding(
                    get: { Int(draft.durationText) ?? TaskItem.defaultDuration },
                    set: { draft.durationText = String(min(max($0, TaskItem.durationRange.lowerBound), TaskItem.durationRange.upperBound)) }
                ), in: TaskItem.durationRange, step: 5)
                .labelsHidden()
                Divider().frame(height: 18)
                ForEach([15, 30, 60, 90], id: \.self) { minutes in
                    Button("\(minutes)") {
                        withAnimation(Motion.snappy) { draft.durationText = String(minutes) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(draft.durationText == String(minutes) ? Palette.accent : nil)
                }
            }
        } label: {
            FieldLabel(text: "Длительность", isRequired: config.isRequired(.duration))
        }
    }

    // MARK: - Логика

    private func requirable(_ kind: CategoryKind) -> RequirableField {
        switch kind {
        case .project: .project
        case .location: .location
        case .taskType: .taskType
        }
    }

    private func load() {
        guard !loaded else { return }
        config = model.settings.formConfig
        switch request.mode {
        case .edit(let id):
            if let task = model.store.task(id: id) {
                draft = TaskDraft(task: task)
                config.allowsEmptyDuration = TaskTree.allowsEmptyDuration(task, in: model.store.tasks)
                // Подзадача всегда в проекте родителя — выбирать его здесь нечего.
                if task.parentId != nil { config.visibleCategories.remove(.project) }
            }
        case .create(let kind, let categoryId):
            if let kind { draft.setCategoryId(categoryId, for: kind) }
        }
        loaded = true
        titleFocused = true
    }

    private func revalidateSilently() {
        guard case .invalid(let found) = TaskValidator.validate(draft, config: config) else {
            errors = [:]
            return
        }
        // Убираем исправленные ошибки; новые не добавляем, пока пользователь не нажмёт «Сохранить».
        errors = errors.keys.reduce(into: [:]) { result, field in
            if let message = found[field] { result[field] = message }
        }
    }

    private func submit() {
        switch TaskValidator.validate(draft, config: config) {
        case .invalid(let found):
            withAnimation(Motion.snappy) { errors = found }
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
            if found[.title] != nil { titleFocused = true }
        case .valid(let values):
            if let id = editingId {
                withAnimation(Motion.standard) { model.store.updateTask(id: id, with: values) }
                model.didSaveForm(created: false, fromCategory: fromCategory)
            } else {
                withAnimation(Motion.standard) { _ = model.store.addTask(values) }
                model.didSaveForm(created: true, fromCategory: fromCategory)
            }
            dismiss()
        }
    }
}

/// Лёгкое покачивание кнопки при ошибке валидации.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(animatableData * .pi * 4), y: 0))
    }
}
