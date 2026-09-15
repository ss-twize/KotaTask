import SwiftUI
import SwiftData

struct AddTaskView: View {
    @Binding var isPresented: Bool
    var editingTask: AppTask? = nil

    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]
    @Query private var settingsList: [AppSettings]

    @State private var title = ""
    @State private var note = ""
    @State private var urgency = 3
    @State private var importance = 3
    @State private var effort = 3
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var isDateRange = false
    @State private var endDate = Date()
    @State private var selectedProjectId: UUID? = nil
    @State private var selectedLocationId: UUID? = nil
    @State private var selectedTaskTypeId: UUID? = nil

    private var isEditing: Bool { editingTask != nil }
    private var settings: AppSettings? { settingsList.first }

    private var projects: [Category]  { categories.filter { $0.kind == .project } }
    private var locations: [Category] { categories.filter { $0.kind == .location } }
    private var taskTypes: [Category] { categories.filter { $0.kind == .taskType } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Редактировать задачу" : "Новая задача")
                    .font(.headline)
                Spacer()
                Button("Отмена") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Задача") {
                    TextField("Название", text: $title)
                    TextEditor(text: $note)
                        .frame(height: 60)
                        .overlay(
                            Group {
                                if note.isEmpty {
                                    Text("Заметка (необязательно)")
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 4)
                                        .padding(.top, 8)
                                        .allowsHitTesting(false)
                                }
                            }, alignment: .topLeading
                        )
                }

                Section("Факторы приоритета") {
                    factorPicker("Срочность", value: $urgency)
                    factorPicker("Важность", value: $importance)
                    factorPicker("Усилия (меньше = выше приоритет)", value: $effort)
                }

                Section("Дедлайн") {
                    Toggle("Установить дедлайн", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Дата", selection: $dueDate, displayedComponents: .date)
                        Toggle("Диапазон дат", isOn: $isDateRange)
                        if isDateRange {
                            DatePicker("До", selection: $endDate, displayedComponents: .date)
                        }
                    }
                }

                Section("Категории") {
                    categoryPicker("Проект", items: projects, selection: $selectedProjectId)
                    categoryPicker("Место", items: locations, selection: $selectedLocationId)
                    categoryPicker("Тип задачи", items: taskTypes, selection: $selectedTaskTypeId)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(isEditing ? "Сохранить" : "Добавить") {
                    saveTask()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 600)
        .onAppear { loadEditingTask() }
    }

    @ViewBuilder
    private func factorPicker(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker("", selection: value) {
                ForEach(1...5, id: \.self) { i in Text("\(i)").tag(i) }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }

    @ViewBuilder
    private func categoryPicker(_ label: String, items: [Category], selection: Binding<UUID?>) -> some View {
        Picker(label, selection: selection) {
            Text("— не выбрано —").tag(UUID?.none)
            ForEach(items) { cat in
                Text(cat.name).tag(Optional(cat.id))
            }
        }
    }

    private func loadEditingTask() {
        guard let t = editingTask else { return }
        title = t.title
        note = t.note
        urgency = t.urgency
        importance = t.importance
        effort = t.effort
        hasDueDate = t.dueDate != nil
        if let d = t.dueDate { dueDate = d }
        isDateRange = t.isDateRange
        if let e = t.endDate { endDate = e }
        selectedProjectId = t.projectId
        selectedLocationId = t.locationId
        selectedTaskTypeId = t.taskTypeId
    }

    private func saveTask() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let task: AppTask
        if let existing = editingTask {
            task = existing
        } else {
            task = AppTask(title: trimmed)
            context.insert(task)
        }

        task.title = trimmed
        task.note = note
        task.urgency = urgency
        task.importance = importance
        task.effort = effort
        task.dueDate = hasDueDate ? dueDate : nil
        task.isDateRange = isDateRange
        task.endDate = (hasDueDate && isDateRange) ? endDate : nil
        task.projectId = selectedProjectId
        task.locationId = selectedLocationId
        task.taskTypeId = selectedTaskTypeId

        if let s = settings {
            task.priority = PriorityCalculator.calculate(task: task, settings: s)
        }
    }
}
