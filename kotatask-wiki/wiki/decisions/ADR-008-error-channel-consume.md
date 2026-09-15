# ADR-008 — Канал одноразовых ошибок `LiveData<String?>` + `consumeError()`

- **Статус:** Принято (видно в коде)
- **Дата:** 2026-05-28
- **Контекст модуля:** `viewmodel/TaskViewModel.kt`, `ui/MainActivity.kt`

## Контекст

В CRUD-операциях с Room возможны исключения (диск переполнен, схема rotted, и т.д.).
Раньше (вывод из комментариев в коде) ошибки молча проглатывались try/catch, и
пользователь думал, что задача сохранилась, хотя БД могла отказать.

Стандартная проблема LiveData в Android: при ротации экрана подписчик при подписке
сразу получает **последнее значение** — Toast показывается повторно. Решения:
1. SingleLiveEvent (Google sample) — самокастующийся LiveData.
2. `Channel` + `Flow` (modern, требует корутин).
3. **`LiveData<String?>` + явный вызов `consumeError()` для сброса в null.**

## Решение

Выбран вариант 3. В `TaskViewModel`:
```kotlin
private val _errors = MutableLiveData<String?>()
val errors: LiveData<String?> = _errors
fun consumeError() { _errors.value = null }

private fun launchTracked(errorMessage: String, block: suspend () -> Unit) {
    viewModelScope.launch {
        try { block() } catch (e: Exception) {
            _errors.postValue("$errorMessage: ${e.message ?: e.javaClass.simpleName}")
        }
    }
}
```

Все мутирующие операции (`addTask`, `updateTask`, `deleteTask`, `addProject`, …)
обёрнуты в `launchTracked("Не удалось …") { … }`.

В `MainActivity`:
```kotlin
vm.errors.observe(this) { msg ->
    if (!msg.isNullOrBlank()) {
        Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
        vm.consumeError()
    }
}
```

## Обоснование (вывод из кода и комментариев)

Авторский комментарий в `TaskViewModel.kt`:
> Канал одноразовых ошибок для UI: Activity подписывается, показывает Toast, затем
> вызывает consumeError() чтобы Toast не появился повторно при ротации. Раньше ошибки
> Room молча проглатывались try/catch — пользователь думал, что задача сохранилась,
> хотя БД могла отказать.

Преимущество над SingleLiveEvent — явный контракт: Activity **обязана** вызвать
`consumeError`, и видно где этот сброс происходит. Меньше "магии".

## Последствия

**Плюсы:**
- Ошибки видимы пользователю.
- Нет повторных Toast'ов при ротации.
- Унифицированный helper `launchTracked()` — все CRUD-методы выглядят одинаково.

**Минусы / риски:**
- Если Activity забудет вызвать `consumeError()` — следующий observer покажет
  старую ошибку. Это easy-to-miss контракт.
- Сообщения собираются как `"$prefix: ${e.message ?: e.javaClass.simpleName}"` —
  для пользователя это часто бессмысленно (`SQLiteFullException` и т.п.).
  Хорошо для диагностики, плохо для UX.
- Нет дедупликации ошибок: 10 быстрых сбоев → 10 Toast'ов подряд.

## Связанные документы
- [[../tech/stack]] — секция "Error-channel"
- [[../tech/architecture]] — слой ViewModel
