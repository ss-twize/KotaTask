import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings? { settingsList.first }

    private var priorityColor: Color {
        switch task.priority {
        case 70...: return .blue
        case 40..<70: return .green
        default: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggleDone) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.status == .done ? .green : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.status == .done)
                    .foregroundColor(task.status == .done ? .secondary : .primary)
                if let due = task.dueDate {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("\(Int(task.priority))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(priorityColor)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
