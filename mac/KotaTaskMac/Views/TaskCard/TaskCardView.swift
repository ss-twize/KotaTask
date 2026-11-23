import SwiftUI

/// Данные одной карточки: задача и уже вычисленные подписи.
struct TaskCardModel: Identifiable, Equatable {
    let task: TaskItem
    let score: Double?
    /// Итоговое время для чипа (см. `AppModel.timeLabel`); nil — чип не показываем.
    let timeLabel: String?
    let locationName: String?
    let projectName: String?
    /// «↳ Родитель · Проект» у подзадачи; вместо строки проекта.
    var parentLabel: String? = nil
    /// У задачи открытые подзадачи: «Выполнить» открывает диалог, а не анимацию галочки.
    var needsCompletionChoice = false
    var id: String { task.id }
}

/// Набор кнопок карточки — порт `TabMode` из Android-адаптера.
enum CardMode: Equatable {
    case today
    case stack(deferEnabled: Bool)
    case merged
    /// Календарь и папки: кнопки зависят от статуса задачи.
    case byStatus(deferEnabled: Bool)
    case archive
}

/// Карточка задачи. Клик по телу открывает редактирование, кнопки — действия,
/// правый клик — контекстное меню со всеми действиями.
struct TaskCardView: View {
    let model: TaskCardModel
    let mode: CardMode
    let today: Day
    var isSelecting = false
    var isSelected = false
    var onAction: (TaskAction) -> Void
    var onToggleSelection: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var pressing = false
    @State private var completing = false
    @State private var showDeferPicker = false

