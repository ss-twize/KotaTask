import SwiftUI

/// Необязательная дата: кнопка с датой открывает календарь в поповере.
struct OptionalDateField: View {
    let label: String
    let placeholder: String
    @Binding var date: Day?
    let minimum: Day?
    let isRequired: Bool
    let error: String?

    @State private var showPicker = false

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundStyle(date == nil ? Palette.textHint : Palette.accentInk)
                        Text(date.map { "\(RuFormat.long($0)), \(RuFormat.weekday($0).lowercased())" } ?? placeholder)
                            .foregroundStyle(date == nil ? Palette.textTertiary : Palette.textPrimary)
                            .contentTransition(.interpolate)
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(error == nil ? Palette.borderSubtle : Palette.error.opacity(0.7))
                    )
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
                .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                    DatePopover(date: $date, minimum: minimum) { showPicker = false }
                }
                if date != nil {
                    Button {
                        withAnimation(Motion.snappy) { date = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.textHint)
                    }
                    .buttonStyle(.plain)
                    .help("Убрать дату")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Motion.snappy, value: date)
        } label: {
            FieldLabel(text: label, isRequired: isRequired)
        }
        FieldError(message: error)
    }
}

/// Календарь в поповере с быстрыми датами.
private struct DatePopover: View {
    @Binding var date: Day?
    let minimum: Day?
    let onDone: () -> Void

    @State private var working: Date

    init(date: Binding<Day?>, minimum: Day?, onDone: @escaping () -> Void) {
        _date = date
        self.minimum = minimum
        self.onDone = onDone
        let today = Day.today()
        let initial = date.wrappedValue ?? max(today, minimum ?? today)
        _working = State(initialValue: initial.date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let minimum {
                    DatePicker("", selection: $working, in: minimum.date()..., displayedComponents: .date)
                } else {
                    DatePicker("", selection: $working, displayedComponents: .date)
                }
            }
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.locale, RuFormat.locale)
            .environment(\.calendar, .kota)

            HStack(spacing: 6) {
                quick("Сегодня", 0)
                quick("Завтра", 1)
                quick("Через неделю", 7)
            }
            HStack {
                Spacer()
                Button("Отмена", action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button("Готово") {
                    date = Day(working)
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .fixedSize()
    }

    private func quick(_ title: String, _ days: Int) -> some View {
        let day = Day.today().adding(days: days)
        return Button(title) {
            date = day
            onDone()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(minimum.map { day < $0 } ?? false)
    }
}

/// Подпись поля с пометкой обязательности.
struct FieldLabel: View {
    let text: String
    var isRequired = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if isRequired {
                Text("обязательно")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.accentInk)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Palette.accentSoft, in: Capsule())
            }
        }
    }
}

/// Три «пилюли» важности.
struct ImportancePicker: View {
    @Binding var importance: Importance

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Importance.allCases) { value in
                let selected = value == importance
                Button {
                    withAnimation(Motion.snappy) { importance = value }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Palette.importance(value))
                            .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                            .frame(width: 9, height: 9)
                        Text(value.title)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule().fill(selected ? Palette.importance(value).opacity(0.28) : Palette.surfaceAlt)
                    )
                    .overlay(
                        Capsule().strokeBorder(selected ? Palette.importanceStripe(value) : Palette.borderSubtle, lineWidth: selected ? 1.5 : 1)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
            }
        }
    }
}

/// Выбор категории меню с пунктом быстрого создания — как «Добавить новый…» в Android.
struct CategoryMenuField: View {
    @Environment(AppModel.self) private var model
    let kind: CategoryKind
    @Binding var selection: String?
    /// Алерт создания показывается поверх формы её собственным листом: второй лист
    /// с корня окна, пока открыт первый, не появился бы.
    @Binding var categoryEdit: CategoryEdit?
    let isRequired: Bool
    let error: String?

    var body: some View {
        let categories = model.store.categories(kind)
        let current = categories.first { $0.id == selection }
        LabeledContent {
            Menu {
                Button(kind.notSelectedTitle) { selection = nil }
                if !categories.isEmpty {
                    Divider()
                    ForEach(categories) { category in
                        Button {
                            selection = category.id
                        } label: {
                            if category.id == selection {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                }
                Divider()
                Button(kind.addTitle, systemImage: "plus") {
                    categoryEdit = CategoryEdit(kind: kind, mode: .create) { created in
                        selection = created.id
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: kind.symbol)
                    Text(current?.name ?? kind.notSelectedTitle)
                }
                .foregroundStyle(current == nil ? Palette.textTertiary : Palette.textPrimary)
            }
            .menuStyle(.button)
            .fixedSize()
        } label: {
            FieldLabel(text: kind.singularTitle, isRequired: isRequired)
        }
        FieldError(message: error)
    }
}
