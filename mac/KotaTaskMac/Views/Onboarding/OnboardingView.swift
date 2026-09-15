import SwiftUI

struct OnboardingView: View {
    let settings: AppSettings
    @State private var currentStep = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "star.circle.fill",
            title: "Добро пожаловать в KotaTask",
            description: "Умный менеджер задач, который сам расставляет приоритеты на основе алгоритма."
        ),
        OnboardingStep(
            icon: "function",
            title: "Алгоритм приоритета",
            description: "Каждой задаче присваивается балл от 0 до 100 на основе четырёх факторов: срочность, важность, усилия и дедлайн."
        ),
        OnboardingStep(
            icon: "flame.fill",
            title: "Срочность и важность",
            description: "Срочность — насколько быстро нужно сделать. Важность — насколько значима задача для твоих целей. Оба параметра от 1 до 5."
        ),
        OnboardingStep(
            icon: "calendar.badge.exclamationmark",
            title: "Дедлайн-фактор",
            description: "Задачи с близким дедлайном автоматически получают более высокий приоритет. Просроченные задачи получают максимальный дедлайн-балл."
        ),
        OnboardingStep(
            icon: "list.number",
            title: "Дневной лимит задач",
            description: "В разделе «Сегодня» показываются только топ-N задач по приоритету. Остальные ждут в Стеке. Лимит можно изменить в Настройках."
        ),
        OnboardingStep(
            icon: "bell.fill",
            title: "Ежедневные уведомления",
            description: "KotaTask может напоминать тебе утром проверить задачи. Включить и настроить время можно в Настройках."
        ),
        OnboardingStep(
            icon: "checkmark.circle.fill",
            title: "Всё готово!",
            description: "Создай первую задачу — нажми + в верхнем правом углу. Удачи!"
        )
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            let step = steps[currentStep]

            Image(systemName: step.icon)
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                Text(step.description)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            HStack {
                if currentStep > 0 {
                    Button("Назад") { currentStep -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if currentStep < steps.count - 1 {
                    Button("Далее") { currentStep += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Начать работу") {
                        settings.onboardingCompleted = true
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 40)
        }
        .frame(width: 600, height: 480)
        .padding(.bottom, 32)
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
}
