import SwiftUI

/// Создание задачи строкой, как в Напоминаниях: название, ⏎ — задача создана и строка
/// ждёт следующую; Esc или пустое поле без фокуса — отмена.
struct InlineTaskField: View {
    @Environment(AppModel.self) private var model
    let container: TaskContainer
    let placeholder: String
    var compact = false
    /// Снаружи можно открыть строку (пункт «Новая задача» в меню колонки).
    var externalTrigger: Binding<Bool>?

    @State private var editing = false
    @State private var text = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(Palette.borderDefault, lineWidth: 1.5)
                        .frame(width: compact ? 14 : 17, height: compact ? 14 : 17)
                    TextField(placeholder, text: $text, prompt: Text(placeholder))
                        .textFieldStyle(.plain)
                        .font(.system(size: compact ? 12.5 : 13.5, weight: .medium))
                        .focused($focused)
                        .onSubmit(submit)
                        .onExitCommand(perform: cancel)
                }
                .padding(.horizontal, compact ? 5 : 11)
                .padding(.vertical, compact ? 6 : 10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: compact ? 8 : 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 8 : 13, style: .continuous)
                        .strokeBorder(Palette.accent.opacity(0.8), lineWidth: 1.5)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else {
                Button(action: start) {
                    Label(placeholder, systemImage: "plus")
                        .font(.system(size: compact ? 12 : 12.5, weight: .medium))
                        .foregroundStyle(hovering ? Palette.accentInk : Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, compact ? 5 : 11)
                        .padding(.vertical, compact ? 5 : 9)
                        .background(
                            RoundedRectangle(cornerRadius: compact ? 8 : 13, style: .continuous)
                                .fill(hovering ? Palette.accentSoft : .clear)
                        )
                        .overlay {
                            if !compact {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(Palette.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.98))
                .onHover { hovering = $0 }
            }
        }
        .animation(Motion.snappy, value: editing)
        .animation(Motion.snappy, value: hovering)
        .onChange(of: focused) { _, isFocused in
            if !isFocused && text.trimmingCharacters(in: .whitespaces).isEmpty { editing = false }
        }
        .onChange(of: externalTrigger?.wrappedValue ?? false) { _, requested in
            if requested {
                start()
                externalTrigger?.wrappedValue = false
            }
        }
    }

    private func start() {
        editing = true
        Task { @MainActor in focused = true }
    }

    private func submit() {
        if model.quickAdd(text, into: container) {
            text = ""
            focused = true
        } else {
            cancel()
        }
    }

    private func cancel() {
        text = ""
        editing = false
    }
}
