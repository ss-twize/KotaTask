import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Query(
        filter: #Predicate<AppTask> { $0.isArchived },
        sort: \AppTask.completedAt,
        order: .reverse
    )
    private var archivedTasks: [AppTask]

    @Environment(\.modelContext) private var context
    @State private var selectedTask: AppTask? = nil
    @State private var searchText = ""

    private var filteredTasks: [AppTask] {
        guard !searchText.isEmpty else { return archivedTasks }
        return archivedTasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Поиск в архиве", text: $searchText).textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                if filteredTasks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Архив пуст")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredTasks, selection: $selectedTask) { task in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(task.title)
                                    .strikethrough(task.status == .done)
                                if let completed = task.completedAt {
                                    Text(completed, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Text(task.status.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
        .navigationTitle("Архив (\(archivedTasks.count))")
    }
}
