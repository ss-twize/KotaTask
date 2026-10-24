# Доска проектов и подзадачи — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Доска «Проекты → Общий» с колонками-проектами, ручным порядком и плавным перетаскиванием, листы проектов и подзадачи-полноценные задачи в Mac-версии KotaTask.

**Architecture:** Модель задачи получает `parentId`, `sortIndex` и необязательную длительность. Вся новая логика — чистые функции в `Logic/` (время родителя и подзадач, ручной порядок, колонки доски), покрытые тестами. `TaskStore` получает операции размещения задач, каждая — одно действие ⌘Z. Интерфейс — новые `BoardView` и `ProjectListView` вместо `StackView`, перетаскивание через `onDrag` + `DropDelegate` с общим состоянием перетаскивания.

**Tech Stack:** SwiftUI, macOS 26, Swift 6, Swift Testing, XcodeGen. Новых зависимостей нет.

**Spec:** `docs/superpowers/specs/2026-10-22-mac-board-subtasks-design.md`

## Global Constraints

- Только `mac/`; Android не меняется.
- macOS 26, Swift 6, `SWIFT_VERSION 6.0`, без новых пакетов.
- Весь текст интерфейса — на русском, формулировки из спеки дословно: «Общий», «Без проекта», «+ Новая задача», «+ Подзадача», «Подзадачи · N из M», «Сделать подзадачей», «Сделать отдельной задачей», «↳ Родитель · Проект», «Σ N мин», «время в родителе», «нет дедлайна».
- Каждое изменение через доску (перенос, перестановка, вложение, вынос, перестановка колонок, создание строкой) — ровно одно действие ⌘Z с русским названием.
- Старый `kotatask.json` (без новых полей) читается; новые поля Android игнорирует.
- «Уменьшить движение» и обе темы учитываются, пружины — только из `Design/Motion.swift`.
- Существующие 49 тестов остаются зелёными на каждом шаге.
- Коммиты — только по просьбе пользователя (правило сессии); шаги «Commit» в этом плане заменены проверкой сборки.

## Review Focus

1. **Бросок задачи на саму себя, на свою подзадачу или родителя на чужую карточку** — ничего не меняется, данные целы. Тест в Task 3: `placeRejectsInvalidNesting`.
2. **Перенос при активном поиске или фильтре** — перестановка внутри колонки выключена, перенос в другую колонку ставит задачу в конец. Тест в Task 3: `placeAtEndWhenPositionNil`.
3. **Удаление проекта, где есть родители с подзадачами** — все уходят в «Без проекта» вместе, связи сохраняются. Тест в Task 3: `deletingProjectKeepsTreesTogether`.
4. **⌘Z после переноса между колонками** возвращает и проект, и место, и проект подзадач. Тест в Task 3: `undoRestoresCrossColumnMove`.
5. **Многократная вставка в одно и то же место** не схлопывает порядок (точность `Double`). Тест в Task 2: `repeatedInsertionKeepsStrictOrder`.

---

## Карта файлов

| Файл | Что делает |
|---|---|
| `Model/TaskItem.swift` (изм.) | поля `parentId`, `sortIndex`, `duration: Int?` |
| `Model/Category.swift` (изм.) | поле `sortIndex` (используется для проектов) |
| `Store/Persistence.swift` (изм.) | `StoreSnapshot.formatVersion` (текущий — 2) |
| `Logic/TaskTree.swift` (нов.) | дети, режим времени, итоговое время, нагрузка дня без двойного счёта |
| `Logic/ManualOrder.swift` (нов.) | ручной порядок, индекс вставки, перенумерация |
| `Logic/BoardQueries.swift` (нов.) | колонки «Общего», поиск/фильтры по деревьям, начальный порядок |
| `Store/TaskStore+Board.swift` (нов.) | операции размещения, создание строкой, выполнение родителя, перестановка колонок |
| `Views/Board/BoardView.swift` (нов.) | доска «Общий» |
| `Views/Board/ProjectListView.swift` (нов.) | лист проекта (одна колонка ≤ 720 pt) |
| `Views/Board/BoardColumnView.swift` (нов.) | колонка: шапка, карточки, слот, строка ввода |
| `Views/Board/BoardCard.swift` (нов.) | компактная карточка с подзадачами |
| `Views/Board/InlineTaskField.swift` (нов.) | строка «+ Новая задача» / «+ Подзадача» |
| `Views/Board/BoardDrag.swift` (нов.) | состояние перетаскивания и `DropDelegate`-ы |
| `Views/Stack/StackView.swift` (удал.) | заменён доской |
| `App/AppModel.swift`, `Views/Root/*`, `App/KotaTaskApp.swift` (изм.) | навигация «Общий»/проекты, диалог выполнения родителя |
| `Views/TaskCard/TaskCardView.swift`, `Views/Today/TodayView.swift`, `Views/Calendar/DonutCell.swift`, `Views/TaskForm/*` (изм.) | подзадачи и итоговое время в остальных экранах |
| `KotaTaskMacTests/BoardTests.swift` (нов.) | тесты Task 1–3 |

