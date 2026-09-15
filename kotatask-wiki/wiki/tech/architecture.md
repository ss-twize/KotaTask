# Архитектура KotaTask

**Дата документа:** 2026-05-28
**Корень модуля:** `KotaTask-main/android/app/src/main/java/com/mark/app/`

---

## Структура пакетов

```
com.mark.app/
├── KotaTaskApp.kt              ← Application: тема + все константы prefs
│
├── data/                       ← Слой данных (Room)
│   ├── AppDatabase.kt          ← @Database v3, миграции 1→2, 2→3
│   ├── Task.kt + TaskDao.kt
│   ├── Project.kt + ProjectDao.kt
│   ├── Location.kt + LocationDao.kt
│   └── TaskType.kt + TaskTypeDao.kt
│
├── repository/                 ← Слой репозиториев (suspend + Dispatchers.IO)
│   ├── TaskRepository.kt
│   ├── ProjectRepository.kt
│   ├── LocationRepository.kt
│   └── TaskTypeRepository.kt
│
├── viewmodel/
│   └── TaskViewModel.kt        ← Единственная ViewModel, шарится между всеми Fragment'ами
│                                  через activityViewModels()
│
├── adapter/                    ← RecyclerView адаптеры
│   ├── TaskAdapter.kt          ← Универсальный, режимы TabMode {TODAY, STACK, ARCHIVE, CALENDAR, MERGED}
│   ├── FolderAdapter.kt
│   └── CategoryRowAdapter.kt
│
├── ui/                         ← View-слой
│   ├── MainActivity.kt         ← BottomNav + FAB, host для Fragment'ов
│   ├── OnboardingActivity.kt   ← 7-шаговый мастер первого запуска
│   ├── TodayFragment.kt
│   ├── StackFragment.kt        ← + newMerged() для режима "merged"
│   ├── CalendarFragment.kt
│   ├── FoldersFragment.kt      ← Заменил ArchiveFragment в bottom-nav
│   ├── ArchiveFragment.kt      ← Теперь модальный, открывается из Settings
│   ├── SettingsFragment.kt
│   ├── AddTaskFragment.kt      ← Dual-mode: create / edit
│   ├── CategoryKind.kt         ← enum { PROJECT, LOCATION, TASK_TYPE }
│   ├── CategoryManagerFragment.kt
│   ├── CategoryTasksFragment.kt
│   ├── calendar/
│   │   ├── MonthCalendarAdapter.kt
│   │   └── CalendarCellView.kt   ← Кастомная View с donut-ring
│   └── dialog/
│       └── CategoryNameDialog.kt
│
└── util/
    ├── PriorityCalculator.kt   ← Чистая функция расчёта скора
    ├── NotificationWorker.kt   ← CoroutineWorker (WorkManager)
    └── BootReceiver.kt         ← scheduleDaily() после ребута
```

---

## Слоистая архитектура

```
┌────────────────────────────────────────────────────────────────┐
│  UI (Activity / Fragment / Adapter / Dialog / View)            │
│  ─ MainActivity, OnboardingActivity                            │
│  ─ TodayFragment, StackFragment, CalendarFragment,             │
│    FoldersFragment, ArchiveFragment, SettingsFragment,         │
│    AddTaskFragment, CategoryManagerFragment, CategoryTasks…    │
│  ─ TaskAdapter, FolderAdapter, MonthCalendarAdapter            │
└─────────────────────────────┬──────────────────────────────────┘
                              │ activityViewModels()
                              │ LiveData<…>.observe()
┌─────────────────────────────▼──────────────────────────────────┐
│  ViewModel (один на всю активность)                            │
│  ─ TaskViewModel : AndroidViewModel                            │
│     • держит 4 репозитория                                     │
│     • exposes: allTasks, allProjects, allLocations, allTypes   │
│     • exposes: errors LiveData (+ consumeError)                │
│     • методы сортировки / фильтрации                           │
│     • чтение/запись SharedPreferences (coeff_*, overload_*)    │
└─────────────────────────────┬──────────────────────────────────┘
                              │ repo.insert(...), repo.allTasks
┌─────────────────────────────▼──────────────────────────────────┐
│  Repository (suspend + withContext(Dispatchers.IO))            │
│  ─ TaskRepository, ProjectRepository,                          │
│    LocationRepository, TaskTypeRepository                      │
│  Тонкие обёртки: dao.method() в IO-контексте                   │
└─────────────────────────────┬──────────────────────────────────┘
                              │
┌─────────────────────────────▼──────────────────────────────────┐
│  Data (Room)                                                   │
│  ─ AppDatabase (singleton, @Volatile)                          │
│     entities = [Task, Project, Location, TaskType]             │
│     version = 3, migrations: 1→2, 2→3                          │
│  ─ TaskDao, ProjectDao, LocationDao, TaskTypeDao               │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│  Util (чистые модули, без UI зависимостей)                     │
│  ─ PriorityCalculator (чистые функции, без состояния)          │
│  ─ NotificationWorker (CoroutineWorker)                        │
│  ─ BootReceiver + scheduleDaily() + cancelDaily() + calculate… │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│  Persistence (sideband)                                        │
│  ─ SharedPreferences "mark_prefs": тема, feature flags,        │
│    коэффициенты, время уведомлений, режим календаря, уровень   │
│    помощи, кастомные required-поля.                            │
│    Доступ — напрямую из любого слоя через ctx.getSharedPrefs   │
└────────────────────────────────────────────────────────────────┘
```

