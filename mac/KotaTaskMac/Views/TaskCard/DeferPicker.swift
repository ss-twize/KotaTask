import SwiftUI

enum DeferPickerResult {
    case day(Day)
    case clear
    case cancel
}

/// Поповер «Отложить до»: только даты строго после сегодня (минимум — завтра).
struct DeferPicker: View {
    let task: TaskItem
    let today: Day
    let onDone: (DeferPickerResult) -> Void

    @State private var date: Date

    init(task: TaskItem, today: Day, onDone: @escaping (DeferPickerResult) -> Void) {
        self.task = task
        self.today = today
        self.onDone = onDone
        let tomorrow = today.adding(days: 1)
        let preselect = task.deferredDate.flatMap { $0 > today ? $0 : nil } ?? tomorrow
        _date = State(initialValue: preselect.date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Отложить до")
                .font(.system(size: 15, weight: .semibold))
            Text("Задача сама перейдёт в «Сегодня» в выбранный день.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: 240, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            DatePicker("", selection: $date, in: today.adding(days: 1).date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, RuFormat.locale)
                .environment(\.calendar, .kota)

            HStack(spacing: 6) {
                quick("Завтра", days: 1)
                quick("+3 дня", days: 3)
                quick("Неделя", days: 7)
            }

            HStack {
                if task.isDeferred {
                    Button("Снять", role: .destructive) { onDone(.clear) }
                }
                Spacer()
                Button("Отмена") { onDone(.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button("Отложить") { onDone(.day(Day(date))) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.deferPurple)
            }
        }
        .padding(16)
        .fixedSize()
    }

    private func quick(_ title: String, days: Int) -> some View {
        Button(title) {
            withAnimation(Motion.snappy) { date = today.adding(days: days).date() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
