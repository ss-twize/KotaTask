# KotaTask

Персональный планировщик для Android и macOS: настраиваемые приоритеты, план дня,
календарь и категоризация по проекту, локации и типу действия. Клиенты работают
локально, без аккаунтов и синхронизации между устройствами.

## Версия 1.1

- Android-виджет 4×1 для ввода названия задачи с пометкой «Дополнить».
- Экспорт всего Стека и задач на Сегодня в текст: пояснения полей, копирование,
  системная отправка и сохранение .txt.
- Android-канбан с колонками проектов, ручным порядком и перетаскиванием карточек.
- Настройка состава и порядка нижнего меню Android.
- Mac-доска проектов, подзадачи, отмена действий и экспорт активных задач.

Подробности и команды проверок — [RELEASE_NOTES_1.1.md](RELEASE_NOTES_1.1.md).

## Готовые сборки

- [Android 1.1-beta, подписанный APK](releases/1.1/KotaTask-1.1-beta-android.apk).
- [macOS 1.1, ZIP с приложением](releases/1.1/KotaTask-1.1-mac.zip).
- [Контрольные суммы SHA-256](releases/1.1/SHA256SUMS.txt).

Mac-сборка требует macOS 26 и подписана ad-hoc для локального запуска.

## Структура

| Каталог | Назначение |
|---|---|
| Code/KotaTask-main/android | Android: Kotlin, XML/ViewBinding, Room и WorkManager |
| mac | macOS: Swift 6, SwiftUI, JSON-хранилище и тесты |
| kotatask-wiki/wiki | Описание продукта, архитектура и ADR |
| docs/superpowers | Спецификации и история решений |
| Design | Исследование и концепции дизайна |
| Brand | Логотип и брендовые ассеты |
| releases/1.1 | Установочные файлы версии 1.1 |

Начало навигации по документации — [INDEX.md](INDEX.md).
[PROJECT.md](PROJECT.md) содержит подробный Android-справочник; его основной
текст описывает снимок кода от сентября 2026 года, а изменения 1.1 вынесены
в release notes. Июньский план Mac на SwiftData заменён текущим SwiftUI-клиентом
с JSON-хранилищем.

## Сборка Android

Нужны Android SDK 34 и JDK 17. Путь к SDK задаётся локально; путь к JDK в
gradle.properties следует проверить для своей машины.

~~~sh
cd Code/KotaTask-main/android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest :app:lintDebug
~~~

Для Release используйте локальный keystore.properties по
[шаблону](Code/KotaTask-main/android/keystore.properties.example). Файлы ключей
и пароли в Git не хранятся.

## Сборка macOS

Нужны Xcode 26 и XcodeGen. Конфигурация — mac/project.yml; Xcode-проект генерируется.

~~~sh
cd mac
xcodegen generate
xcodebuild test -project KotaTaskMac.xcodeproj -scheme KotaTaskMac -destination 'platform=macOS,arch=arm64'
~~~

Инструкция по установке и изоляции Debug-данных — [mac/README.md](mac/README.md).

## Проверки версии 1.1

21 ноября 2026 года прошли 98 тестов Mac, 8 модульных и 3 инструментальных
теста Android. Проверены миграция Room v4→v5, быстрый ввод, перетаскивание,
настройка меню и экспорт. Android Lint завершился без ошибок; предупреждения
проекта остаются.
