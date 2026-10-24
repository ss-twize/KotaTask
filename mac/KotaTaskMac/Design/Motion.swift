import SwiftUI

/// Пружины приложения. По умолчанию — критическое демпфирование (без перелёта):
/// спокойно и не отвлекает. Отскок — только там, где у действия есть «импульс».
enum Motion {
    /// Перестановки, появление и исчезновение карточек, смена экранов.
    static let standard = Animation.spring(response: 0.36, dampingFraction: 1.0)
    /// Мелкие отклики: выбор, переключатели, наведение.
    static let snappy = Animation.spring(response: 0.24, dampingFraction: 1.0)
    /// Отметка выполнения, всплывающие подтверждения — с лёгким перелётом.
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Мгновенное сжатие при нажатии.
    static let press = Animation.spring(response: 0.16, dampingFraction: 1.0)

    /// Вместо пружин и сдвигов при «Уменьшить движение» — короткое растворение.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : animation
    }
}
