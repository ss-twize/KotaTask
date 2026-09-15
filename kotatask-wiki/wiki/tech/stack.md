# Технологический стек KotaTask

**Дата документа:** 2026-05-28
**Источник:** `KotaTask-main/android/build.gradle`, `app/build.gradle`, `AndroidManifest.xml`

---

## Платформа и язык

| Параметр | Значение | Где задано |
|---|---|---|
| Платформа | Android (нативное) | `AndroidManifest.xml` |
| Язык | **Kotlin 2.0.21** | `build.gradle` (root) |
| AGP | **Android Gradle Plugin 8.5.2** | `build.gradle` (root) |
| KSP | **2.0.21-1.0.28** | `build.gradle` (root) |
| `minSdk` | 26 (Android 8.0 Oreo) | `app/build.gradle` |
| `targetSdk` / `compileSdk` | 34 (Android 14) | `app/build.gradle` |
| JVM target | 17 | `app/build.gradle` |
| Package / namespace | `com.mark.app` | `app/build.gradle` |
| ApplicationId | `com.mark.app` | `app/build.gradle` |

> 🔍 **Расхождение в названии**: package называется `com.mark.app` (исторический префикс),
> хотя продукт зовётся **KotaTask**. Это видно и в `applicationId`. Переименовывать
> придётся синхронно с миграцией БД.

---

## Зависимости (runtime)

Все версии — из `app/build.gradle`. Источник: AndroidX BOM не используется,
версии прибиты руками.

### AndroidX core / UI
| Библиотека | Версия | Назначение |
|---|---|---|
| `androidx.core:core-ktx` | 1.12.0 | Kotlin-расширения для Android API |
| `androidx.appcompat:appcompat` | 1.6.1 | `AppCompatActivity`, `AppCompatDelegate` (тёмная тема) |
| `com.google.android.material:material` | 1.11.0 | Material 3 компоненты (`BottomNavigationView`, `MaterialAlertDialogBuilder`, `MaterialButton`, `TextInputLayout`) |
| `androidx.constraintlayout` | 2.1.4 | Layouts |
| `androidx.coordinatorlayout` | 1.2.0 | Coordinator + FAB |
| `androidx.fragment:fragment-ktx` | 1.6.2 | `Fragment` + `activityViewModels()` |
| `androidx.recyclerview` | 1.3.2 | Списки задач, папок, календаря |
| `androidx.cardview` | 1.0.0 | Карточки задач |
| `com.google.android.flexbox:flexbox` | 3.0.0 | Адаптивные ряды чипов (внутри `item_task.xml`) |

### Lifecycle + ViewModel
| Библиотека | Версия |
|---|---|
| `androidx.lifecycle:lifecycle-viewmodel-ktx` | 2.7.0 |
| `androidx.lifecycle:lifecycle-livedata-ktx` | 2.7.0 |

→ MVVM на `AndroidViewModel` + `LiveData`. Корутины через `viewModelScope`.

### Хранение
| Библиотека | Версия | Назначение |
|---|---|---|
| `androidx.room:room-runtime` | 2.6.1 | Room ORM, БД `mark_db` |
| `androidx.room:room-ktx` | 2.6.1 | suspend-функции для DAO |
| `androidx.room:room-compiler` (KSP) | 2.6.1 | кодогенерация DAO |
| `androidx.preference:preference-ktx` | 1.2.1 | (зависимость есть; в коде используется напрямую `SharedPreferences`) |

→ Только Room + `SharedPreferences`. **Никакого DataStore, никаких сетевых клиентов** (`Retrofit`, `OkHttp` отсутствуют). См. [[decisions/ADR-001-explicit-room-migrations]].

### Background work
| Библиотека | Версия |
|---|---|
| `androidx.work:work-runtime-ktx` | 2.9.0 |

→ Используется только для **ежедневных уведомлений** через self-rescheduling
`OneTimeWorkRequest`. См. [[decisions/ADR-004-self-rescheduling-worker]].

### Что НЕ подключено (примечательно)
- Нет DI-фреймворка (Hilt/Koin/Dagger). Зависимости создаются вручную:
  `AppDatabase.getInstance(application)` — синглтон с `@Volatile + synchronized`,
  репозитории создаются прямо в `TaskViewModel.init`.
- Нет Compose. UI полностью на XML + `ViewBinding`.
- Нет Navigation Component. Используется ручной `FragmentManager.beginTransaction()`
  с `addToBackStack("modal_…")` для модалок.