---

### Task 1: Модель и время родителя/подзадач

**Files:**
- Modify: `mac/KotaTaskMac/Model/TaskItem.swift`, `mac/KotaTaskMac/Model/Category.swift`, `mac/KotaTaskMac/Store/Persistence.swift`
- Create: `mac/KotaTaskMac/Logic/TaskTree.swift`
- Modify (переход на итоговое время): `Logic/PriorityCalculator.swift`, `Logic/TaskQueries.swift`, `App/AppModel.swift` (`sortContext`), `Views/Today/TodayView.swift:13`, `Views/Calendar/DonutCell.swift:92`, `Views/TaskCard/TaskCardView.swift:138`, `Logic/TaskValidator.swift`
- Test: `mac/KotaTaskMacTests/BoardTests.swift`

**Interfaces:**
- Produces:
  - `TaskItem.parentId: String?`, `TaskItem.sortIndex: Double` (по умолчанию `0`), `TaskItem.duration: Int?` (nil — не задана). JSON: `parentId` — строка или `""`; `sortIndex` — число; `duration` — число или ключ отсутствует.
  - `Category.sortIndex: Double` (по умолчанию `0`).
  - `StoreSnapshot.formatVersion: Int` — читается из `version` (нет ключа → 1), пишется `StoreSnapshot.currentVersion = 2`; в `==` не участвует.
  - `enum TimeMode: Equatable { case single(Int), bigTask(Int), block(Int), subtask(own: Int?, parentHasOwn: Bool) }`
  - `enum TaskTree` (чистые функции, `all: [TaskItem]`):
    - `children(of id: String, in all: [TaskItem]) -> [TaskItem]` — все дети, отсортированы `ManualOrder.sorted` (Task 2; до него — по `sortIndex`)
    - `openChildren(of:in:) -> [TaskItem]` — дети не в архиве
    - `hasChildren(_ id: String, in:) -> Bool`
    - `timeMode(_ task: TaskItem, in:) -> TimeMode`
    - `effectiveMinutes(_ task: TaskItem, in:) -> Int`
    - `todayLoadMinutes(_ all: [TaskItem]) -> Int`
    - `effectiveMinutesMap(_ all: [TaskItem]) -> [String: Int]`
  - `SortContext.minutes: [String: Int]`; `PriorityCalculator.score(_:minutes:coefficients:load:today:now:)` — фактор длительности берёт `minutes`.
  - `ValidatedTask.duration: Int?`; `FormConfig.allowsEmptyDuration: Bool` (по умолчанию `false`).

Правила времени (спека §2.12, §8):

| Задача | `timeMode` | `effectiveMinutes` |
|---|---|---|
| без родителя и детей | `.single(duration ?? 30)` | `duration ?? 30` |
| родитель, `duration != nil` | `.bigTask(duration)` | `duration` |
| родитель, `duration == nil` | `.block(Σ открытых детей (duration ?? 0))` | эта сумма |
| подзадача | `.subtask(own: duration, parentHasOwn: родитель.duration != nil)` | `duration ?? 0` |

