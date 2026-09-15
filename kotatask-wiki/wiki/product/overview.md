# Обзор продукта KotaTask

**Дата документа:** 2026-05-28
**Версия кодовой базы:** versionName `1.0`, versionCode `1`
**Платформа:** Android (нативное, Kotlin), `minSdk 26` (Android 8.0+), `targetSdk 34`

---

## Что делает приложение

KotaTask — нативный Android task-менеджер с **алгоритмическим приоритезатором задач**.
Ядро ценности: приложение не просто хранит список дел, а **считает скор каждой задачи**
по 4 факторам (дедлайн, важность, длительность, возраст) и сортирует список так,
чтобы наверху всегда оказывалась задача, которую разумнее всего сделать прямо сейчас.

Пользователь сам задаёт **веса** этих факторов через слайдеры в [[onboarding]] и
в [[настройках]] — это превращает приложение из "очередной todo-листа" в
персонализируемый движок приоритизации.

---

## Ключевые фичи, реализованные в коде

### 1. Алгоритмический приоритет
Файл: [`util/PriorityCalculator.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/util/PriorityCalculator.kt)

- Считает скор по формуле: `score = w_deadline · dl + w_importance · imp + w_duration · dur + w_age · age`
- Веса по умолчанию: `0.45 / 0.35 / 0.10 / 0.10` (сумма ≈ 1, не нормализуется жёстко).
- `deadlineScore` шкалирует пять зон: просрочено → сегодня → ≤3 дней → ≤7 → дальше.
- `ageScore` нелинейно растёт первые 5 дней, потом стабилизируется на 1.0 —
  чтобы старые задачи "всплывали" на поверхность.
- При перегрузке дня (`duration` суммарно > порога) включается **бонус короткой задачи**:
  легче выполнить мелкую задачу, чем застрять в крупной.

Подробнее: [[decisions/ADR-002-weighted-priority]].

### 2. Четыре статуса задачи
- **Стек** — общий бэклог.
- **Сегодня** — план дня (показывает суммарную нагрузку в минутах с цветовой индикацией).
- **Архив** — выполненные.
- (внутренний) **deadlineStart…deadline** — диапазон, в котором задача "видна" в календаре.

Переходы: `Стек ↔ Сегодня → Архив`. Удаление возможно из любого статуса.

### 3. Три независимые оси категоризации
Файлы: [`data/Project.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/data/Project.kt),
[`data/Location.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/data/Location.kt),
[`data/TaskType.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/data/TaskType.kt)

Задача может одновременно относиться:
- **Проект** (`Сайт для клиента`, `Личный бренд`) — крупная смысловая группа.
- **Локация** (`Дом`, `Зал`, `Компьютер`) — где выполнить.
- **Тип задачи** (`Звонок`, `Создание`, `Тренировка`) — характер действия.

Каждая ось хранится в отдельной Room-таблице, не enum — пользователь создаёт свои.
В UI фильтры комбинируются через `applyCategoryFilters()` с поддержкой sentinel-значений
`FILTER_ANY` ("все") и `FILTER_NONE` ("без X"). См. [[decisions/ADR-006-three-axis-categorization]].

### 4. Календарь с режимом "точка" / "диапазон"
Файл: [`ui/CalendarFragment.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/ui/CalendarFragment.kt)

- Кастомная сетка месяца (`GridLayoutManager(7)` + `MonthCalendarAdapter`).
- Ячейки — donut-кольца, показывающие нагрузку на день (история коммитов: `0d59ca3 feat: redesign calendar cells as thick donut-ring indicators`).
- **Режим "диапазон"**: задача "видна" каждый день из `[deadlineStart, deadline]`.
  Если `deadlineStart` пуст — берётся дата создания задачи.
- **Режим "точка"**: задача видна только в день дедлайна (legacy-поведение).
- Переключение мгновенное в настройках, без перезапуска.

### 5. Ежедневные утренние уведомления
Файлы: [`util/NotificationWorker.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/util/NotificationWorker.kt),
[`util/BootReceiver.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/util/BootReceiver.kt)

- В заданное время выводит summary всех задач со статусом "Сегодня" (первые 5 + "ещё N").
- Реализовано через **self-rescheduling `OneTimeWorkRequest`**, а не `PeriodicWorkRequest`,
  чтобы точно попадать в `HH:MM` (см. [[decisions/ADR-004-self-rescheduling-worker]]).
- `BootReceiver` перепланирует после ребута.
- На Android 13+ запрашивает `POST_NOTIFICATIONS` runtime-разрешение.

### 6. Онбординг с feature flags
Файл: [`ui/OnboardingActivity.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/ui/OnboardingActivity.kt)

