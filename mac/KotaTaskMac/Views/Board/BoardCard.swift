import SwiftUI

/// Данные карточки доски, посчитанные один раз на экран (см. `AppModel.boardCards`).
struct BoardCardModel: Identifiable, Equatable {
    let task: TaskItem
    /// Подзадачи в ручном порядке, включая выполненные.
    let children: [TaskItem]
    let score: Double?
    let timeLabel: String?
    let childTimeLabels: [String: String?]
    /// Уровень помощи требует дедлайн, а его нет (задача создана строкой).
    let missingDeadline: Bool
    var id: String { task.id }

    var doneChildren: Int { children.filter { $0.status == .archive }.count }
}

/// Компактная карточка доски: кружок выполнения, название, чипы и подзадачи внутри.
struct BoardCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let card: BoardCardModel
    let today: Day
    /// Откуда карточку тащат — колонка или лист проекта.
    let container: TaskContainer

    @State private var hovering = false
    @State private var completing = false
    @State private var height: CGFloat = 60
    @State private var subtaskFrames: [String: CGRect] = [:]

    private var task: TaskItem { card.task }
    private var isExpanded: Bool { model.expandedParents.contains(task.id) }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Palette.importanceStripe(task.importance))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 7) {
                // Карточку тащат за верх. Строки подзадач перетаскиваются сами по себе:
                // будь они внутри этого onDrag, после броска подзадачи срабатывал бы ещё
                // и перенос родителя.
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 9) {
                        CompletionCircle(isDone: completing, action: complete)
                            .padding(.top, 1)
                        Text(task.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let score = card.score {
                            ScoreBadge(score: score)
                        }
                    }
                    chips
                        .padding(.leading, 26)
                }
                .contentShape(Rectangle())
                .onDrag {
                    model.boardDrag.beginTask(task.id, from: container, height: height)
                } preview: {
                    DragPreviewCard(title: task.title, importance: task.importance, reduceMotion: reduceMotion)
                }
                if !card.children.isEmpty || isExpanded {
                    subtasks
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(isNestTarget ? Palette.accent : borderColor,
                              lineWidth: isNestTarget ? 2 : (task.isDeferred && task.status == .stack ? 1.5 : 1))
        )
        .overlay(alignment: .bottomTrailing) {
            if isNestTarget {
                Text("Сделать подзадачей")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Palette.onJordyBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.jordyBlue, in: Capsule())
                    .padding(8)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .opacity(model.boardDrag.draggingTaskId == task.id ? 0.35 : 1)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .shadow(color: .black.opacity(hovering ? 0.12 : 0.04), radius: hovering ? 10 : 3, y: hovering ? 4 : 1)
        .scaleEffect(hovering && !reduceMotion ? 1.008 : 1)
        .animation(Motion.snappy, value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { model.presentEdit(task) }
        .contextMenu { contextMenu }
        .sensoryFeedback(.success, trigger: completing) { _, new in new }
        .sensoryFeedback(.alignment, trigger: isNestTarget) { _, new in new }
        .animation(Motion.snappy, value: isNestTarget)
        .onChange(of: task.status) { _, _ in completing = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(task.title)
    }

    // MARK: - Части

    private var chips: some View {
        FlowLayout(spacing: 5, lineSpacing: 5) {
            if task.needsDetails {
                Chip(text: "Дополнить", symbol: "square.and.pencil", foreground: Palette.onWarning, background: Palette.warningSoft)
            }
            if task.status == .today {
                Chip(text: "Сегодня", symbol: "sun.max.fill", foreground: Palette.onWarning, background: Palette.warningSoft)
            }
            if let deadline = task.deadline {
                let colors = BoardCard.deadlineColors(deadline, today: today)
                Chip(text: BoardCard.deadlineText(task, deadline: deadline, today: today),
                     symbol: "calendar", foreground: colors.fg, background: colors.bg)
            } else if card.missingDeadline {
                Chip(text: "нет дедлайна", symbol: "exclamationmark.circle", foreground: Palette.onWarning, background: Palette.warningSoft)
            }
            if let label = card.timeLabel {
                Chip(text: label, symbol: "clock", foreground: label.hasPrefix("Σ") ? Palette.accentInk : Palette.textSecondary,
                     background: label.hasPrefix("Σ") ? Palette.accentSoft : Palette.surfaceAlt)
            }
            if let deferred = task.deferredDate, task.status == .stack {
                Chip(text: RuFormat.deferChip(deferred), symbol: "clock.arrow.circlepath", foreground: Palette.deferPurple, background: Palette.deferSoft)
            }
        }
    }

    private var subtasks: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !card.children.isEmpty {
                let total = card.children.count
                let done = card.doneChildren
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.surfaceAlt)
                        Capsule().fill(Palette.success)
                            .frame(width: proxy.size.width * CGFloat(done) / CGFloat(max(total, 1)))
                    }
                }
                .frame(height: 3)
                .animation(Motion.standard, value: done)

                Button {
                    withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { toggleExpanded() }
                } label: {
                    HStack {
                        Text("Подзадачи · \(done) из \(total)")
                            .contentTransition(.numericText(value: Double(done)))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.accentInk)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
            if isExpanded {
                let slot = subtaskSlot
                let space = subtaskSpace
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(card.children) { child in
                        if slot == .before(child.id) { subtaskSlotView }
                        SubtaskRow(task: child, timeLabel: card.childTimeLabels[child.id] ?? nil, today: today)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { subtaskFrames[child.id] = $0 }
                            .opacity(model.boardDrag.draggingTaskId == child.id ? 0.35 : 1)
                            .onDrag {
                                model.boardDrag.beginTask(child.id, from: .parent(task.id), height: 34)
                            } preview: {
                                DragPreviewCard(title: child.title, importance: child.importance, reduceMotion: reduceMotion)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if slot == .end { subtaskSlotView }
                    InlineTaskField(container: .parent(task.id), placeholder: "Подзадача", compact: true)
                }
                .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: slot)
                .coordinateSpace(.named(space))
                .onDrop(of: [.plainText], delegate: SubtaskDropDelegate(
                    parentId: task.id,
                    frames: card.children.compactMap { child in subtaskFrames[child.id].map { (child.id, $0) } },
                    model: model
                ))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 7)
        .overlay(alignment: .top) { Rectangle().fill(Palette.borderSubtle).frame(height: 1) }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Редактировать…", systemImage: "pencil") { model.presentEdit(task) }
        Button("Добавить подзадачу", systemImage: "text.badge.plus") {
            withAnimation(Motion.standard) { _ = model.expandedParents.insert(task.id) }
        }
        Divider()
        if task.status == .today {
            Button("В стек", systemImage: "arrow.uturn.backward") { model.perform(.toStack, on: task) }
        } else {
            Button("В сегодня", systemImage: "sun.max") { model.perform(.toToday, on: task) }
        }
        Button("Выполнить", systemImage: "checkmark.circle") { model.perform(.complete, on: task) }
        Divider()
        // Те же переносы, что и перетаскиванием, — для клавиатуры и VoiceOver.
        NestMenu(task: task, title: "Сделать подзадачей")
        if model.settings.projectsEnabled {
            ProjectMoveMenu(task: task)
        }
        Divider()
        Button("Удалить…", systemImage: "trash", role: .destructive) { model.perform(.delete, on: task) }
    }

    // MARK: - Перетаскивание

    private var isNestTarget: Bool { model.boardDrag.target == .nest(parentId: task.id) }

    private var subtaskSpace: String { "subtasks-\(task.id)" }

    private enum SubtaskSlot: Equatable { case none, before(String), end }

    private var subtaskSlot: SubtaskSlot {
        guard case .insert(.parent(let pid), let position) = model.boardDrag.target, pid == task.id else { return .none }
        let others = card.children.filter { $0.id != model.boardDrag.draggingTaskId }
        guard let position, position < others.count else { return .end }
        return .before(others[position].id)
    }

    private var subtaskSlotView: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Palette.accent.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Palette.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
            .frame(height: 24)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }

    // MARK: - Поведение

    private func toggleExpanded() {
        if isExpanded { model.expandedParents.remove(task.id) } else { model.expandedParents.insert(task.id) }
    }

    private func complete() {
        guard !completing else { return }
        // Родитель с открытыми подзадачами сначала спрашивает — галочку не ставим заранее.
        if !TaskTree.openChildren(of: task.id, in: model.store.tasks).isEmpty {
            model.perform(.complete, on: task)
            return
        }
        withAnimation(Motion.adaptive(Motion.bouncy, reduceMotion: reduceMotion)) { completing = true }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 320))
            model.perform(.complete, on: task)
        }
    }

    private var borderColor: Color {
        if task.isDeferred && task.status == .stack { return Palette.deferPurple.opacity(0.8) }
        if task.deadline == today { return Palette.warning }
        return hovering ? Palette.borderDefault : Palette.borderSubtle
    }

    /// На доске рядом бывает чип статуса «Сегодня», поэтому срок на сегодня подписан явно.
    static func deadlineText(_ task: TaskItem, deadline: Day, today: Day) -> String {
        if deadline == today && (task.deadlineStart == nil || task.deadlineStart == deadline) { return "Дедлайн сегодня" }
        return RuFormat.deadlineChip(start: task.deadlineStart, end: deadline, today: today)
    }

    static func deadlineColors(_ deadline: Day, today: Day) -> (fg: Color, bg: Color) {
        if deadline < today { return (Palette.error, Palette.errorSoft) }
        if deadline == today { return (Palette.onWarning, Palette.warningSoft) }
        return (Palette.accentInk, Palette.accentSoft)
    }
}

