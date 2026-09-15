import SwiftUI
import SwiftData

enum SidebarItem: String, CaseIterable, Identifiable {
    case today    = "Сегодня"
    case stack    = "Стек"
    case calendar = "Календарь"
    case folders  = "Папки"
    case archive  = "Архив"
    case settings = "Настройки"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today:    return "star.fill"
        case .stack:    return "list.bullet"
        case .calendar: return "calendar"
        case .folders:  return "folder"
        case .archive:  return "archivebox"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .today
    @State private var showAddTask = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
        } detail: {
            detailView(for: selectedItem)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showAddTask = true }) {
                            Label("Добавить задачу", systemImage: "plus")
                        }
                    }
                }
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskView(isPresented: $showAddTask)
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem?) -> some View {
        switch item {
        case .today:    TodayView()
        case .stack:    StackView()
        case .calendar: CalendarView()
        case .folders:  FoldersView()
        case .archive:  ArchiveView()
        case .settings: SettingsView()
        case nil:       TodayView()
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query private var tasks: [AppTask]

    private var todayCount: Int {
        tasks.filter { !$0.isArchived && ($0.status == .todo || $0.status == .inProgress) }.count
    }

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.icon)
                .badge(item == .today ? todayCount : 0)
        }
        .listStyle(.sidebar)
        .navigationTitle("KotaTask")
    }
}