`todayLoadMinutes`: сумма `effectiveMinutes` задач со статусом «Сегодня», кроме подзадач, чей родитель тоже в «Сегодня».

- [ ] **Step 1: Написать тесты** в `BoardTests.swift`, `@Suite("Время родителя и подзадач")`:
  - `legacyJSONDecodes` — JSON задачи без `parentId`/`sortIndex` → `parentId == nil`, `sortIndex == 0`, `duration == 30` (ключ есть); JSON без `duration` → `duration == nil`.
  - `roundTripKeepsNewFields` — `parentId: "p"`, `sortIndex: 2.5`, `duration: nil` переживают encode/decode.
  - `singleTaskDefaultsTo30` — `effectiveMinutes(TaskItem(title:, duration: nil))` = 30.
  - `bigTaskWinsOverSubtasks` — родитель 120, дети 30/45 → `.bigTask(120)`, 120.
  - `blockSumsOpenChildren` — родитель nil, дети 30, 45, 90 (90 в архиве) → `.block(75)`, 75.
  - `subtaskWithoutTimeInBigTask` — ребёнок nil у родителя 120 → `.subtask(own: nil, parentHasOwn: true)`, 0.
  - `todayLoadNoDoubleCount` — родитель-блок в «Сегодня» (дети 30+45) и его ребёнок 30 тоже в «Сегодня» → 75; только ребёнок в «Сегодня» → 30.
  - `priorityUsesEffectiveMinutes` — родитель-блок с суммой 10 мин получает тот же `durationScore`, что одиночная задача на 10 мин.
- [ ] **Step 2:** `xcodebuild test … -only-testing:KotaTaskMacTests/…` — тесты не собираются (нет `TaskTree`, полей).
- [ ] **Step 3:** Добавить поля и кодирование; `StoreSnapshot.formatVersion`; создать `TaskTree` по таблице; перевести все места из списка Files на `effectiveMinutes`/`todayLoadMinutes`/`SortContext.minutes` (сортировка «По времени» — по итоговому времени; радиус «пончика» — по итоговому). `TaskValidator`: пустая длительность → `nil`, если `config.allowsEmptyDuration`, иначе 30, как сейчас.
- [ ] **Step 4:** Запустить весь набор тестов — новые и 49 старых зелёные.

---

### Task 2: Ручной порядок и колонки доски (чистая логика)

**Files:**
- Create: `mac/KotaTaskMac/Logic/ManualOrder.swift`, `mac/KotaTaskMac/Logic/BoardQueries.swift`
- Test: `mac/KotaTaskMacTests/BoardTests.swift`

**Interfaces:**
- Consumes: `TaskItem.sortIndex/parentId`, `TaskTree.children`, `TaskQueries.sort`, `SortContext`.
- Produces:
  - `enum ManualOrder`:
    - `sorted(_ tasks: [TaskItem]) -> [TaskItem]` — по `sortIndex`, при равенстве новые сверху (`created` по убыванию).
    - `index(insertingAt position: Int, among siblings: [TaskItem]) -> Double` — `siblings` уже без перемещаемой задачи и отсортированы; середина между соседями; в начало — `первый − 1`; в конец/пусто — `последний + 1` / `0`.
    - `needsRenumbering(_ siblings: [TaskItem]) -> Bool` — есть соседние индексы ближе `1e-6`.
    - `renumbered(_ siblings: [TaskItem]) -> [String: Double]` — `0, 1, 2…` в текущем порядке.
  - `enum ProjectScope: Hashable { case none, project(String), all }` — `.all` используется, когда ось «Проекты» выключена (projectId не учитывается).
  - `struct BoardColumn: Identifiable { let scope: ProjectScope; let title: String; let tasks: [TaskItem] }` — `tasks` только верхнего уровня, активные, `ManualOrder.sorted`.
  - `enum BoardQueries`:
    - `columns(all: [TaskItem], projects: [Category]) -> [BoardColumn]` — «Без проекта», затем проекты по `sortIndex`, затем по имени.
    - `topLevel(in scope: ProjectScope, all:) -> [TaskItem]`
    - `matches(_ task: TaskItem, query: String, location: CategoryFilter, taskType: CategoryFilter, all:) -> Bool` — родитель подходит, если подходит он сам или любой его ребёнок.
    - `initialOrder(all:, mode: SortMode, context: SortContext) -> [String: Double]` — для каждой колонки и каждого родителя: порядок `TaskQueries.sort(…, by: mode)` → индексы `0, 1, 2…`.