/// Строка подзадачи внутри карточки родителя.
struct SubtaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let timeLabel: String?
    let today: Day
    @State private var hovering = false

    private var isDone: Bool { task.status == .archive }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CompletionCircle(isDone: isDone, size: 14) {
                if isDone { model.reopen(task) } else { model.perform(.complete, on: task) }
            }
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .strikethrough(isDone, color: Palette.textTertiary)
                    .foregroundStyle(isDone ? Palette.textTertiary : Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isDone {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        if task.status == .today {
                            Chip(text: "Сегодня", symbol: nil, foreground: Palette.onWarning, background: Palette.warningSoft)
                        }
                        if let deadline = task.deadline {
                            let colors = BoardCard.deadlineColors(deadline, today: today)
                            Chip(text: BoardCard.deadlineText(task, deadline: deadline, today: today),
                                 symbol: nil, foreground: colors.fg, background: colors.bg)
                        }
                        if let timeLabel {
                            Chip(text: timeLabel, symbol: nil, foreground: Palette.textTertiary, background: Palette.surfaceAlt)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 5)
        .background(hovering ? Palette.surfaceAlt : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.presentEdit(task) }
        .animation(Motion.snappy, value: hovering)
        .contextMenu {
            Button("Редактировать…", systemImage: "pencil") { model.presentEdit(task) }
            if !isDone {
                Divider()
                if task.status == .today {
                    Button("В стек", systemImage: "arrow.uturn.backward") { model.perform(.toStack, on: task) }
                } else {
                    Button("В сегодня", systemImage: "sun.max") { model.perform(.toToday, on: task) }
                }
                Button("Выполнить", systemImage: "checkmark.circle") { model.perform(.complete, on: task) }
            } else {
                Button("Вернуть в работу", systemImage: "arrow.uturn.backward.circle") { model.reopen(task) }
            }
            Divider()
            Button("Сделать отдельной задачей", systemImage: "arrow.up.right.square") { model.makeStandalone(task) }
            NestMenu(task: task, title: "Перенести в задачу")
            Divider()
            Button("Удалить…", systemImage: "trash", role: .destructive) { model.perform(.delete, on: task) }
        }
    }
}

