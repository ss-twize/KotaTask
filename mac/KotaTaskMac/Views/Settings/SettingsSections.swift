import SwiftUI

// Секции настроек, общие для окна «Настройки» и онбординга — как в Android,
// где настройки дублируют все шаги онбординга.

// MARK: - Строка-переключатель

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Motion.snappy, value: isEnabled)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Тема

struct ThemePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Picker("Тема оформления", selection: $settings.theme) {
            ForEach(ThemeMode.allCases) { theme in
                Label(theme.title, systemImage: theme.symbol).tag(theme)
            }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Уведомления

struct NotificationSettingsRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        ToggleRow(
            title: "Ежедневное напоминание",
            subtitle: "Утром — список задач на сегодня",
            isOn: Binding(
                get: { settings.notificationsEnabled },
                set: { enabled in
                    settings.notificationsEnabled = enabled
                    if enabled {
                        Task {
                            await model.notifications.requestAuthorization()
                            model.rescheduleNotifications()
                        }
                    }
                }
            )
        )
        HStack {
            Text("Время напоминания")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            DatePicker("Время напоминания", selection: $settings.notificationTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.locale, RuFormat.locale)
        }
        .disabled(!settings.notificationsEnabled)
        .opacity(settings.notificationsEnabled ? 1 : 0.4)
        if settings.notificationsEnabled && model.notifications.authorization == .denied {
            HStack(spacing: 8) {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(Palette.error)
                Text("Уведомления запрещены в Системных настройках.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Button("Открыть") { model.notifications.openSystemSettings() }
                    .controlSize(.small)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Функции

struct FeatureToggles: View {
    @Environment(AppModel.self) private var model
    var includeOverload = true

    var body: some View {
        @Bindable var settings = model.settings
        ToggleRow(title: "Раздельные «Сегодня» и «Стек»", subtitle: "Если выключено — будет одна вкладка «Задачи»", isOn: $settings.splitToday)
        ToggleRow(title: "Календарь", subtitle: "Просмотр задач по дням", isOn: $settings.calendarEnabled)
        ToggleRow(title: "Проекты", subtitle: "Группировка задач по проектам", isOn: $settings.projectsEnabled)
        ToggleRow(title: "Локации", subtitle: "Фильтрация задач по месту выполнения", isOn: $settings.locationsEnabled)
        ToggleRow(title: "Типы задач", subtitle: "Дополнительная категоризация по виду задачи", isOn: $settings.taskTypesEnabled)
        ToggleRow(title: "Умная сортировка", subtitle: "Автоматический приоритет по дедлайну, важности и другим факторам", isOn: $settings.smartSort)
        ToggleRow(
            title: "Отложенное планирование",
            subtitle: "Кнопка «Отложить» в стеке: задача сама добавится в «Сегодня» в выбранный день. Требует разделения «Сегодня» и «Стек»",
            isOn: $settings.deferEnabledFlag,
            isEnabled: settings.splitToday
        )
        if includeOverload {
            ToggleRow(
                title: "Контроль нагрузки дня",
                subtitle: "Светофор нагрузки и приоритет коротких задач при перегруженном дне",
                isOn: $settings.overloadControl
            )
        }
    }
}

// MARK: - Поля формы

struct FieldVisibilityToggles: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        ToggleRow(title: "Длительность", subtitle: "Сколько минут уйдёт на задачу", isOn: $settings.showDurationField)
        ToggleRow(title: "Цель / обоснование", subtitle: "Почему задача важна", isOn: $settings.showPurposeField)
        ForEach(CategoryKind.allCases) { kind in
            ToggleRow(
                title: kind.singularTitle,
                subtitle: settings.isCategoryEnabled(kind) ? subtitle(kind) : "Включите «\(kind.pluralTitle)» в функциях",
                isOn: Binding(get: { settings.isCategoryFieldShown(kind) }, set: { settings.setCategoryFieldShown(kind, $0) }),
                isEnabled: settings.isCategoryEnabled(kind)
            )
        }
    }

    private func subtitle(_ kind: CategoryKind) -> String {
        switch kind {
        case .project: "К какому проекту относится"
        case .location: "Место выполнения задачи"
        case .taskType: "Вид выполняемой задачи"
        }
    }
}

// MARK: - Режим календаря

struct CalendarModeChoices: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(CalendarMode.allCases) { mode in
                ChoiceRow(
                    title: mode.title,
                    subtitle: mode.subtitle,
                    symbol: mode == .range ? "arrow.left.and.right" : "smallcircle.filled.circle",
                    isSelected: model.settings.calendarMode == mode
                ) {
                    model.settings.calendarMode = mode
                }
            }
        }
    }
}

// MARK: - Уровень помощи

struct AssistanceChoices: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AssistanceLevel.allCases) { level in
                ChoiceRow(
                    title: level.title,
                    subtitle: level.subtitle,
                    symbol: symbol(level),
                    isSelected: model.settings.assistanceLevel == level
                ) {
                    withAnimation(Motion.standard) { model.settings.assistanceLevel = level }
                }
            }
        }
    }

    private func symbol(_ level: AssistanceLevel) -> String {
        switch level {
        case .minimal: "1.circle"
        case .standard: "2.circle"
        case .advanced: "3.circle"
        case .custom: "slider.horizontal.3"
        }
    }
}