- [ ] **Step 1: Тесты** `@Suite("Ручной порядок и колонки")`:
  - `insertBetweenNeighbours` — соседи 1 и 2, позиция 1 → 1.5; позиция 0 → 0; конец → 3; пустой список → 0.
  - `repeatedInsertionKeepsStrictOrder` — 60 вставок подряд в позицию 1 с перенумерацией по `needsRenumbering` дают строго возрастающий порядок и правильную последовательность.
  - `columnsStartWithNoProject` — проекты B(sortIndex 1), A(sortIndex 0) → заголовки `["Без проекта", "A", "B"]`; подзадачи и архив в колонки не попадают; задача «Сегодня» попадает.
  - `searchMatchesParentByChild` — запрос по названию ребёнка находит родителя.
  - `initialOrderFollowsPriority` — при `.priority` горящая задача получает меньший индекс, чем далёкая.
- [ ] **Step 2:** Запустить — не собирается.
- [ ] **Step 3:** Реализовать `ManualOrder` и `BoardQueries` по интерфейсам.
- [ ] **Step 4:** Весь набор тестов зелёный.

---

### Task 3: Операции хранилища

**Files:**
- Create: `mac/KotaTaskMac/Store/TaskStore+Board.swift`
- Modify: `mac/KotaTaskMac/Store/TaskStore.swift` (`load` выставляет `needsOrderSeeding`, когда `formatVersion < 2`; `delete(id:)` и `delete(ids:)` удаляют и детей; `deleteCategory` для проекта переносит деревья целиком)
- Modify: `mac/KotaTaskMac/App/AppModel.swift` (`start()` вызывает `seedManualOrderIfNeeded`)
- Test: `mac/KotaTaskMacTests/BoardTests.swift`

**Interfaces:**
- Consumes: Task 1–2.
- Produces (все `@MainActor` на `TaskStore`, каждая мутация — один `mutate(...)`):
  - `enum TaskContainer: Hashable { case column(ProjectScope), parent(String) }`
  - `canPlace(_ taskId: String, into container: TaskContainer) -> Bool` — запрещено: в саму себя, в своего ребёнка, родителя с детьми в `.parent`, в `.parent` подзадачи.
  - `@discardableResult place(_ taskId: String, into container: TaskContainer, at position: Int?) -> Bool` — `nil` = в конец. В колонку: `parentId = nil`, проект = колонки (для `.all` не меняется), дети получают тот же проект. В родителя: `parentId`, проект родителя. Перенумеровывает соседей при `needsRenumbering`. Имена отмены: «Перемещение задачи» (колонка ↔ колонка), «Вложение задачи» (→ родитель), «Вынос подзадачи» (родитель → колонка).
  - `makeStandalone(_ id: String)` — в колонку родителя сразу после него.
  - `@discardableResult quickAdd(title: String, into container: TaskContainer, now: Date = .now) -> TaskItem?` — пустое название → nil; важность «Средняя», без дедлайна, `duration` nil для подзадачи и 30 для задачи, в конец, статус «Стек». Отмена: «Создание задачи».
  - `completeParent(_ id: String, closingSubtasks: Bool, now: Date = .now)` — `true`: родитель и открытые дети в архив; `false`: открытые дети становятся задачами в той же колонке сразу под бывшим родителем. Отмена: «Выполнение задачи».
  - `reopen(_ id: String)` — из архива в «Стек», `completed = nil`, место сохраняется. Отмена: «Возврат задачи».
  - `moveProjectColumn(_ projectId: String, to position: Int)` — перестановка проектов (позиция среди проектов, без «Без проекта»). Отмена: «Перестановка колонок».
  - `private(set) var needsOrderSeeding: Bool`; `seedManualOrderIfNeeded(mode: SortMode, context: SortContext)` — применяет `BoardQueries.initialOrder` без записи в отмену, затем сохраняет (файл получает версию 2).
