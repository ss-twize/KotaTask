import SwiftUI
import SwiftData

struct CategoryManagerView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.name) private var categories: [Category]

    @State private var newName = ""
    @State private var newKind: CategoryKind = .project

    private var projects:  [Category] { categories.filter { $0.kind == .project } }
    private var locations: [Category] { categories.filter { $0.kind == .location } }
    private var taskTypes: [Category] { categories.filter { $0.kind == .taskType } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Управление категориями").font(.headline)
                Spacer()
                Button("Готово") { isPresented = false }
            }
            .padding()

            Divider()

            HStack(alignment: .top, spacing: 20) {
                categoryColumn("Проекты", items: projects, kind: .project)
                Divider()
                categoryColumn("Места", items: locations, kind: .location)
                Divider()
                categoryColumn("Типы задач", items: taskTypes, kind: .taskType)
            }
            .padding()

            Divider()

            HStack {
                TextField("Название новой категории", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $newKind) {
                    ForEach(CategoryKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .frame(width: 140)
                Button("Добавить") { addCategory() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
    }

    @ViewBuilder
    private func categoryColumn(_ title: String, items: [Category], kind: CategoryKind) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundColor(.secondary)
            List {
                ForEach(items) { cat in
                    HStack {
                        Text(cat.name)
                        Spacer()
                        Button {
                            context.delete(cat)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 100)
        }
        .frame(maxWidth: .infinity)
    }

    private func addCategory() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.insert(Category(name: trimmed, kind: newKind))
        newName = ""
    }
}
