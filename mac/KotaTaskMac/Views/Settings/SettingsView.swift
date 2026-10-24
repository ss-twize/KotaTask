import SwiftUI

/// Окно «Настройки» (⌘,): дублирует онбординг и добавляет алгоритм, контакты и данные.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("Основные", systemImage: "gearshape") }
            FeaturesSettingsTab()
                .tabItem { Label("Функции", systemImage: "switch.2") }
            CreationSettingsTab()
                .tabItem { Label("Создание задач", systemImage: "square.and.pencil") }
            AlgorithmSettingsTab()
                .tabItem { Label("Алгоритм", systemImage: "wand.and.stars") }
            AboutSettingsTab()
                .tabItem { Label("О приложении", systemImage: "info.circle") }
        }
        .frame(width: 600)
        .tint(Palette.accent)
    }
}

private struct GeneralSettingsTab: View {
    var body: some View {
        Form {
            Section("Оформление") {
                ThemePicker()
            }
            Section("Календарь") {
                CalendarModeChoices()
            }
            Section("Уведомления") {
                NotificationSettingsRows()
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }
}

private struct FeaturesSettingsTab: View {
    var body: some View {
        Form {
            Section {
                FeatureToggles()
            } header: {
                Text("Включённые возможности")
            }
            Section {
                FieldVisibilityToggles()
            } header: {
                Text("Видимые поля задачи")
            }
        }
        .formStyle(.grouped)
        .frame(height: 620)
    }
}

private struct CreationSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                AssistanceChoices()
            } header: {
                Text("Уровень помощи")
            } footer: {
                Text("Сколько полей обязательно при создании задачи.")
                    .foregroundStyle(Palette.textTertiary)
            }
            Section {
                RequiredFieldsEditor()
                    .disabled(model.settings.assistanceLevel != .custom)
                    .opacity(model.settings.assistanceLevel == .custom ? 1 : 0.45)
            } header: {
                Text("Обязательные поля уровня «Свой»")
            } footer: {
                Text(model.settings.assistanceLevel == .custom
                     ? "Скрытые в форме поля недоступны."
                     : "Выберите уровень «Свой», чтобы настроить поля вручную.")
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .animation(Motion.standard, value: model.settings.assistanceLevel)
    }
}

private struct AlgorithmSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var draft = CoefficientDraft.defaults
    @State private var loaded = false
    @State private var savedFlash = false

    var body: some View {
        let stored = CoefficientDraft(settings: model.settings)
        Form {
            Section {
                CoefficientSliders(draft: $draft)
            } header: {
                Text("Алгоритм приоритета")
            } footer: {
                if !model.settings.smartSort {
                    Text("Умная сортировка выключена — веса применятся, когда вы её включите.")
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Section("Загруженность") {
                LoadSliders(draft: $draft)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if savedFlash {
                    Label("Настройки сохранены", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if draft != stored {
                    Text("Есть несохранённые изменения")
                        .foregroundStyle(Palette.textTertiary)
                        .transition(.opacity)
                }
                Spacer()
                Button("По умолчанию") {
                    withAnimation(Motion.standard) { draft = .defaults }
                }
                Button("Сохранить") {
                    draft.apply(to: model.settings)
                    model.rescheduleNotifications()
                    withAnimation(Motion.bouncy) { savedFlash = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(Motion.standard) { savedFlash = false }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft == stored)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(height: 640)
        .onAppear {
            if !loaded {
                draft = stored
                loaded = true
            }
            // Контроль нагрузки переключается и на вкладке «Функции» — черновик не должен его откатить.
            draft.overloadEnabled = model.settings.overloadControl
        }
        .onChange(of: model.settings.overloadControl) { _, enabled in draft.overloadEnabled = enabled }
    }
}

private struct AboutSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var confirmOnboarding = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("KotaTask")
                            .font(.system(size: 20, weight: .bold))
                        Text("Свобода. Контроль. Свежесть.")
                            .foregroundStyle(Palette.textTertiary)
                        Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") для macOS")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.textHint)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Контакты") {
                LabeledContent("Почта") {
                    Button(AppModel.supportEmail) { model.openURL("mailto:\(AppModel.supportEmail)") }
                        .buttonStyle(.link)
                }
                LabeledContent("Telegram") {
                    Button("Открыть канал") { model.openURL(AppModel.telegramURL) }
                        .buttonStyle(.link)
                }
                LabeledContent("Предложить изменения") {
                    Button("Написать в Telegram") { model.openURL(AppModel.suggestURL) }
                        .buttonStyle(.link)
                }
                Button {
                    model.openURL(AppModel.donateURL)
                } label: {
                    Label("Поддержать проект", systemImage: "heart.fill")
                }
                .tint(Palette.carnation)
            }
            Section {
                LabeledContent("Файл данных") {
                    Button("Показать в Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.dataFileURL ?? Persistence.standard().fileURL])
                    }
                }
                LabeledContent("Начальная настройка") {
                    Button("Пройти заново…") { confirmOnboarding = true }
                }
            } header: {
                Text("Данные")
            } footer: {
                Text("Задачи хранятся только на этом Mac. Каждый день сохраняется копия — последние 7 лежат в папке Backups рядом с файлом.")
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .confirmationDialog("Пройти начальную настройку заново?", isPresented: $confirmOnboarding, titleVisibility: .visible) {
            Button("Начать") { model.settings.onboardingDone = false }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Задачи останутся на месте — изменятся только настройки, которые вы выберете.")
        }
    }
}
