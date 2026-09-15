# Архитектура KotaTask

**Дата документа:** 2026-05-28 · **обновлено:** 2026-09-15 (схема БД v4)
> Полный сводный справочник по коду — [`PROJECT.md`](../../../PROJECT.md) в корне репозитория.
**Корень модуля:** `KotaTask-main/android/app/src/main/java/com/mark/app/`

---

## Структура пакетов

```
com.mark.app/
├── KotaTaskApp.kt              ← Application: тема + все константы prefs
│
├── data/                       ← Слой данных (Room)
│   ├── AppDatabase.kt          ← @Database v4, миграции 1→2, 2→3, 3→4
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
│   ├── FoldersFragment.kt      ← Модальный, открывается из Settings
│   ├── ArchiveFragment.kt      ← Модальный, открывается из Settings
│   ├── SettingsFragment.kt
│   ├── AddTaskFragment.kt      ← Dual-mode: create / edit
│   ├── CategoryKind.kt         ← enum { PROJECT, LOCATION, TASK_TYPE }
│   ├── CategoryManagerFragment.kt  ← МЁРТВЫЙ КОД: нигде не инстанцируется
│   ├── CategoryTasksFragment.kt
│   ├── calendar/
│   │   ├── MonthCalendarAdapter.kt
│   │   └── CalendarCellView.kt   ← Кастомная View с donut-ring
│   └── dialog/
│       └── CategoryNameDialog.kt
│
└── util/
    ├── PriorityCalculator.kt   ← Чистая функция расчёта скора
    ├── NotificationWorker.kt   ← CoroutineWorker: утренний дайджест
    ├── DeferPromoteWorker.kt   ← CoroutineWorker: перенос отложенных задач в 00:00
    ├── BackupExportManager.kt  ← Локальный JSON-снимок в Downloads/
    └── BootReceiver.kt         ← перепланирует ОБА воркера после ребута
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
│     version = 4, migrations: 1→2, 2→3, 3→4                     │
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

## Модель данных (Room schema v4)

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
│ deferredDate TEXT│   ISO-дата автопереноса в «Сегодня» (v4)
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
   Удаление категории **очищает** ссылку у задач: репозиторий вызывает
   `dao.unlinkFromTasks(id)` перед `deleteById(id)`. Защита работает только для
   удаления через репозиторий — прямая правка БД оставит осиротевшие ссылки.
3. **`status` — строка с русскими литералами** ("Стек"/"Сегодня"/"Архив").
   Это закрепляет связку модели и UI-локализации. См. [[decisions/ADR-007-status-russian-literals]].
4. **`deadline` хранится как ISO-строка** (`yyyy-MM-dd`), не как timestamp.
   Сравнения идут через `LocalDate.parse(...)`. См. [[decisions/ADR-005-iso-date-strings]].
5. **`parent` — legacy поле**: до v2 здесь хранился свободный текст "проекта".
   После v2 заменено на `projectId`; новые задачи всегда пишут `""`.
   `SortMode.BY_PROJECT` теперь резолвит `projectId` → имя проекта (раньше читал
   всегда пустой `parent`, из-за чего сортировка не работала).
6. **`deferredDate`** (schema v4) — ISO-дата отложенного планирования. Пока она не
   наступила, задача остаётся в статусе «Стек»; в 00:00 `DeferPromoteWorker`
   переводит её в «Сегодня» и очищает поле. Сравнение идёт строковым `<=` —
   для ISO-дат лексикографический порядок совпадает с хронологическим.
7. **`JournalMode.TRUNCATE`** — WAL-файл не создаётся, каждая запись фиксируется
   прямо в `mark_db`, чтобы Auto Backup всегда видел актуальное состояние базы.

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
  │   │ первый запуск НА ЭТОЙ установке? (mark_local[install_initialized])
  │   │   → да: читаем Downloads/kotatask_backup.json, восстанавливаем настройки,
  │   │        задачи — только если Room-база пуста
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
  ├── vm.promoteDueDeferred() ← catch-up отложенных задач
  ├── scheduleDeferPromotion() ← воркер переноса на ближайшую полночь
  ├── vm.errors.observe { Toast + consumeError }
  └── showFragment(TodayFragment | Stack.newMerged)
```

### Навигация между экранами

**Bottom-nav** (стандартные вкладки):
- `nav_today` → `TodayFragment` (если `featureSplit`)
- `nav_stack` → `StackFragment` или `StackFragment.newMerged()` (если `!featureSplit`)
- `nav_calendar` → `CalendarFragment` (если `featureCalendar`)
- `nav_placeholder` → пустой слот, под ним FAB создания задачи
- `nav_settings` → `SettingsFragment`

Вкладки `nav_folders` в нижней навигации **нет**: центральный слот отдан FAB,
а «Папки» переехали в настройки.

**Модалки** (через `openModalFragment(fragment, title)` + back stack):
- FAB → `AddTaskFragment` (создание)
- Карточка задачи → `AddTaskFragment.forEdit(id)` (редактирование)
- В папке "+" → `AddTaskFragment.forCategory(kind, id)` (создание с префиллом категории)
- Тап по папке → `CategoryTasksFragment`
- В настройках "Архив" → `ArchiveFragment`
- В настройках "Папки" → `FoldersFragment`

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
   → scheduleDaily(ctx)           ← утренний дайджест
   → scheduleDeferPromotion(ctx)  ← перенос отложенных задач
   (очередь одноразовых worker'ов сбрасывается ОС после ребута)
```

---

## Шаринг состояния между фрагментами

KotaTask использует **`activityViewModels()` повсеместно** — один экземпляр
`TaskViewModel` на весь жизненный цикл `MainActivity`. Это означает:
- Все фрагменты видят одно и то же `LiveData<List<Task>>` без передачи через arguments.
- Изменение в одном фрагменте (например, "В сегодня") моментально отражается во всех остальных.
- При `MainActivity.recreate()` (смена темы) — ViewModel переживает recreate, БД не перечитывается.

Минус: ViewModel разрастается — сейчас 451 строка, держит CRUD для 4 сущностей, сортировки,
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