- Нет Coil / Glide / Picasso. Картинок и сети нет.
- Нет аналитики (Firebase / Amplitude / etc.).
- Нет Crashlytics / Sentry.
- Нет тестов — папок `app/src/test/` и `app/src/androidTest/` нет в исходниках.

---

## Build features
```gradle
buildFeatures {
    viewBinding true
}
```

→ `ViewBinding` включён. Используется во всех фрагментах и activity (`ActivityMainBinding`,
`FragmentTodayBinding`, `FragmentStackBinding`, и т.д.).

→ `dataBinding` НЕ включён.
→ `compose` НЕ включён.

---

## Конфигурация сборки

```gradle
buildTypes {
    release {
        minifyEnabled false
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

- Релизная сборка **БЕЗ R8/ProGuard минификации** (`minifyEnabled false`).
- Подключение `proguard-rules.pro` есть, но без `minifyEnabled` оно не применяется.
- Дебажная сборка по умолчанию.

### Кастомная Gradle-задача: автокопирование APK
В `app/build.gradle` есть `afterEvaluate`-блок, который после каждой сборки копирует
APK в папку `Builds/` под именем `KotaTask_${timestamp}.apk`. Удобно для версионирования
билдов локально. Согласно auto-memory ([feedback_apk_workflow](../../../../.claude/projects/-Users-savelijsidorenko-Documents-Coding-KotaTask-backup-20260522-201538-copy-3/memory/feedback_apk_workflow.md)),
пользовательская конвенция — `KotaTask-v{X.Y}-{feature-slug}-debug.apk`, что не совпадает
с автогенерируемым именем по timestamp — это **расхождение**, см. [[status/mvp-scope]].

---

## Архитектурные паттерны, видимые в коде

### MVVM-light (без Navigation, без DI)
```
View (Fragment / Activity)
   ↓ activityViewModels()
ViewModel (AndroidViewModel)
   ↓ репозитории как поля класса
Repository (suspend + Dispatchers.IO)
   ↓
DAO (Room) → SQLite (mark_db)
```

Применяется в [`viewmodel/TaskViewModel.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/viewmodel/TaskViewModel.kt).
Единая ViewModel держит **все** репозитории (4 шт.: Task, Project, Location, TaskType)
и шарится между всеми фрагментами через `by activityViewModels()`.

### Repository pattern
Каждой сущности соответствует репозиторий, который оборачивает DAO в `withContext(Dispatchers.IO)`.
Пример: [`repository/TaskRepository.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/repository/TaskRepository.kt).
ViewModel не вызывает DAO напрямую.

### Single-source-of-truth через LiveData
`TaskDao.getAllTasks()` возвращает `LiveData<List<Task>>` — Room автоматически
обновляет подписчиков при изменении таблицы. Все фрагменты подписываются на
`vm.allTasks` и пересчитывают свой отфильтрованный/отсортированный срез.

### Feature flags через `SharedPreferences`
Преференции `mark_prefs` хранят 20+ флагов: видимость вкладок, поля формы,
коэффициенты алгоритма, время уведомлений и т.д. Каждый флаг читается прямо
из `SharedPreferences` там, где нужен — без обёрток. См. константы в
`KotaTaskApp.kt`.

### Один Application + applyTheme
[`KotaTaskApp.kt`](../../KotaTask-main/android/app/src/main/java/com/mark/app/KotaTaskApp.kt)
делает одну вещь — применяет тёмную тему из prefs до того, как первая активити
будет создана. Все константы prefs тоже живут здесь как `companion object`.

### Error-channel через `LiveData<String?>` + `consumeError()`
В `TaskViewModel` есть `_errors: MutableLiveData<String?>`. Все мутирующие
операции обёрнуты в `launchTracked()` — если корутина бросает, ошибка
постится в канал, MainActivity её подхватывает, показывает `Toast` и
вызывает `consumeError()`, чтобы ротация экрана не показала Toast повторно.
См. [[decisions/ADR-008-error-channel-consume]].

---

## Permissions

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

- `POST_NOTIFICATIONS` — Android 13+ runtime-permission для утренних уведомлений.
- `RECEIVE_BOOT_COMPLETED` — `BootReceiver` перепланирует утренний worker после ребута.
- `INTERNET` — заявлен, но **в коде сетевых вызовов нет**. Скорее всего легаси
  декларация для будущих фич или невычищенный шаблон.

---

## Связанные документы
- [[tech/architecture]] — как модули связаны
- [[decisions/ADR-001-explicit-room-migrations]] — Room без destructive fallback
- [[decisions/ADR-003-shared-preferences-feature-flags]] — почему SharedPreferences
- [[decisions/ADR-004-self-rescheduling-worker]] — WorkManager pattern
