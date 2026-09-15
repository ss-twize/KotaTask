import SwiftUI
import SwiftData

struct FoldersView: View {
    @Query(sort: \Category.name) private var categories: [Category]
    @State private var showCategoryManager = false
    @State private var selectedCategory: Category? = nil

    private var projects:  [Category] { categories.filter { $0.kind == .project } }
    private var locations: [Category] { categories.filter { $0.kind == .location } }
    private var taskTypes: [Category] { categories.filter { $0.kind == .taskType } }

    var body: some View {
        HSplitView {
            List(selection: $selectedCategory) {
                categorySection("Проекты", items: projects, icon: "folder.fill")
                categorySection("Места", items: locations, icon: "mappin.circle.fill")
                categorySection("Типы задач", items: taskTypes, icon: "tag.fill")
            }
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem {
                    Button(action: { showCategoryManager = true }) {
                        Label("Управление категориями", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .frame(minWidth: 220)

            Group {
                if let cat = selectedCategory {
                    CategoryTasksView(category: cat)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Выбери категорию")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300)
        }
        .navigationTitle("Папки")
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagerView(isPresented: $showCategoryManager)
        }
    }

    @ViewBuilder
    private func categorySection(_ title: String, items: [Category], icon: String) -> some View {
        Section(title) {
            ForEach(items) { cat in
                Label(cat.name, systemImage: icon)
                    .tag(cat)
            }
        }
    }
}
