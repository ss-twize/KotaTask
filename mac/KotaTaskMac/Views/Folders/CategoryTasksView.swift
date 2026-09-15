import SwiftUI
import SwiftData

struct CategoryTasksView: View {
    let category: Category
    @Query private var allTasks: [AppTask]
    @State private var selectedTask: AppTask? = nil

    private var tasksForCategory: [AppTask] {
        allTasks.filter { task in
            switch category.kind {
            case .project:  return task.projectId == category.id && !task.isArchived
            case .location: return task.locationId == category.id && !task.isArchived
            case .taskType: return task.taskTypeId == category.id && !task.isArchived
            }
        }.sorted { $0.priority > $1.priority }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(category.name)
                        .font(.headline)
                        .padding()
                    Spacer()
                    Text("\(tasksForCategory.count) задач")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
                Divider()

                if tasksForCategory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("Нет задач в этой категории")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(tasksForCategory, selection: $selectedTask) { task in
                        TaskRowView(task: task).tag(task)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 280)

            Group {
                if let task = selectedTask {
                    TaskDetailView(task: task)
                } else {
                    NoSelectionView()
                }
            }
            .frame(minWidth: 220, maxWidth: 280)
        }
    }
}
