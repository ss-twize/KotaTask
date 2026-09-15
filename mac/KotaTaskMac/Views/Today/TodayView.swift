import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(
        filter: #Predicate<AppTask> {
            !$0.isArchived &&
            $0.statusRaw != "done" &&
            $0.statusRaw != "cancelled"
        },
        sort: \AppTask.priority,
        order: .reverse
    )
    private var allActiveTasks: [AppTask]

    @Query private var settingsList: [AppSettings]
    @State private var selectedTask: AppTask? = nil

    private var settings: AppSettings? { settingsList.first }
    private var limit: Int { settings?.dailyTaskLimit ?? 5 }
    private var displayedTasks: [AppTask] { Array(allActiveTasks.prefix(limit)) }
    private var hiddenCount: Int { max(0, allActiveTasks.count - limit) }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                if hiddenCount > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Скрыто ещё \(hiddenCount) задач — дневной лимит \(limit)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                }

                if displayedTasks.isEmpty {
                    emptyState
                } else {
                    List(displayedTasks, selection: $selectedTask) { task in
                        TaskRowView(task: task)
                            .tag(task)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 300)

            Group {
                if let task = selectedTask {
                    TaskDetailView(task: task)
                } else {
                    NoSelectionView()
                }
            }
            .frame(minWidth: 220, maxWidth: 280)
        }
        .navigationTitle("Сегодня")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Нет задач на сегодня")
                .foregroundColor(.secondary)
            Text("Нажми + чтобы добавить первую задачу")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
