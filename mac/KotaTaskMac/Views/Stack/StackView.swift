import SwiftUI
import SwiftData

struct StackView: View {
    @Query(
        filter: #Predicate<AppTask> {
            !$0.isArchived &&
            $0.statusRaw != "done" &&
            $0.statusRaw != "cancelled"
        },
        sort: \AppTask.priority,
        order: .reverse
    )
    private var tasks: [AppTask]

    @State private var selectedTask: AppTask? = nil
    @State private var searchText = ""

    private var filteredTasks: [AppTask] {
        guard !searchText.isEmpty else { return tasks }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Поиск", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                if filteredTasks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "Стек пуст" : "Ничего не найдено")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredTasks, selection: $selectedTask) { task in
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
        .navigationTitle("Стек (\(tasks.count))")
    }
}
