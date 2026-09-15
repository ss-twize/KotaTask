# ADR-005 — Дедлайны как ISO-строки `yyyy-MM-dd` вместо timestamp

- **Статус:** Принято (видно в коде)
- **Дата:** 2026-05-28
- **Контекст модуля:** `data/Task.kt`, `viewmodel/TaskViewModel.kt`, `adapter/TaskAdapter.kt`

## Контекст

Поля `deadline` и `deadlineStart` в `Task` — это **даты без времени** ("задача с
дедлайном на пятницу"), а не моменты времени ("в 14:30 пятницы"). Варианты хранения:
1. `Long` (epoch millis).
2. `LocalDate` через `TypeConverter`.
3. **`String` в ISO-формате `yyyy-MM-dd`.**

## Решение

Выбран вариант 3. В Room таблице `tasks`:
- `deadline TEXT NOT NULL DEFAULT ''` — пустая строка = дедлайна нет.
- `deadlineStart TEXT NOT NULL DEFAULT ''` (добавлен в миграции v2→v3) — начало
  диапазона; если пуст, начало = дата создания задачи.

Чтение и сравнение идут через `java.time.LocalDate.parse(...)`:
```kotlin
val dl = LocalDate.parse(deadline)   // выбросит, если строка кривая
val today = LocalDate.now()
val daysUntil = ChronoUnit.DAYS.between(today, dl)
```

Везде, где парсинг может упасть, используется `try { ... } catch (e: Exception) { fallback }`.

## Обоснование (вывод из кода)

- ISO-строка `yyyy-MM-dd` **лексикографически сортируется** = хронологически.
  Поэтому `SortMode.DEADLINE` использует:
  ```kotlin
  tasks.sortedWith(compareBy(
      { if (it.deadline.isBlank()) 1 else 0 },
      { it.deadline }
  ))
  ```
  — никаких parse'ов в hot path сортировки, просто строки.
- В JSON-экспорте (если когда-то появится) это уже готовый формат.
- DatePicker возвращает день/месяц/год и легко форматируется через
  `LocalDate.of(y, m+1, d).format(DateTimeFormatter.ISO_LOCAL_DATE)`.
- Не нужен TypeConverter — Room хранит TEXT как есть.

## Последствия

**Плюсы:**
- Сортировка O(n log n) без парсинга — компаратор сравнивает String.
- Совместимость с экспортом / CSV / SQL-инструментами без преобразований.
- Самодокументирующиеся значения при отладке SQLite.

**Минусы / риски:**
- В коде разбросано **много** `try { LocalDate.parse(deadline) } catch ...` — нет
  единой точки парсинга. Можно было бы централизовать в extension-функции на `Task`.
- Нет валидации при записи: теоретически в `deadline` можно положить `"кривая дата"`
  и до первого `LocalDate.parse` не упадёт. На практике UI всегда пишет ISO через
  DatePicker, но программный seed может ошибиться (см. `seed_tasks.sh`).
- Учёт часовых поясов нечёткий: `LocalDate.now()` берёт текущий зону системы.
  При перелёте через часовой пояс задача может "переместиться" на день. В коде это
  не обрабатывается явно.

## Связанные документы
- [[../tech/architecture]] — модель данных
- [[ADR-001-explicit-room-migrations]] — миграция v2→v3 добавила `deadlineStart`