---

## Модель данных (Room schema v3)

```
┌─────────────────┐       ┌──────────────────┐
│     tasks       │       │     projects     │
├─────────────────┤       ├──────────────────┤
│ id        TEXT PK│      │ id      TEXT PK  │
│ title      TEXT  │      │ name    TEXT     │
│ deadline   TEXT  │      │ color   TEXT?    │
│ deadlineStart    │      │ created INTEGER  │
│            TEXT  │      │ updated INTEGER  │
│ parent     TEXT  │←     └──────────────────┘
│ purpose    TEXT  │ │
│ duration   INT   │ │ legacy free-text
│ importance TEXT  │ │ ("Высокая"|"Средняя"|"Низкая")
│ status     TEXT  │ ↑ ("Стек"|"Сегодня"|"Архив")
│ assignee   TEXT  │   (поле есть, в UI вырезано)
│ created    LONG  │
│ completed  LONG  │
│ projectId  TEXT? │──── soft reference (без FK!) ────→ projects.id
│ locationId TEXT? │──── soft reference                → locations.id
│ taskTypeId TEXT? │──── soft reference                → task_types.id
└─────────────────┘

┌─────────────────┐       ┌──────────────────┐
│   locations     │       │   task_types     │
├─────────────────┤       ├──────────────────┤
│ id      TEXT PK │       │ id      TEXT PK  │
│ name    TEXT    │       │ name    TEXT     │
│ created INTEGER │       │ created INTEGER  │
│ updated INTEGER │       │ updated INTEGER  │
└─────────────────┘       └──────────────────┘
```

### Важные особенности схемы
1. **Все ID — UUID-строки**, генерируются через `UUID.randomUUID().toString()` в ViewModel.
   Не AUTOINCREMENT.
2. **Нет внешних ключей в Room**. `projectId`/`locationId`/`taskTypeId` — обычные
   nullable строки. Связь поддерживается на уровне ViewModel (`vm.allProjects.value?.find { … }`).
   Удаление проекта **не** очищает `projectId` у задач — это можно считать багом,
   см. [[status/mvp-scope]].
3. **`status` — строка с русскими литералами** ("Стек"/"Сегодня"/"Архив").
   Это закрепляет связку модели и UI-локализации. См. [[decisions/ADR-007-status-russian-literals]].
4. **`deadline` хранится как ISO-строка** (`yyyy-MM-dd`), не как timestamp.
   Сравнения идут через `LocalDate.parse(...)`. См. [[decisions/ADR-005-iso-date-strings]].
5. **`parent` — legacy поле**: до v2 здесь хранился свободный текст "проекта".
   После v2 заменено на `projectId`, но `parent` оставлен для миграции и для
   старых сортировок (`SortMode.BY_PROJECT` использует `parent`, а не `projectId`).

---

## Жизненный цикл UI и навигация

```
launch
  ↓
KotaTaskApp.onCreate()  ← applyTheme()
  ↓
MainActivity.onCreate()
  │
  ├── ┐
  │   │ prefs[KEY_ONBOARDING_DONE] == false?
  │   ↓ yes
  │   OnboardingActivity (7 шагов)
  │   │  → prefs.edit().putBoolean(KEY_ONBOARDING_DONE, true)
  │   │  → startActivity(MainActivity) + finish
  │   ↓
  │   (MainActivity второй раз, теперь продолжает дальше)
  │
  ├── inflate(ActivityMainBinding)
  ├── setupBottomNav() ← applyFeatureFlagsToNav()
  ├── setupFab()
  ├── requestNotifPermission() [Android 13+]
  ├── scheduleDaily()  ← перепланируем утренний worker
  ├── vm.errors.observe { Toast + consumeError }
  └── showFragment(TodayFragment | Stack.newMerged)
```

