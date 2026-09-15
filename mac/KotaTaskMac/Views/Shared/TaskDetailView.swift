import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @State private var showEdit = false

    private var settings: AppSettings? { settingsList.first }

    private var priorityColor: Color {
        switch task.priority {
        case 70...: return .blue
        case 40..<70: return .green
        default: return .orange
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text(task.title)
                        .font(.title2).bold()
                    Spacer()
                    Text("\(Int(task.priority))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(priorityColor)
                }

                if !task.note.isEmpty {
                    Text(task.note)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Факторы приоритета")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    factorRow(label: "Срочность",  value: task.urgency)
                    factorRow(label: "Важность",   value: task.importance)
                    factorRow(label: "Усилия",     value: task.effort)
                }

                if let due = task.dueDate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.isDateRange ? "Диапазон" : "Дедлайн")
                            .font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                        if task.isDateRange, let end = task.endDate {
                            Text("\(due.formatted(date: .abbreviated, time: .omitted)) — \(end.formatted(date: .abbreviated, time: .omitted))")
                        } else {
                            Text(due, style: .date)
                        }
                    }
                }

                Divider()

                VStack(spacing: 8) {
                    Button("Редактировать") { showEdit = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                    Button(task.status == .done ? "Вернуть в работу" : "Отметить выполненным") {
                        toggleDone()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                    Button(task.isArchived ? "Разархивировать" : "В архив") {
                        task.isArchived.toggle()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showEdit) {
            AddTaskView(isPresented: $showEdit, editingTask: task)
        }
    }

    private func factorRow(label: String, value: Int) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= value ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
            Text("\(value)/5")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func toggleDone() {
        if task.status == .done {
            task.status = .todo
            task.completedAt = nil
        } else {
            task.status = .done
            task.completedAt = Date()
        }
        if let s = settings {
            task.priority = PriorityCalculator.calculate(task: task, settings: s)
        }
    }
}

struct NoSelectionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Выбери задачу")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
