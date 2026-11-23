import SwiftUI
import UniformTypeIdentifiers

struct TaskExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct TaskExportView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    @State private var copied = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Экспорт задач")
                .font(.title2.bold())
            Text("Весь стек и план на сегодня, включая подзадачи. Скопируйте текст в любой чат или нейросеть.")
                .foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.borderSubtle))
            HStack {
                Button(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(text, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                ShareLink(item: text) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                Button("Сохранить .txt", systemImage: "arrow.down.document") { saving = true }
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 640, idealWidth: 860, minHeight: 480, idealHeight: 620)
        .background(Palette.canvas)
        .fileExporter(isPresented: $saving, document: TaskExportDocument(text: text),
                      contentType: .plainText, defaultFilename: "KotaTask-задачи") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .alert("Не удалось сохранить файл", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("ОК", role: .cancel) {} } message: { Text(error ?? "") }
    }
}