- [ ] **Step 1: Тесты** `@MainActor @Suite("Доска: операции")`:
  - `moveBetweenColumnsCarriesSubtasks` — родитель с 2 детьми из «A» в «B» позиция 0 → все трое `projectId == B`, родитель первый в колонке B.
  - `nestAndDetach` — задача X в родителя P → `parentId == P`, проект P; `makeStandalone(X)` → `parentId == nil`, в колонке сразу после P.
  - `placeRejectsInvalidNesting` — в себя, в своего ребёнка, родителя с детьми в другую задачу, в подзадачу → `false`, снимок не изменился.
  - `placeAtEndWhenPositionNil` — `place(t, into: .column(.project(B)), at: nil)` → последняя в B.
  - `quickAddDefaults` — задача: важность `.medium`, `deadline == nil`, `duration == 30`, последняя в колонке; подзадача: `duration == nil`; пустое название → `nil`.
  - `completeParentDetachesOpenSubtasks` — `closingSubtasks: false`: открытый ребёнок — задача верхнего уровня сразу под родителем, выполненный ребёнок остаётся привязанным; `true`: все в архиве.
  - `reopenSubtask` — выполненный ребёнок → статус «Стек», `parentId` прежний.
  - `deleteParentDeletesChildren` — `delete(id: P)` удаляет и детей; ⌘Z возвращает всех.
  - `deletingProjectKeepsTreesTogether` — проект с родителем и детьми удалён → все трое `projectId == nil`, `parentId` у детей сохранён.
  - `undoRestoresCrossColumnMove` — перенос из A в B, `undo()` → проект, `sortIndex` и проект детей как до переноса; имя действия «Перемещение задачи».
  - `columnReorder` — проекты [A, B, C], `moveProjectColumn(C, to: 0)` → [C, A, B].
  - `seedingRunsOnceForLegacyFile` — снимок с `version: 1` → `needsOrderSeeding`; после сида и сохранения перезагрузка → `false`.
- [ ] **Step 2:** Запустить — не собирается.
- [ ] **Step 3:** Реализовать операции через существующий `mutate(_:_:)`.
- [ ] **Step 4:** Весь набор тестов зелёный.

---

### Task 4: Навигация, доска и лист проекта (без перетаскивания)

**Files:**
- Modify: `App/AppModel.swift` — `enum SidebarItem { case today, board, project(String), calendar, archive, category(CategoryKind, String?) }`; `.tasks` удалить; везде, где был `.tasks`, — `.board`; `normalizeSelection` уводит с удалённого `.project`; `didSaveForm` → `.board`.
- Modify: `Views/Root/SidebarView.swift` — раздел «ПРОЕКТЫ» (кнопка «+»): «Общий» (бейдж — число активных задач верхнего уровня), затем проекты по `sortIndex` с бейджами и прежним контекстным меню; секция проектов из старого цикла категорий убирается, локации и типы — как были. Ось «Проекты» выключена → один пункт «Задачи» (`.board`).
- Modify: `Views/Root/RootView.swift` (`DetailView`), `App/KotaTaskApp.swift` (⌘2 → «Общий»)
- Create: `Views/Board/BoardView.swift`, `Views/Board/ProjectListView.swift`, `Views/Board/BoardColumnView.swift`, `Views/Board/BoardCard.swift`, `Views/Board/InlineTaskField.swift`
- Delete: `Views/Stack/StackView.swift` (перенести в `BoardView`: поиск в тулбаре «Поиск по задачам…», фильтры по локации и типу и полоску «N задач · M мин в «Сегодня»»)

