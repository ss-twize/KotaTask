import SwiftUI

/// Месячный календарь с «пончиками» и списком задач выбранного дня.
/// На широком окне сетка и список рядом, на узком — друг под другом.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var month: YearMonth = YearMonth(Day.today())
    @State private var selected: Day = .today()
    @State private var direction: Edge = .trailing
    @State private var contentWidth: CGFloat = 900
    @Namespace private var selectionNamespace

    var body: some View {
        let settings = model.settings
        let mode = settings.calendarMode
        let all = model.store.tasks
        let today = model.clock.today

        ScreenScroll {
            ScreenHeader(title: "Календарь", subtitle: "Задачи по датам") {
                Picker("Режим", selection: Binding(
                    get: { settings.calendarMode },
                    set: { newValue in withAnimation(Motion.standard) { settings.calendarMode = newValue } }
                )) {
                    ForEach(CalendarMode.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Диапазон — задача видна весь период; точка — только в день дедлайна")
            }

            if contentWidth >= 960 {
                HStack(alignment: .top, spacing: 24) {
                    monthCard(all: all, mode: mode, today: today)
                        .frame(width: min(600, contentWidth * 0.52))
                    dayList(all: all, mode: mode, today: today)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    monthCard(all: all, mode: mode, today: today)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    dayList(all: all, mode: mode, today: today)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 56 } action: { contentWidth = $0 }
        .navigationTitle("Календарь")
    }

    // MARK: - Сетка месяца

    private func monthCard(all: [TaskItem], mode: CalendarMode, today: Day) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Button { go(by: -1) } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .help("Предыдущий месяц")
                Button {
                    jumpToToday(today)
                } label: {
                    Text(RuFormat.monthYear(month))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText())
                        .frame(minWidth: 170)
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
                .help("Вернуться к сегодняшнему дню")
                Button { go(by: 1) } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .help("Следующий месяц")
                Spacer()
                Button("Сегодня") { jumpToToday(today) }
                    .disabled(month == YearMonth(today) && selected == today)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 4) {
                ForEach(RuFormat.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(symbol == "Сб" || symbol == "Вс" ? Palette.textHint : Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            ZStack {
                monthGrid(all: all, mode: mode, today: today)
                    .id(month)
                    .transition(reduceMotion ? .opacity : .push(from: direction))
            }
            .clipped()
        }
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.borderSubtle))
    }

    private func monthGrid(all: [TaskItem], mode: CalendarMode, today: Day) -> some View {
        let cells = CalendarMonth.cells(for: month)
        let minutes = TaskTree.effectiveMinutesMap(all)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                DonutCell(
                    cell: cell,
                    tasks: TaskQueries.cellOrder(TaskQueries.tasks(on: cell.day, in: all, mode: mode)),
                    minutes: minutes,
                    isToday: cell.day == today,
                    isSelected: cell.day == selected,
                    appearDelay: Double(index) * 0.008,
                    selectionNamespace: selectionNamespace
                ) {
                    select(cell.day)
                }
            }
        }
    }

    // MARK: - Список дня

    private func dayList(all: [TaskItem], mode: CalendarMode, today: Day) -> some View {
        let tasks = TaskQueries.dayListOrder(TaskQueries.tasks(on: selected, in: all, mode: mode))
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RuFormat.weekday(selected) + (selected == today ? " · сегодня" : ""))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .textCase(.uppercase)
                Text("\(RuFormat.long(selected)) — \(tasks.isEmpty ? "нет задач" : RuFormat.tasksCount(tasks.count))")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
            }
            .animation(Motion.standard, value: selected)

            if tasks.isEmpty {
                EmptyState(symbol: "calendar", title: "Свободно", subtitle: "На этот день задач нет")
                    .frame(minHeight: 200)
            } else {
                ConnectedTaskGrid(tasks: tasks, mode: .byStatus(deferEnabled: false))
            }
        }
        .animation(Motion.standard, value: tasks.map(\.id))
    }

    // MARK: - Навигация

    private func go(by months: Int) {
        move(to: month.adding(months: months), selecting: nil)
    }

    private func select(_ day: Day) {
        move(to: YearMonth(day), selecting: day)
    }

    /// Направление сдвига ставится отдельным обновлением до смены месяца: уходящая
    /// сетка берёт переход из своего последнего состояния, и иначе уехала бы не туда.
    private func move(to target: YearMonth, selecting day: Day?) {
        let animation = Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)
        guard target != month else {
            if let day { withAnimation(animation) { selected = day } }
            return
        }
        direction = target > month ? .trailing : .leading
        Task { @MainActor in
            withAnimation(animation) {
                month = target
                if let day { selected = day }
            }
        }
    }

    private func jumpToToday(_ today: Day) {
        select(today)
    }
}
