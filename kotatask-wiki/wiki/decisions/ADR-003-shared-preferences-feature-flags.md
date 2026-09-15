# ADR-003 — `SharedPreferences` как единственное хранилище настроек и feature flags

- **Статус:** Принято (видно в коде)
- **Дата:** 2026-05-28
- **Контекст модуля:** `KotaTaskApp.kt` (декларация констант), 20+ мест использования

## Контекст

В приложении 20+ настроек, которые читаются из разных мест:
- Тема (`light` / `dark` / `system`).
- Видимость 5 фич: `split_today`, `calendar`, `projects`, `locations`, `task_types`, `smart_sort`, `overload`.
- Видимость 4 полей формы: `duration`, `purpose`, `assignee`, `project`.
- 4 коэффициента приоритета.
- Уровень помощи + 3 кастомных required-флага.
- Время и включённость утренних уведомлений.
- Режим календаря.
- `KEY_ONBOARDING_DONE`.

Альтернативы:
1. `androidx.preference.DataStore` — современная, type-safe, async, миграция из SharedPreferences есть из коробки.
2. **`SharedPreferences` напрямую** (`ctx.getSharedPreferences("mark_prefs", MODE_PRIVATE)`).
3. Room-таблица `settings`.
4. Вынести в отдельный `SettingsRepository`-обёртку.

## Решение

Выбран вариант 2 — `SharedPreferences` без обёртки. Все ключи объявлены как
`const val KEY_*` в `KotaTaskApp.companion object`. Каждый клиент (фрагмент, ViewModel,
Worker) читает prefs напрямую:
```kotlin
val prefs = ctx.getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
val enabled = prefs.getBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, false)
```

## Обоснование (вывод из кода)

- Простота. DI не используется (см. отсутствие Hilt/Koin), значит передавать
  `SettingsRepository` пришлось бы вручную в каждый Worker / Fragment.
- Все ключи в одном файле (`KotaTaskApp.kt`) — централизация констант есть,
  даже если обёртки нет.
- Преференции читаются **синхронно** в `Application.onCreate()` для применения темы
  до создания первой активити — DataStore (async) сделал бы это сложнее.

## Последствия

**Плюсы:**
- Минимум абстракций — легко понять, что и откуда читается.
- Совместимо со старыми Android (DataStore требует корутин и `Flow`).
- Worker может читать prefs синхронно без проблем.

**Минусы:**
- Нет type-safety: ключи и типы значений раскиданы — при ошибке в типе будет
  `ClassCastException` в runtime.
- Дефолты дублируются: например, `prefs.getInt(KEY_NOTIF_HOUR, DEFAULT_NOTIF_HOUR)`
  встречается в 4+ местах. При изменении дефолта легко пропустить точку.
- Тесты усложняются — без обёртки нельзя замокать настройки.
- Все хранится открытым (без шифрования). Для notification-времени это норм,
  но если когда-то появятся чувствительные настройки — потребуется
  `EncryptedSharedPreferences`.

## Связанные документы
- [[../tech/stack]] — секция "Persistence (sideband)"
- [[../tech/architecture]]
