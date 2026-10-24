import SwiftUI

/// Шаги онбординга. Коэффициенты пропускаются без умной сортировки, поля задачи — без уровня
/// «Свой», режим календаря — без календаря.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, system, features, coefficients, calendar, assistance, fields

    var id: Int { rawValue }

    @MainActor
    func isVisible(_ settings: AppSettings) -> Bool {
        switch self {
        case .coefficients: settings.smartSort
        case .calendar: settings.calendarEnabled
        case .fields: settings.assistanceLevel == .custom
        default: true
        }
    }

    var title: String {
        switch self {
        case .welcome: "Добро пожаловать в KotaTask"
        case .system: "Системные настройки"
        case .features: "Возможности"
        case .coefficients: "Умная сортировка"
        case .calendar: "Режим календаря"
        case .assistance: "Уровень помощи"
        case .fields: "Поля задачи"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "Гибкий планировщик — ваши правила, ваш ритм"
        case .system: "Тема и уведомления"
        case .features: "Выберите функции, которые вам нужны"
        case .coefficients: "Настройте веса факторов приоритизации"
        case .calendar: "Как отображать задачи с диапазоном"
        case .assistance: "Сколько полей обязательно при создании задачи"
        case .fields: "Какие поля показывать и какие обязательны"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "hand.wave"
        case .system: "paintbrush"
        case .features: "square.grid.2x2"
        case .coefficients: "wand.and.stars"
        case .calendar: "calendar"
        case .assistance: "lifepreserver"
        case .fields: "list.bullet.rectangle"
        }
    }
}

/// Первичная настройка — порт `OnboardingActivity`. Карточка из «жидкого стекла»
/// поверх мягкого фирменного градиента; шаги сменяются сдвигом в сторону перехода.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .welcome
    @State private var forward = true
    @State private var coefficients = CoefficientDraft.defaults
    @State private var coefficientsLoaded = false

    private var visibleSteps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0.isVisible(model.settings) }
    }

    var body: some View {
        let steps = visibleSteps
        let index = steps.firstIndex(of: step) ?? 0

        ZStack {
            background
            VStack(spacing: 0) {
                header(index: index, total: steps.count)
                ZStack {
                    content(for: step)
                        .id(step)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                footer(index: index, steps: steps)
            }
            .frame(maxWidth: 640, maxHeight: 680)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 30, y: 14)
            .padding(32)
        }
        .onAppear {
            if !coefficientsLoaded {
                coefficients = CoefficientDraft(settings: model.settings)
                coefficientsLoaded = true
            }
        }
    }

    // MARK: - Оформление

    private var background: some View {
        ZStack {
            Palette.canvas
            RadialGradient(colors: [Palette.jordyBlue.opacity(0.55), .clear], center: .topLeading, startRadius: 40, endRadius: 620)
            RadialGradient(colors: [Palette.sulu.opacity(0.28), .clear], center: .bottomTrailing, startRadius: 40, endRadius: 560)
            RadialGradient(colors: [Palette.parisDaisy.opacity(0.22), .clear], center: .topTrailing, startRadius: 20, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    private func header(index: Int, total: Int) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                Text("Шаг \(index + 1) из \(total)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .contentTransition(.numericText(value: Double(index)))
                Spacer()
            }
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Palette.accent : Palette.borderDefault.opacity(0.6))
                        .frame(height: 4)
                        .frame(maxWidth: i == index ? .infinity : 40)
                }
            }
            .animation(Motion.standard, value: index)
            .animation(Motion.standard, value: total)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private func footer(index: Int, steps: [OnboardingStep]) -> some View {
        HStack {
            if index > 0 {
                Button("Назад") { go(to: steps[index - 1], forward: false) }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .transition(.opacity)
            }
            Spacer()
            if index < steps.count - 1 {
                Button("Далее") { advance(from: index, steps: steps) }
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Готово") { finish() }
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .animation(Motion.snappy, value: index)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Шаги

    @ViewBuilder
    private func content(for step: OnboardingStep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: step.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .symbolEffect(.bounce, value: step)
                    Text(step.title)
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.5)
                    Text(step.subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.textTertiary)
                }
                stepBody(step)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }

    @ViewBuilder
    private func stepBody(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 16) {
                Text("Включите только нужные функции и настройте всё под себя. Никаких лишних экранов — только то, что помогает именно вам. Все параметры можно изменить позже в разделе «Настройки».")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                highlight("wand.and.stars", "Алгоритм приоритета", "Сам считает, что важнее сделать прямо сейчас — по дедлайну, важности, длительности и возрасту задачи.")
                highlight("gauge.with.dots.needle.67percent", "Нагрузка дня", "Показывает, сколько минут уже запланировано, и предупреждает о перегрузе.")
                highlight("calendar", "Календарь", "Каждый день — «пончик»: секторы задач, их цвет и длительность.")
            }
        case .system:
            card {
                Text("Тема оформления").font(.system(size: 13, weight: .semibold))
                ThemePicker().labelsHidden()
            }
            card { NotificationSettingsRows() }
        case .features:
            card { FeatureToggles(includeOverload: false) }
        case .coefficients:
            card { CoefficientSliders(draft: $coefficients) }
            card {
                Text("Нагрузка дня").font(.system(size: 13, weight: .semibold))
                LoadSliders(draft: $coefficients)
            }
        case .calendar:
            CalendarModeChoices()
        case .assistance:
            AssistanceChoices()
        case .fields:
            card { FieldVisibilityToggles() }
            card {
                Text("Обязательные поля").font(.system(size: 13, weight: .semibold))
                RequiredFieldsEditor()
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.borderSubtle))
    }

    private func highlight(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 36, height: 36)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Навигация

    private func advance(from index: Int, steps: [OnboardingStep]) {
        if step == .coefficients { coefficients.apply(to: model.settings) }
        // Состав шагов мог измениться на текущем шаге — пересчитываем следующий.
        let fresh = visibleSteps
        let currentIndex = fresh.firstIndex(of: step) ?? index
        guard currentIndex + 1 < fresh.count else { finish(); return }
        go(to: fresh[currentIndex + 1], forward: true)
    }

    /// Направление ставится отдельным обновлением: уходящий шаг берёт переход из своего
    /// последнего состояния.
    private func go(to target: OnboardingStep, forward isForward: Bool) {
        forward = isForward
        Task { @MainActor in
            withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { step = target }
        }
    }

    private func finish() {
        if model.settings.smartSort { coefficients.apply(to: model.settings) }
        model.normalizeSelection()
        model.settings.onboardingDone = true
        if model.settings.notificationsEnabled {
            Task {
                await model.notifications.requestAuthorization()
                model.rescheduleNotifications()
            }
        }
    }
}