/// Обязательные поля уровня «Свой». Скрытые поля недоступны и принудительно сброшены.
struct RequiredFieldsEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        let config = settings.formConfig
        VStack(alignment: .leading, spacing: 6) {
            ForEach(RequirableField.allCases) { field in
                let available = config.isVisible(field)
                Toggle(isOn: Binding(
                    get: { available && settings.customRequired.contains(field) },
                    set: { on in
                        if on { settings.customRequired.insert(field) } else { settings.customRequired.remove(field) }
                    }
                )) {
                    Text(field.title)
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .disabled(!available)
                .opacity(available ? 1 : 0.38)
                .help(available ? "" : "Поле скрыто в форме — сделать его обязательным нельзя")
            }
        }
        .onAppear(perform: dropUnavailable)
        .onChange(of: config.visibleCategories) { _, _ in dropUnavailable() }
        .onChange(of: config.showDuration) { _, _ in dropUnavailable() }
        .onChange(of: config.showPurpose) { _, _ in dropUnavailable() }
    }

    private func dropUnavailable() {
        let config = model.settings.formConfig
        let filtered = model.settings.customRequired.filter(config.isVisible)
        if filtered != model.settings.customRequired { model.settings.customRequired = filtered }
    }
}

// MARK: - Коэффициенты

/// Черновик весов: слайдеры работают в целых процентах, как в Android, и применяются по кнопке.
struct CoefficientDraft: Equatable {
    var deadline: Double
    var importance: Double
    var duration: Double
    var age: Double
    var overloadEnabled: Bool
    var limit: Double
    var boost: Double

    @MainActor
    init(settings: AppSettings) {
        deadline = (settings.coefficients.deadline * 100).rounded()
        importance = (settings.coefficients.importance * 100).rounded()
        duration = (settings.coefficients.duration * 100).rounded()
        age = (settings.coefficients.age * 100).rounded()
        overloadEnabled = settings.overloadControl
        limit = Double(settings.overloadLimitMinutes)
        boost = (settings.loadDurationBoost * 100).rounded()
    }

    static let defaults = CoefficientDraft(
        deadline: Coefficients.defaults.deadline * 100,
        importance: Coefficients.defaults.importance * 100,
        duration: Coefficients.defaults.duration * 100,
        age: Coefficients.defaults.age * 100,
        overloadEnabled: true,
        limit: Double(DayLoad.defaultLimit),
        boost: DayLoad.defaultBoost * 100
    )

    private init(deadline: Double, importance: Double, duration: Double, age: Double, overloadEnabled: Bool, limit: Double, boost: Double) {
        self.deadline = deadline
        self.importance = importance
        self.duration = duration
        self.age = age
        self.overloadEnabled = overloadEnabled
        self.limit = limit
        self.boost = boost
    }

    mutating func resetWeights() {
        let d = Self.defaults
        deadline = d.deadline; importance = d.importance; duration = d.duration; age = d.age
    }

    mutating func resetLoad() {
        let d = Self.defaults
        overloadEnabled = d.overloadEnabled; limit = d.limit; boost = d.boost
    }

    var weightSum: Int { Int(deadline + importance + duration + age) }

    @MainActor
    func apply(to settings: AppSettings) {
        settings.coefficients = Coefficients(deadline: deadline / 100, importance: importance / 100, duration: duration / 100, age: age / 100)
        settings.overloadControl = overloadEnabled
        settings.overloadLimitMinutes = Int(limit)
        settings.loadDurationBoost = boost / 100
    }
}

struct CoefficientSliders: View {
    @Binding var draft: CoefficientDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            weight("Дедлайн", symbol: "calendar.badge.clock", value: $draft.deadline)
            weight("Важность", symbol: "flag", value: $draft.importance)
            weight("Длительность", symbol: "timer", value: $draft.duration)
            weight("Возраст задачи", symbol: "hourglass", value: $draft.age)
            HStack {
                Image(systemName: draft.weightSum == 0 ? "exclamationmark.triangle.fill" : "sum")
                    .foregroundStyle(draft.weightSum == 0 ? Palette.error : Palette.textTertiary)
                Text(draft.weightSum == 0 ? "Все веса равны нулю — сортировка станет случайной" : "Сумма весов: \(draft.weightSum)%")
                    .contentTransition(.numericText(value: Double(draft.weightSum)))
                Spacer()
                Button("Сбросить веса") { withAnimation(Motion.standard) { draft.resetWeights() } }
                    .controlSize(.small)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.textTertiary)
        }
    }

    private func weight(_ title: String, symbol: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.accentInk)
                    .contentTransition(.numericText(value: value.wrappedValue))
                    .animation(Motion.snappy, value: value.wrappedValue)
            }
            Slider(value: value, in: 0...100, step: 1)
        }
    }
}

struct LoadSliders: View {
    @Binding var draft: CoefficientDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToggleRow(
                title: "Коэффициент нагрузки",
                subtitle: "Повышает приоритет коротких задач при перегруженном дне",
                isOn: $draft.overloadEnabled
            )
            Group {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Лимит дня").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(Int(draft.limit)) мин")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.accentInk)
                            .contentTransition(.numericText(value: draft.limit))
                            .animation(Motion.snappy, value: draft.limit)
                    }
                    Slider(
                        value: $draft.limit,
                        in: Double(DayLoad.limitRange.lowerBound)...Double(DayLoad.limitRange.upperBound),
                        step: Double(DayLoad.limitStep)
                    )
                    Text("Порог перегрузки. После половины лимита короткие задачи получают буст.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Буст коротких задач").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("+\(Int(draft.boost))%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.accentInk)
                            .contentTransition(.numericText(value: draft.boost))
                            .animation(Motion.snappy, value: draft.boost)
                    }
                    Slider(value: $draft.boost, in: 0...100, step: 5)
                }
            }
            .disabled(!draft.overloadEnabled)
            .opacity(draft.overloadEnabled ? 1 : 0.4)
            HStack {
                Spacer()
                Button("Сбросить нагрузку") { withAnimation(Motion.standard) { draft.resetLoad() } }
                    .controlSize(.small)
            }
        }
        .animation(Motion.snappy, value: draft.overloadEnabled)
    }
}
