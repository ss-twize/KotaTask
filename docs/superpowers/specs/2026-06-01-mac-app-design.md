# KotaTask macOS — Дизайн-документ

**Дата:** 2026-06-01  
**Статус:** Заменён планом [`2026-10-22-kotatask-mac-port.md`](../plans/2026-10-22-kotatask-mac-port.md) — эта спека описывала другую модель данных, не копию Android-версии.  

---

## Контекст

KotaTask — нативный Android task-менеджер с алгоритмическим приоритетом. Цель этого документа — описать Mac-версию приложения, создаваемую как отдельный проект в папке `mac/` рядом с `android/`. Android-код не затрагивается.

---

## Ограничения и решения

| Вопрос | Решение |
|--------|---------|
| Кто будет использовать | Только автор, личный инструмент |
| App Store | Нет |
| Синхронизация с Android | Нет, независимая база данных |
| Технология | SwiftUI + SwiftData |
| Минимальная macOS | 14 (Sonoma) |
| Дизайн | Нативный macOS: sidebar + список + панель деталей |
| Функциональность | Полный порт всех экранов и фич Android-версии |

---

## Структура проекта

Новая папка `mac/` создаётся в корне репозитория:

```
KotaTask/
  android/                    ← не трогать
  mac/
    KotaTaskMac.xcodeproj
    KotaTaskMac/
      App/
        KotaTaskMacApp.swift  ← точка входа, ModelContainer
      Models/
        Task.swift            ← @Model
        Category.swift        ← @Model
        AppSettings.swift     ← @Model
        Enums.swift           ← TaskStatus, CategoryKind
      ViewModels/
        TodayViewModel.swift
        StackViewModel.swift
        CalendarViewModel.swift
        FoldersViewModel.swift
        ArchiveViewModel.swift
        SettingsViewModel.swift
        AddTaskViewModel.swift
      Views/
        ContentView.swift     ← NavigationSplitView (sidebar)
        Today/
        Stack/
        Calendar/
        Folders/
        Archive/
        Settings/
        Onboarding/
        AddTask/
      Algorithm/
        PriorityCalculator.swift
      Notifications/
        NotificationManager.swift
  docs/
  kotatask-wiki/
```

---

## Архитектура

**Паттерн:** MVVM — как в Android-версии.

- **Model** — SwiftData `@Model` классы, персистентность автоматическая
- **ViewModel** — `@Observable` классы, бизнес-логика и запросы к SwiftData
- **View** — чистый SwiftUI, без логики

**Контейнер данных** инициализируется один раз в `KotaTaskMacApp.swift`:

```swift
@main struct KotaTaskMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Task.self, Category.self, AppSettings.self])
    }
}
```

**Главная навигация** — `NavigationSplitView` с тремя колонками: sidebar → список → детали.

---

## Модели данных

### Task

```swift
@Model class Task {
    var id: UUID
    var title: String
    var note: String?
    var status: TaskStatus      // .todo / .inProgress / .done / .cancelled
    var priority: Double        // вычисляется алгоритмом, 0–100
    var urgency: Int            // 1–5
    var importance: Int         // 1–5
    var effort: Int             // 1–5
    var dueDate: Date?
    var endDate: Date?          // для режима диапазона
    var isDateRange: Bool
    var createdAt: Date
    var completedAt: Date?
    var isArchived: Bool
    var projectId: UUID?
    var locationId: UUID?
    var taskTypeId: UUID?
}
```

Поля `assignee` и legacy `parent` из Android-схемы **не переносятся** — они мёртвый код.

### Category

```swift
@Model class Category {
    var id: UUID
    var name: String
    var kind: CategoryKind      // .project / .location / .taskType
    var color: String?
}
```

### AppSettings

Единственный экземпляр, создаётся при первом запуске:

```swift
@Model class AppSettings {
    var weightUrgency: Double       // default: 0.35
    var weightImportance: Double    // default: 0.30
    var weightEffort: Double        // default: 0.20
    var weightDeadline: Double      // default: 0.15
    var dailyTaskLimit: Int         // default: 5
    var notificationsEnabled: Bool
    var notificationTime: Date
    var onboardingCompleted: Bool
}
```

---