7-шаговый мастер при первом запуске. Пользователь решает:
- Какие вкладки нужны (`split_today`, `calendar`, `projects`, `locations`, `task_types`).
- Нужен ли smart-sort вообще (если выключен — шаг настройки коэффициентов скипается).
- Уровень помощи при создании задачи: `minimal / standard / advanced / custom`
  (определяет какие поля обязательны).
- Какие поля показывать в форме (`duration`, `purpose`, `project`).
- Тему (light/dark/system), время уведомлений, режим календаря.

Все настройки дублируются в [[ui/SettingsFragment]] — онбординг не запирает выбор.

### 7. Контроль дневной нагрузки (overload)
В TodayFragment и StackFragment отображается **суммарная длительность задач "на сегодня"**
с цветовым светофором:
- зелёный, если меньше половины порога,
- жёлтый — между половиной и порогом,
- красный — выше порога.

Порог настраивается (120…960 минут, шаг 10). При перегрузке `PriorityCalculator` повышает скор коротких задач — это `loadDurationBoost`.

### 8. Архив с множественным выделением
Файл: [`ui/ArchiveFragment.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/ui/ArchiveFragment.kt)

- Режим выделения с чекбоксами, массовое удаление, "удалить всё".
- Карточки в архиве показывают timestamp выполнения.

### 9. UX-детали
- **Drag-free dual-mode AddTaskFragment**: один и тот же фрагмент работает в режимах
  "создание" и "редактирование" через factory-методы `forEdit(id)` / `forCategory(kind, id)`.
- **Material 3 BottomNavigation** с динамической видимостью вкладок (feature flags).
- **Поиск по задачам** в Стеке (по `title` и `purpose`, без учёта регистра).
- **Quick-add** новой категории прямо из формы создания задачи.
- **Русская локализация плюрализации** ("1 задача / 2 задачи / 5 задач").

---

## Что приложение НЕ делает (отсутствует в коде)

- Нет синхронизации/облака — БД полностью локальная (Room, `mark_db`).
- Нет аккаунтов / шеринга задач.
- Нет вложений / файлов / голосовых заметок.
- Нет повторяющихся задач (recurring) — каждая задача создаётся вручную.
- Нет напоминаний на конкретную задачу — есть только общий утренний summary.
- Нет виджетов главного экрана / Quick Settings.
- Поле `assignee` существует в схеме, но удалено из UI (см. коммит `3c119bf fix: remove assignee field`).
- Поле `parent` (legacy free-text название проекта) сохраняется для обратной совместимости
  с миграцией v1→v2, но новые задачи его не заполняют — теперь `projectId`.

См. также: [[status/mvp-scope]].

---

## Целевой пользователь (вывод из кода)

- Человек, готовый настраивать (онбординг с 7 шагов, custom-уровень помощи, custom-веса).
- Локализация только русская (`Locale("ru")` зашит как `RU` константа в `CalendarFragment`,
  множественные числа русские, кнопки/строки русские).
- Один пользователь — один телефон. Нет multi-user или multi-device.

---

## Связанные документы
- [[tech/stack]] — стек и зависимости
- [[tech/architecture]] — модули, слои
- [[status/mvp-scope]] — что готово, что незакончено
- [[decisions/ADR-002-weighted-priority]] — почему такая формула приоритета
- [[decisions/ADR-006-three-axis-categorization]] — почему три оси категоризации