/// Подменю «Сделать подзадачей»: задачи той же колонки, куда вложение допустимо.
private struct NestMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let title: String

    var body: some View {
        let candidates = model.store.nestCandidates(for: task.id)
        // В контекстном меню .disabled у Menu не действует — пустое подменю выглядело бы рабочим.
        if candidates.isEmpty {
            Button(title, systemImage: "text.badge.plus") {}
                .disabled(true)
        } else {
            Menu(title, systemImage: "text.badge.plus") {
                ForEach(candidates) { parent in
                    Button(parent.title) { model.drop(taskId: task.id, on: .nest(parentId: parent.id)) }
                }
            }
        }
    }
}

/// Подменю «Переместить в проект»: то же, что бросок на проект в сайдбаре.
private struct ProjectMoveMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Menu("Переместить в проект", systemImage: "folder") {
            Button("Без проекта") { model.moveToProject(taskId: task.id, projectId: nil) }
                .disabled(task.projectId == nil)
            Divider()
            ForEach(model.store.categories(.project)) { project in
                Button(project.name) { model.moveToProject(taskId: task.id, projectId: project.id) }
                    .disabled(task.projectId == project.id)
            }
        }
    }
}

/// Кружок выполнения, как в Напоминаниях: при наведении — подсказка галочкой, по клику — заливка.
struct CompletionCircle: View {
    var isDone: Bool
    var size: CGFloat = 17
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? Palette.success : (hovering ? Palette.accent : Palette.borderDefault), lineWidth: 1.5)
                if isDone {
                    Circle().fill(Palette.success)
                        .overlay(Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white))
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else if hovering {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(Palette.accent.opacity(0.7))
                        .transition(.opacity)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.85))
        .onHover { hovering = $0 }
        .animation(Motion.bouncy, value: isDone)
        .animation(Motion.snappy, value: hovering)
        .help(isDone ? "Вернуть в работу" : "Выполнить")
    }
}

/// Бейдж балла приоритета.
struct ScoreBadge: View {
    let score: Double

    var body: some View {
        Text(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), score))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.scoreText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Palette.scoreBackground, in: Capsule())
            .contentTransition(.numericText(value: score))
            .help("Приоритет задачи")
    }
}