## Алгоритм приоритета

Порт из `TaskViewModel.kt`, изолирован в `PriorityCalculator.swift`:

```swift
struct PriorityCalculator {
    static func calculate(task: Task, settings: AppSettings) -> Double {
        let urgencyScore    = Double(task.urgency) / 5.0
        let importanceScore = Double(task.importance) / 5.0
        let effortScore     = 1.0 - (Double(task.effort) / 5.0)
        let deadlineScore   = deadlineFactor(dueDate: task.dueDate)

        let score = urgencyScore    * settings.weightUrgency
                  + importanceScore * settings.weightImportance
                  + effortScore     * settings.weightEffort
                  + deadlineScore   * settings.weightDeadline

        return (score * 100).rounded()
    }

    private static func deadlineFactor(dueDate: Date?) -> Double {
        guard let due = dueDate else { return 0.0 }
        let days = Calendar.current.dateComponents([.day], from: .now, to: due).day ?? 0
        switch days {
        case ..<0:   return 1.0
        case 0...1:  return 0.9
        case 2...3:  return 0.7
        case 4...7:  return 0.5
        default:     return 0.2
        }
    }
}
```

Пересчёт вызывается в ViewModel при:
- Сохранении/редактировании задачи
- Изменении весов в настройках (пересчитываются все задачи)

---

## Навигация и экраны

**Структура окна:** `NavigationSplitView` — три колонки.

### Sidebar (левая колонка)

| Пункт | Иконка | Описание |
|-------|--------|----------|
| Сегодня | `star.fill` | Топ задач по приоритету, бейдж с количеством |
| Стек | `list.bullet` | Все активные задачи |
| Календарь | `calendar` | Задачи по датам, режимы точка/диапазон |
| Папки | `folder` | 3 оси категоризации |
| Архив | `archivebox` | Завершённые и отменённые |
| Настройки | `gearshape` | Внизу sidebar |

### Центральная колонка — список задач

- Toolbar с заголовком экрана и кнопкой «+ Задача»
- При `TodayView` — предупреждение об overload если задач > лимита
- Каждая строка: чекбокс → заголовок → категория → дата → **число приоритета** (цвет: синий ≥70, зелёный 40–69, оранжевый <40)

### Правая колонка — детали задачи

- Показывается при выборе задачи в списке
- Заголовок, заметка, разбивка факторов приоритета (слайдеры urgency/importance/effort, дата)
- Кнопки: Редактировать, Выполнено, В архив

### Добавление задачи

Sheet (модальный лист) поверх основного окна. Поля: название, заметка, urgency (stepper 1–5), importance (stepper 1–5), effort (stepper 1–5), дата (DatePicker, переключатель точка/диапазон), категории (три пикера).

---

## Контроль перегрузки (Overload)

`TodayViewModel` показывает только топ-N задач по приоритету, где N = `AppSettings.dailyTaskLimit`. Если активных задач больше N — показывается предупреждение с количеством скрытых задач.

---

## Уведомления

`NotificationManager.swift` использует `UNUserNotificationCenter`:

- Разрешение запрашивается один раз при первом запуске
- Ежедневное уведомление в `notificationTime` из настроек
- Текст: «У тебя [N] задач на сегодня»
- При изменении времени уведомления в настройках — старое удаляется, новое планируется
- При старте приложения — уведомление перепланируется (на случай перезагрузки Mac)

---

## Онбординг

Показывается при первом запуске (`AppSettings.onboardingCompleted == false`). Отдельный `OnboardingView` поверх основного окна.

| Шаг | Содержание |
|-----|-----------|
| 1 | Приветствие — что такое KotaTask |
| 2 | Как работает алгоритм приоритета |
| 3 | Срочность и важность — в чём разница |
| 4 | Дедлайн-фактор |
| 5 | Дневной лимит задач |
| 6 | Настройка уведомлений |
| 7 | Готово — кнопка «Создать первую задачу» |

По завершении: `onboardingCompleted = true`, онбординг больше не показывается.

---

## Что НЕ входит в scope

- Синхронизация с Android-версией
- Облачное хранилище
- Несколько пользователей
- App Store / подписание
- Виджеты macOS
- Импорт/экспорт данных
