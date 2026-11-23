# INDEX — Карта вики KotaTask

**Дата документа:** 2026-05-28 · **обновлено:** 2026-09-15
**Версия кодовой базы:** versionName `1.0-beta`, схема БД v4 (фактические билды в `Builds/` до `v4.8`)
**Платформа:** Android native, Kotlin 2.0.21, minSdk 26

---

## Быстрый старт

- **Новое в 1.1 → [RELEASE_NOTES_1.1.md](RELEASE_NOTES_1.1.md)** — виджет, экспорт, настройка меню и канбан; актуальные изменения схемы и команды проверок.

- 📘 **Полный технический справочник → [`PROJECT.md`](PROJECT.md)** — функционал,
  зависимости, схема БД, алгоритм, настройки, техдолг. Сверен с кодом на 2026-09-15
- 👋 Что это за приложение → [[wiki/product/overview]]
- 🏗️ Как устроен код → [[wiki/tech/architecture]]
- 🛠️ Стек и версии → [[wiki/tech/stack]]
- 📋 Что готово, что нет → [[wiki/status/mvp-scope]]

---

## Структура вики

```
kotatask-wiki/
├── INDEX.md                                ← этот файл
└── wiki/
    ├── product/
    │   └── overview.md                     ← Описание продукта и ключевых фич
    ├── tech/
    │   ├── stack.md                        ← Зависимости, версии, паттерны
    │   └── architecture.md                 ← Слои, модули, модель данных
    ├── decisions/                          ← Architectural Decision Records
    │   ├── ADR-001-explicit-room-migrations.md
    │   ├── ADR-002-weighted-priority.md
    │   ├── ADR-003-shared-preferences-feature-flags.md
    │   ├── ADR-004-self-rescheduling-worker.md
    │   ├── ADR-005-iso-date-strings.md
    │   ├── ADR-006-three-axis-categorization.md
    │   ├── ADR-007-status-russian-literals.md
    │   └── ADR-008-error-channel-consume.md
    └── status/
        └── mvp-scope.md                    ← Что реализовано / что нет
```

---

## Раздел 1. Продукт

### [[wiki/product/overview]]
Что делает приложение, какие фичи реализованы, целевой пользователь, чего
в коде НЕТ. Главные пункты:
- Алгоритмический приоритет с пользовательскими весами.
- 4 статуса задачи (Стек / Сегодня / Архив + диапазон в календаре).
- 3 независимые оси категоризации.
- Календарь с режимом "точка" / "диапазон".
- Ежедневные уведомления.
- 7-шаговый онбординг с feature flags.
- Контроль дневной нагрузки (overload).
- Архив с массовым удалением.

---

## Раздел 2. Технологии

### [[wiki/tech/stack]]
- **Стек:** Kotlin 2.0.21 + AGP 8.5.2 + KSP. JVM 17. SDK 26→34.
- **AndroidX:** core-ktx, appcompat, material 1.11, fragment-ktx, lifecycle 2.7, room 2.6.1, work 2.9.
- **Архитектурные паттерны:** MVVM-light, Repository, single ViewModel via `activityViewModels()`,
  ViewBinding, feature flags через SharedPreferences.
- **Чего нет:** DI (Hilt/Koin/Dagger), Compose, Navigation Component, тестов,
  сети, аналитики, Crashlytics.

### [[wiki/tech/architecture]]
- Структура пакетов (`data` / `repository` / `viewmodel` / `ui` / `util` / `adapter`).
- Слоистая диаграмма UI → ViewModel → Repository → Room.
- Модель данных (4 таблицы: `tasks`, `projects`, `locations`, `task_types`).
- Жизненный цикл UI и навигация (bottom-nav + модальные fragment'ы).
- Конвейер расчёта приоритета.
- Конвейер уведомлений.

---

## Раздел 3. Архитектурные решения (ADR)

| # | ADR | Тема |
|---|---|---|
| 001 | [[wiki/decisions/ADR-001-explicit-room-migrations]] | Явные Room-миграции, нет `fallbackToDestructiveMigration` |
| 002 | [[wiki/decisions/ADR-002-weighted-priority]] | Линейная взвешенная формула приоритета с пользовательскими весами |
| 003 | [[wiki/decisions/ADR-003-shared-preferences-feature-flags]] | `SharedPreferences` как единственное хранилище настроек и feature flags |
| 004 | [[wiki/decisions/ADR-004-self-rescheduling-worker]] | Self-rescheduling `OneTimeWorkRequest` вместо `PeriodicWorkRequest` |
| 005 | [[wiki/decisions/ADR-005-iso-date-strings]] | Дедлайны как ISO-строки `yyyy-MM-dd`, не timestamp |
| 006 | [[wiki/decisions/ADR-006-three-axis-categorization]] | Три независимые оси категоризации (Project / Location / TaskType) |
| 007 | [[wiki/decisions/ADR-007-status-russian-literals]] | `status` хранится как русская строка-литерал, не enum |
| 008 | [[wiki/decisions/ADR-008-error-channel-consume]] | Канал одноразовых ошибок `LiveData<String?>` + `consumeError()` |
| 009 | [[wiki/decisions/ADR-009-android-only-beta]] | Бета-тестирование только среди знакомых с Android (APK-файлом) |

Все ADR датированы **2026-05-28** (дата первичной задокументированной фиксации,
не дата принятия решения).

---

## Раздел 4. Статус и пробелы

### [[wiki/status/mvp-scope]]
Что готово полностью:
- CRUD задач, алгоритм приоритета, категоризация, календарь, уведомления, онбординг,
  тёмная тема, поиск, архив с массовым удалением.

Что выглядит незаконченным:
- 🟡 Поле `assignee` — мёртвый код в схеме.
- 🟡 Поле `parent` — двойной механизм проектов (legacy + новый `projectId`).
- 🟡 Удаление проекта не очищает `projectId` у задач (нет FK).
- 🟡 INTERNET permission заявлен, но не используется.
- 🟡 Релиз без минификации.
- 🟡 **0% тестов** (включая миграции Room).
- 🟡 `exportSchema = false`.
- 🟡 Несоответствие APK naming convention.
- 🟡 Поле `purpose` не отображается в карточке.

---

## Конвенции этой вики

- **Язык:** русский.
- **Формат дат:** `YYYY-MM-DD`.
- **Внутренние ссылки:** `[[wiki/section/file]]` (Obsidian-style).
- **Внешние ссылки на код:** относительные markdown-ссылки на файлы исходников.
- **ADR-формат:** Status / Дата / Контекст / Решение / Последствия / Связанные документы.

## Не вошло (TODO)

- `wiki/beta/` — пуст (нет данных о бета-тестировании).
- `wiki/competitors/` — пуст (нет конкурентного анализа).
- `wiki/users/` — пуст (нет ICP / персон / интервью).

Эти разделы появились в структуре раньше кода, и из самого кода их наполнить
нечем — нужны данные снаружи (интервью, ресёрч).