    private var task: TaskItem { model.task }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Palette.importanceStripe(task.importance))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 10) {
                titleRow
                chipsRow
                metaRow
                if mode == .archive, let completed = task.completed {
                    Label("Завершено: \(RuFormat.archiveStamp(completed))", systemImage: "checkmark.seal")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                }
                if mode != .archive {
                    actionsRow
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .background(Palette.surface)
        .overlay(completionOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(border.color, lineWidth: border.emphasized ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 14 : 5, y: hovering ? 6 : 2)
        .scaleEffect(pressing ? 0.985 : (hovering && !reduceMotion ? 1.006 : 1))
        .offset(y: hovering && !reduceMotion ? -1 : 0)
        .animation(Motion.snappy, value: hovering)
        .animation(Motion.press, value: pressing)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture {
            if isSelecting { onToggleSelection() } else { onAction(.edit) }
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 8, perform: {}, onPressingChanged: { pressing = $0 })
        .contextMenu { contextMenu }
        .sensoryFeedback(.success, trigger: completing) { _, new in new }
        // После отмены (⌘Z) карточка возвращается — галочка выполнения не должна остаться.
        .onChange(of: task.status) { _, _ in completing = false }
        .onAppear { completing = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(task.title)
        .accessibilityAction(named: "Редактировать") { onAction(.edit) }
    }

    // MARK: - Строки

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 10) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.borderDefault)
                    .contentTransition(.symbolEffect(.replace))
                    .transition(.scale.combined(with: .opacity))
            }
            Text(task.title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(task.status == .archive ? Palette.textSecondary : Palette.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let score = model.score {
                Text(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), score))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.scoreText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.scoreBackground, in: Capsule())
                    .contentTransition(.numericText(value: score))
                    .help("Приоритет задачи")
            }
        }
    }

    private var chipsRow: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            if task.needsDetails {
                Chip(text: "Дополнить", symbol: "square.and.pencil", foreground: Palette.onWarning, background: Palette.warningSoft)
            }
            ImportanceLabel(importance: task.importance)
                .padding(.trailing, 2)
            if let deadline = task.deadline {
                let colors = deadlineColors(deadline)
                Chip(
                    // В архиве срок уже не горит — показываем просто дату.
                    text: mode == .archive
                        ? RuFormat.dateRange(start: task.deadlineStart, end: deadline)
                        : RuFormat.deadlineChip(start: task.deadlineStart, end: deadline, today: today),
                    symbol: "calendar",
                    foreground: colors.fg,
                    background: colors.bg
                )
            }
            if let timeLabel = model.timeLabel {
                Chip(text: timeLabel, symbol: "clock", foreground: Palette.textSecondary, background: Palette.surfaceAlt)
            }
            if task.isDeferred, task.status == .stack, case .byStatus = mode, let day = task.deferredDate {
                Chip(text: RuFormat.deferChip(day), symbol: "clock.arrow.circlepath", foreground: Palette.deferPurple, background: Palette.deferSoft)
            }
        }
    }

    @ViewBuilder
    private var metaRow: some View {
        if model.locationName != nil || model.projectName != nil || model.parentLabel != nil {
            FlowLayout(spacing: 12, lineSpacing: 4) {
                if let parent = model.parentLabel {
                    Text(parent)
                        .lineLimit(1)
                        .help("Подзадача")
                }
                if let location = model.locationName {
                    Label(location, systemImage: CategoryKind.location.symbol)
                }
                if let project = model.projectName {
                    Label(project, systemImage: CategoryKind.project.symbol)
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Palette.textTertiary)
            .labelStyle(CompactLabelStyle())
        }
    }

    @ViewBuilder
    private var actionsRow: some View {
        HStack(spacing: 8) {
            switch mode {
            case .today:
                completeButton
                toStackButton
            case .merged:
                completeButton
            case .stack(let deferEnabled):
                toTodayButton
                deleteButton
                if deferEnabled { deferButton }
            case .byStatus(let deferEnabled):
                if task.status == .today {
                    completeButton
                    toStackButton
                } else {
                    toTodayButton
                    deleteButton
                    if deferEnabled { deferButton }
                }
            case .archive:
                EmptyView()
            }
        }
    }

    // MARK: - Кнопки

    private var completeButton: some View {
        Button { complete() } label: {
            Label("Выполнить", systemImage: "checkmark")
        }
        .buttonStyle(CardActionStyle(kind: .filled(background: Palette.completeFill, foreground: Palette.completeInk)))
    }

    private var toStackButton: some View {
        Button { onAction(.toStack) } label: {
            Label("В стек", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(CardActionStyle(kind: .outlined(Palette.textSecondary)))
    }

    private var toTodayButton: some View {
        Button { onAction(.toToday) } label: {
            Label("В сегодня", systemImage: "scope")
        }
        .buttonStyle(CardActionStyle(kind: .filled(background: Palette.jordyBlue, foreground: Palette.onJordyBlue)))
    }

    private var deleteButton: some View {
        Button { onAction(.delete) } label: {
            Label("Удалить", systemImage: "trash")
        }
        .buttonStyle(CardActionStyle(kind: .outlined(Palette.error)))
    }

    private var deferButton: some View {
        Button { showDeferPicker = true } label: {
            Label(task.deferredDate.map(RuFormat.deferChip) ?? "Отложить", systemImage: "clock")
        }
        .buttonStyle(CardActionStyle(kind: .outlined(Palette.deferPurple)))
        .popover(isPresented: $showDeferPicker, arrowEdge: .bottom) {
            DeferPicker(task: task, today: today) { result in
                showDeferPicker = false
                switch result {
                case .day(let day): onAction(.deferTo(day))
                case .clear: onAction(.undefer)
                case .cancel: break
                }
            }
        }
    }

    // MARK: - Выполнение

    /// Сначала карточка подтверждает выполнение галочкой, затем уезжает из списка.
    private func complete() {
        guard !completing else { return }
        // Сначала диалог: если его отменят, галочка не должна остаться на открытой задаче.
        guard !model.needsCompletionChoice else { onAction(.complete); return }
        withAnimation(Motion.adaptive(Motion.bouncy, reduceMotion: reduceMotion)) { completing = true }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 340))
            onAction(.complete)
        }
    }

    @ViewBuilder
    private var completionOverlay: some View {
        if completing {
            ZStack {
                Palette.success.opacity(0.16)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white, Palette.success)
                    .symbolEffect(.bounce, value: completing)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            .transition(.opacity)
        }
    }

    // MARK: - Контекстное меню

    @ViewBuilder
    private var contextMenu: some View {
        Button("Редактировать…", systemImage: "pencil") { onAction(.edit) }
        if task.status != .archive {
            Divider()
            if task.status == .today {
                Button("Выполнить", systemImage: "checkmark.circle") { onAction(.complete) }
                if mode != .merged {
                    Button("В стек", systemImage: "arrow.uturn.backward") { onAction(.toStack) }
                }
            } else {
                if mode != .merged {
                    Button("В сегодня", systemImage: "scope") { onAction(.toToday) }
                }
                Button("Выполнить", systemImage: "checkmark.circle") { onAction(.complete) }
                if case .stack(true) = mode { deferMenu }
                if case .byStatus(true) = mode { deferMenu }
            }
        }
        Divider()
        Button("Удалить…", systemImage: "trash", role: .destructive) { onAction(.delete) }
    }

    @ViewBuilder
    private var deferMenu: some View {
        Menu("Отложить", systemImage: "clock") {
            Button("На завтра") { onAction(.deferTo(today.adding(days: 1))) }
            Button("Через 3 дня") { onAction(.deferTo(today.adding(days: 3))) }
            Button("Через неделю") { onAction(.deferTo(today.adding(days: 7))) }
            Button("Выбрать дату…") { showDeferPicker = true }
            if task.isDeferred {
                Divider()
                Button("Снять отложенность") { onAction(.undefer) }
            }
        }
    }

    // MARK: - Оформление

    private func deadlineColors(_ deadline: Day) -> (fg: Color, bg: Color) {
        if mode == .archive { return (Palette.textSecondary, Palette.surfaceAlt) }
        if deadline < today { return (Palette.error, Palette.errorSoft) }
        if deadline == today { return (Palette.onWarning, Palette.warningSoft) }
        return (Palette.accentInk, Palette.accentSoft)
    }

    /// Обводка кодирует состояние: отложенная — фиолетовая, «Сегодня» в календаре —
    /// акцентная, дедлайн сегодня — жёлтая, выделенная в архиве — акцентная.
    private var border: (color: Color, emphasized: Bool) {
        if isSelecting && isSelected { return (Palette.accent, true) }
        if mode == .archive { return (Palette.borderSubtle, false) }
        if task.isDeferred && task.status == .stack { return (Palette.deferPurple.opacity(0.8), true) }
        if case .byStatus = mode, task.status == .today { return (Palette.accent.opacity(0.7), true) }
        if task.deadline == today { return (Palette.warning, true) }
        return (hovering ? Palette.borderDefault : Palette.borderSubtle, false)
    }
}

/// Иконка и текст вплотную — для мелких подписей.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10.5, weight: .semibold))
            configuration.title.lineLimit(1)
        }
    }
}