### Навигация между экранами

**Bottom-nav** (стандартные вкладки):
- `nav_today` → `TodayFragment` (если `featureSplit`)
- `nav_stack` → `StackFragment` или `StackFragment.newMerged()` (если `!featureSplit`)
- `nav_calendar` → `CalendarFragment` (если `featureCalendar`)
- `nav_folders` → `FoldersFragment` (если включён любой из Projects/Locations/Task Types)
- `nav_settings` → `SettingsFragment`

**Модалки** (через `openModalFragment(fragment, title)` + back stack):
- FAB → `AddTaskFragment` (создание)
- Карточка задачи → `AddTaskFragment.forEdit(id)` (редактирование)
- В папке "+" → `AddTaskFragment.forCategory(kind, id)` (создание с префиллом категории)
- Тап по папке → `CategoryTasksFragment`
- В настройках "Архив" → `ArchiveFragment`

Все модалки попадают в back stack под именем `modal_$title`. `OnBackStackChangedListener`
управляет видимостью FAB и заголовком top-bar.

---

## Конвейер расчёта приоритета

```
TaskViewModel.calcScore(task, allTasks)
  ├── getCoefficients()              ← SharedPreferences
  ├── todayLoad = Σ duration where status="Сегодня"
  ├── overloadLimit / loadDurationBoost ← если включён overload
  └── PriorityCalculator.calcPriority(task, coeffs, todayLoad, …)
        │
        ├── calcDeadlineScore(task.deadline)
        │     - просрочено   → 1.0
        │     - сегодня      → 0.9
        │     - ≤ 3 дня      → 0.7
        │     - ≤ 7 дней     → 0.5
        │     - дальше       → 0.2
        │     - пустой       → 0.3
        │
        ├── calcImportanceScore(task.importance)
        │     - Высокая → 1.0, Средняя → 0.6, Низкая → 0.2
        │
        ├── calcDurationScore(duration, dayLoad, limit, boost)
        │     - ≤ 15 мин → 1.0, … , > 120 мин → 0.2
        │     - + boost, если dayLoad > limit/2
        │
        ├── calcAgeScore(created)
        │     - 0…5 дней линейно 0 → 1.0, потом константа 1.0
        │
        └── score = Σ (score_i · coeff_i)
```

См. [[decisions/ADR-002-weighted-priority]].

---

## Конвейер уведомлений

```
[SettingsFragment / Onboarding]
   prefs.edit { KEY_NOTIF_ENABLED=true, KEY_NOTIF_HOUR=h, KEY_NOTIF_MINUTE=m }
        ↓
   scheduleDaily(ctx) — рассчитать delay до ближайшего HH:MM, enqueueUniqueWork(REPLACE)
        ↓
[~через delay часов]
NotificationWorker.doWork()
   ├── if !enabled → пропустить показ
   ├── db.taskDao().getAllTasksOnce().filter status=="Сегодня"
   ├── nm.notify(NOTIF_ID, builder...) — bigTextStyle с первыми 5 задачами
   └── reschedule(ctx, prefs) ← OneTimeWorkRequest на завтра в то же время
                                 (см. ADR-004)

[После ребута устройства]
BootReceiver.onReceive(BOOT_COMPLETED)
   → scheduleDaily(ctx)   ← worker очередь сбрасывается ОС после ребута
```

---

## Шаринг состояния между фрагментами

KotaTask использует **`activityViewModels()` повсеместно** — один экземпляр
`TaskViewModel` на весь жизненный цикл `MainActivity`. Это означает:
- Все фрагменты видят одно и то же `LiveData<List<Task>>` без передачи через arguments.
- Изменение в одном фрагменте (например, "В сегодня") моментально отражается во всех остальных.
- При `MainActivity.recreate()` (смена темы) — ViewModel переживает recreate, БД не перечитывается.

Минус: ViewModel разрастается — сейчас ≈ 400 строк, держит CRUD для 4 сущностей, сортировки,
фильтры, prefs-обёртки. Это сознательный размен на простоту против декомпозиции в DI.

---

## Связанные документы
- [[product/overview]] — что приложение делает
- [[tech/stack]] — версии библиотек
- [[decisions/ADR-001-explicit-room-migrations]]
- [[decisions/ADR-002-weighted-priority]]
- [[decisions/ADR-003-shared-preferences-feature-flags]]
- [[decisions/ADR-004-self-rescheduling-worker]]
- [[decisions/ADR-005-iso-date-strings]]
- [[decisions/ADR-006-three-axis-categorization]]
- [[decisions/ADR-007-status-russian-literals]]
- [[decisions/ADR-008-error-channel-consume]]
