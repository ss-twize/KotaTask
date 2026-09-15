import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(
        filter: #Predicate<AppTask> { !$0.isArchived },
        sort: \AppTask.priority, order: .reverse
    )
    private var allTasks: [AppTask]

    @State private var selectedDate = Date()
    @State private var selectedTask: AppTask? = nil

    private var tasksForSelectedDate: [AppTask] {
        allTasks.filter { task in
            guard let due = task.dueDate else { return false }
            if task.isDateRange, let end = task.endDate {
                return selectedDate >= Calendar.current.startOfDay(for: due) &&
                       selectedDate <= Calendar.current.startOfDay(for: end)
            }
            return Calendar.current.isDate(due, inSameDayAs: selectedDate)
        }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                DatePicker(
                    "Выбери дату",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()

                Divider()

                Text("Задачи на \(selectedDate.formatted(date: .long, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if tasksForSelectedDate.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Нет задач на этот день")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(tasksForSelectedDate, selection: $selectedTask) { task in
                        TaskRowView(task: task).tag(task)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 320)

            Group {
                if let task = selectedTask {
                    TaskDetailView(task: task)
                } else {
                    NoSelectionView()
                }
            }
            .frame(minWidth: 220, maxWidth: 280)
        }
        .navigationTitle("Календарь")
    }
}