**Interfaces:**
- Consumes: `BoardQueries.columns/topLevel/matches`, `TaskTree.*`, `TaskStore.quickAdd/place/makeStandalone/reopen`, `AppModel.perform(_:on:)`.
- Produces:
  - `BoardColumnView(column: BoardColumn, width: CGFloat?, reorderEnabled: Bool)` — `width == nil` для листа проекта.
  - `BoardCard(task: TaskItem, children: [TaskItem], isExpanded: Binding<Bool>)`.
  - `InlineTaskField(container: TaskContainer, placeholder: String)` — ⏎ создаёт через `quickAdd` и оставляет поле открытым, Esc закрывает.
  - `AppModel.expandedParents: Set<String>` — раскрытые подзадачи переживают смену экрана.

Требования к виду (спека §7.2–7.3, макет `board-overview-v2.html`):
- Колонка шириной 280 pt, отступ 16, горизонтальная прокрутка доски; шапка: название, число, меню «···» («Новая задача», для проекта ещё «Переименовать…», «Удалить…»).
- Карточка: полоса важности, кружок выполнения слева от названия, бейдж приоритета (если умная сортировка включена), чипы: «Сегодня», дедлайн, время (`.bigTask/.single` — «N мин», `.block` — «Σ N мин»), отложенность; пометка «нет дедлайна», если уровень помощи требует дедлайн, а его нет.
- Подзадачи: полоска прогресса, «Подзадачи · N из M» (раскрытие по клику), строки с кружком (выполнить/вернуть), названием, своими чипами («время в родителе» для `.subtask(own: nil, parentHasOwn: true)`), «+ Подзадача».
- Клик по карточке — форма редактирования (как сейчас); контекстное меню: «Редактировать…», «В сегодня»/«В стек», «Выполнить», «Сделать отдельной задачей» (для подзадачи), «Удалить…».
- Лист проекта: одна колонка до 720 pt по центру, заголовок — название проекта.
- Сортировки на доске и в листе нет.

- [ ] **Step 1:** Собрать и запустить на демо-данных (`KOTATASK_DATA_DIR`) с проектами и подзадачами (расширить `seed_demo.py` в scratchpad: 3 проекта, 2 родителя с 3–5 подзадачами, по одному в каждом режиме времени).
- [ ] **Step 2:** Проверить вживую: колонки в нужном порядке, задача «Сегодня» видна в своей колонке, «Σ» у блока, раскрытие подзадач, создание строкой (⏎ — следующая строка), выполнение/возврат подзадачи кружком, «Сделать отдельной задачей», лист проекта, поиск находит родителя по подзадаче.
- [ ] **Step 3:** Весь набор тестов зелёный, сборка без предупреждений.

---

### Task 5: Перетаскивание

**Files:**
- Create: `Views/Board/BoardDrag.swift`
- Modify: `Views/Board/BoardColumnView.swift`, `Views/Board/BoardCard.swift`, `Views/Board/BoardView.swift`, `Views/Root/SidebarView.swift`

**Interfaces:**
- Consumes: `TaskStore.canPlace/place/moveProjectColumn/moveToToday`, `ManualOrder`.
- Produces:
  - `@MainActor @Observable final class BoardDragState { var draggingTaskId: String?; var draggingProjectId: String?; var target: DropTarget? }` — живёт в `AppModel.boardDrag`.
  - `enum DropTarget: Equatable { case insert(TaskContainer, position: Int), nest(parentId: String) }`
  - Полезная нагрузка перетаскивания — `NSItemProvider(object: "kotatask-task:<id>" as NSString)`; `DropDelegate` принимает перенос, только пока `BoardDragState.draggingTaskId` (или `draggingProjectId`) не nil, — так чужой текст из других приложений не становится задачей, и своё UTType-объявление не нужно.

