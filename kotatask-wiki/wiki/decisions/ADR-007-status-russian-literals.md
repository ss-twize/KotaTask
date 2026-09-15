# ADR-007 — `status` хранится как русская строка-литерал, а не enum

- **Статус:** Принято (видно в коде)
- **Дата:** 2026-05-28
- **Контекст модуля:** `data/Task.kt`, `data/TaskDao.kt`, `viewmodel/TaskViewModel.kt`

## Контекст

Поле `Task.status` может принимать значения "Стек", "Сегодня", "Архив". Варианты:
1. **Хранить строку напрямую** (`status: String = "Стек"`).
2. Хранить enum с TypeConverter.
3. Хранить int (0/1/2) с маппингом в UI.

## Решение

Выбран вариант 1. Литералы хардкожены прямо в SQL-запросах:
```kotlin
@Query("UPDATE tasks SET status = 'Архив', completed = :completedAt WHERE id = :id")
suspend fun archiveTask(id: String, completedAt: Long)

@Query("DELETE FROM tasks WHERE status = 'Архив'")
suspend fun deleteAllArchived()
```

И в Kotlin-коде ViewModel:
```kotlin
val active = all.filter { it.status == "Стек" || it.status == "Сегодня" }
```

Также `Task.importance` хранится так же — строкой `"Высокая"|"Средняя"|"Низкая"`.

## Обоснование (вывод из кода)

- Простота. Никаких TypeConverter'ов, никаких enum'ов с `.name` / `.valueOf()`.
- При SQL-инспекции БД статусы читаются глазами без декодинга.
- Локализации на другие языки **в проекте нет** (см. константу `RU = Locale("ru")`
  в `CalendarFragment.kt` — жёстко прибита).

## Последствия

**Плюсы:**
- Минимум кода. SQL-запросы читаются как есть.
- Простая отладка БД через `sqlite3`.

**Минусы / риски:**
- Опечатка в литерале (`"стек"` вместо `"Стек"`) — компилятор не поймает,
  фильтр молча вернёт пустой список. Поиск такой ошибки сложный.
- **Нелокализуемо**: если когда-то понадобится английская версия, придётся
  переименовывать поле в БД (миграция), либо хранить отдельно "internal status"
  и "display status".
- IDE не подскажет возможные значения — нужно помнить или искать grep'ом.
- Связано с UI: `SortMode.BY_PROJECT` и hard-coded compareBy завязаны на эти строки.

## Связанные документы
- [[ADR-001-explicit-room-migrations]] — миграция значений status потребует ALTER TABLE
- [[../product/overview]] — раздел "Четыре статуса задачи"
