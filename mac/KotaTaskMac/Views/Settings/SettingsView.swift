import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context
    @Query private var tasks: [AppTask]

    private var settings: AppSettings {
        if let s = settingsList.first { return s }
        let s = AppSettings()
        context.insert(s)
        return s
    }

    @State private var showSavedBanner = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if showSavedBanner {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Настройки сохранены")
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)
                    .transition(.opacity)
                }

                weightsSection
                dailyLimitSection
                notificationsSection
            }
            .padding()
        }
        .navigationTitle("Настройки")
    }

    private var weightsSection: some View {
        GroupBox("Веса алгоритма приоритета") {
            VStack(spacing: 16) {
                Text("Сумма весов: \(String(format: "%.0f%%", (settings.weightUrgency + settings.weightImportance + settings.weightEffort + settings.weightDeadline) * 100))")
                    .font(.caption)
                    .foregroundColor(weightsValid ? .secondary : .red)

                weightSlider("Срочность",   value: Binding(
                    get: { settings.weightUrgency },
                    set: { settings.weightUrgency = $0; recalcAll() }
                ))
                weightSlider("Важность",    value: Binding(
                    get: { settings.weightImportance },
                    set: { settings.weightImportance = $0; recalcAll() }
                ))
                weightSlider("Усилия",      value: Binding(
                    get: { settings.weightEffort },
                    set: { settings.weightEffort = $0; recalcAll() }
                ))
                weightSlider("Дедлайн",     value: Binding(
                    get: { settings.weightDeadline },
                    set: { settings.weightDeadline = $0; recalcAll() }
                ))

                Button("Сбросить к стандартным") {
                    settings.weightUrgency = 0.35
                    settings.weightImportance = 0.30
                    settings.weightEffort = 0.20
                    settings.weightDeadline = 0.15
                    recalcAll()
                    showSaved()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private var dailyLimitSection: some View {
        GroupBox("Дневной лимит задач") {
            HStack {
                Text("Показывать в «Сегодня»")
                Spacer()
                Stepper("\(settings.dailyTaskLimit)", value: Binding(
                    get: { settings.dailyTaskLimit },
                    set: { settings.dailyTaskLimit = $0; showSaved() }
                ), in: 1...20)
            }
            .padding()
        }
    }

    private var notificationsSection: some View {
        GroupBox("Уведомления") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Включить ежедневное уведомление", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { v in
                        settings.notificationsEnabled = v
                        if v { NotificationManager.shared.requestPermission() }
                        NotificationManager.shared.reschedule(settings: settings)
                        showSaved()
                    }
                ))

                if settings.notificationsEnabled {
                    HStack {
                        Text("Время")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.notificationHour },
                            set: { settings.notificationHour = $0; NotificationManager.shared.reschedule(settings: settings); showSaved() }
                        )) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .frame(width: 60)
                        Text(":")
                        Picker("", selection: Binding(
                            get: { settings.notificationMinute },
                            set: { settings.notificationMinute = $0; NotificationManager.shared.reschedule(settings: settings); showSaved() }
                        )) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .frame(width: 60)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func weightSlider(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 100, alignment: .leading)
            Slider(value: value, in: 0.0...1.0, step: 0.05)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private var weightsValid: Bool {
        let sum = settings.weightUrgency + settings.weightImportance +
                  settings.weightEffort + settings.weightDeadline
        return abs(sum - 1.0) < 0.01
    }

    private func recalcAll() {
        let weights = PriorityWeights.from(settings: settings)
        for task in tasks {
            task.priority = PriorityCalculator.calculate(
                urgency: task.urgency, importance: task.importance,
                effort: task.effort, dueDate: task.dueDate, weights: weights
            )
        }
        showSaved()
    }

    private func showSaved() {
        withAnimation { showSavedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedBanner = false }
        }
    }
}