Поведение (спека §2.5–2.9, §5, §8):
- Начало перетаскивания (`onDrag`) ставит `draggingTaskId`; превью — та же карточка с поворотом −2.5°, масштабом 1.03 и тенью (`onDrag(_:preview:)`).
- Исходная карточка во время переноса — прозрачность 0.35.
- `DropDelegate` колонки по `dropUpdated` считает позицию по середине карточек (кадры карточек — через `onGeometryChange` в координатах колонки) и выставляет `.insert`; в позиции раскрывается слот высотой с переносимую карточку, `withAnimation(Motion.snappy)`.
- Курсор над средней половиной карточки, в которую можно вложить (`canPlace`), — `.nest`: карточка подсвечивается рамкой акцента и меткой «Сделать подзадачей», слот закрывается. Нельзя — цель не подсвечивается.
- Внутри раскрытой карточки строки подзадач — тоже цели `.insert(.parent(id), position:)`.
- Отпускание — `place(...)`, затем `Motion.standard`; уход курсора — сброс цели.
- `reorderEnabled == false` (поиск/фильтр активны): внутри своей колонки не принимаем, в чужую — `place(…, at: nil)`.
- Сайдбар: бросок на «Сегодня» — `moveToToday`, на проект — `place(…, into: .column(.project(id)), at: nil)`; строка подсвечивается при наведении.
- Шапки колонок проектов перетаскиваются для перестановки (`draggingProjectId`, «Без проекта» — не цель и не источник).
- «Уменьшить движение»: без поворота, масштаба и пружин слота — плавное появление.

- [ ] **Step 1:** Реализовать и собрать.
- [ ] **Step 2:** Проверить вживую каждое поведение из списка выше, включая ⌘Z после каждого вида переноса и отказ на родителя с детьми.
- [ ] **Step 3:** Весь набор тестов зелёный.

---

### Task 6: Подзадачи в остальных экранах и форма

**Files:**
- Modify: `App/AppModel.swift` (`TaskCardModel` ← `parentLabel: String?` «↳ Родитель · Проект»; `perform(.complete)` для родителя с открытыми детьми ставит `parentPendingCompletion`), `Views/Root/RootView.swift` (диалог), `Views/TaskCard/TaskCardView.swift` (подпись родителя, чип времени по `TaskTree.timeMode`), `Views/Archive/ArchiveView.swift`, `Views/Category/CategoryTasksView.swift`, `Views/TaskForm/TaskFormView.swift`, `Logic/TaskValidator.swift`
- Test: `mac/KotaTaskMacTests/LogicTests.swift` (валидация)

**Interfaces:**
- Consumes: `TaskTree`, `TaskStore.completeParent`.
- Produces: `AppModel.parentPendingCompletion: TaskItem?`; `FormConfig.allowsEmptyDuration` выставляется формой для родителя и подзадачи.

Требования:
- «Сегодня», архив, экраны локаций и типов: подзадача — обычная карточка с подписью «↳ Родитель · Проект»; время карточки — итоговое.
- Диалог выполнения родителя (спека §8): «Выполнить вместе с подзадачами», «Только задачу — подзадачи станут отдельными», «Отмена».
- Форма для родителя и подзадачи: пустая длительность допустима; подпись под полем — «Пусто — время считается из подзадач» (родитель) или «Пусто — время входит в родителя» (подзадача); если у родителя задано время и у подзадач тоже — «У подзадач в сумме N мин».
- [ ] **Step 1: Тесты:** `emptyDurationAllowedForTree` — `allowsEmptyDuration: true`, пусто → `duration == nil`; `false` → 30 (как сейчас).
- [ ] **Step 2:** Запустить — падает.
- [ ] **Step 3:** Реализовать.
- [ ] **Step 4:** Весь набор зелёный; вживую — подзадача в «Сегодня» с подписью, нагрузка без двойного счёта, диалог выполнения родителя в обоих вариантах, форма с подсказками.

---

### Task 7: Проверка, ревью, установка

- [ ] **Step 1:** Весь набор тестов и Release-сборка без предупреждений.
- [ ] **Step 2:** Вживую на демо-данных в обеих темах и в узком/широком окне: доска, лист проекта, перетаскивание, подзадачи, «Сегодня», календарь.
- [ ] **Step 3:** Ревью всей ветки свежим ревьюером (самая сильная модель): данные, отмена, перетаскивание, совместимость JSON.
- [ ] **Step 4:** Исправить подтверждённые замечания, повторить Step 1.
- [ ] **Step 5:** С согласия пользователя переустановить `mac/install.sh --open` (закрывает запущенную копию).
- [ ] **Step 6:** Обновить `mac/README.md` (доска, подзадачи) и память проекта.
