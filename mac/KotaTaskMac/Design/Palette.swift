import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }

    /// Цвет, который сам переключается вместе с темой окна.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// Бренд-палитра Android (`values/colors.xml` + `values-night/colors.xml`).
/// Тёмная тема — отдельный набор, а не инверсия светлой.
enum Palette {
    // Бренд
    static let jordyBlue = Color(hex: 0x7FB5EC)
    static let carnation = Color(hex: 0xF25757)
    static let parisDaisy = Color(hex: 0xFDFF73)
    static let sulu = Color(hex: 0x85EF82)
    static let deferPurple = Color(light: 0x8842B3, dark: 0xB07BD8)

    // Поверхности
    static let canvas = Color(light: 0xF7F8FB, dark: 0x0E1014)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1A1D23)
    static let surfaceAlt = Color(light: 0xF4F5F7, dark: 0x22262D)
    static let elevated = Color(light: 0xFFFFFF, dark: 0x262A32)

    // Текст
    static let textPrimary = Color(light: 0x121417, dark: 0xF4F5F7)
    static let textSecondary = Color(light: 0x4F555F, dark: 0xC5C9D2)
    static let textTertiary = Color(light: 0x727884, dark: 0xA8ADB6)
    static let textHint = Color(light: 0xA8ADB6, dark: 0x727884)

    // Обводки
    static let borderSubtle = Color(light: 0xE8EAEE, dark: 0x2D313A)
    static let borderDefault = Color(light: 0xD4D7DD, dark: 0x3D424D)

    // Акцент
    static let accent = Color(light: 0x5A9BE0, dark: 0x7FB5EC)
    static let accentInk = Color(light: 0x3672B8, dark: 0x9CC6F1)
    static let accentSoft = Color(light: 0xEEF5FD, dark: 0x1E2A3D)
    static let accentContainer = Color(light: 0xDCEAFB, dark: 0x1E4A82)

    // Семантика
    static let success = Color(light: 0x5BC758, dark: 0x85EF82)
    static let successSoft = Color(light: 0xEEFCEE, dark: 0x1A2E1A)
    static let onSuccess = Color(light: 0x1E5C1C, dark: 0xD8F7D6)
    static let warning = Color(light: 0xD8DA47, dark: 0xFDFF73)
    static let warningSoft = Color(light: 0xFEFEE8, dark: 0x2D2E15)
    static let onWarning = Color(light: 0x6D6F0E, dark: 0xFDFFCF)
    static let error = Color(hex: 0xF25757)
    static let errorSoft = Color(light: 0xFEEDED, dark: 0x2E1717)
    static let deferSoft = Color(light: 0xF5EDFA, dark: 0x2A1E33)

    // Кнопки действий: тёмный текст на светлой заливке читается в обеих темах.
    static let completeFill = Color(light: 0x5BC758, dark: 0x6FD86C)
    static let completeInk = Color(light: 0x0F3A0E, dark: 0x0B1F0B)
    static let onJordyBlue = Color(hex: 0x0E2F55)

    // Бейдж приоритета
    static let scoreBackground = Color(light: 0xFDFFCF, dark: 0x2D2E15)
    static let scoreText = Color(light: 0x6D6F0E, dark: 0xFDFFCF)

    // Шкала нагрузки
    static let loadTrack = Color(light: 0xE8EAEE, dark: 0x2D313A)

    // Hero «Сегодня»
    static let heroTop = Color(light: 0x8CC0F2, dark: 0x5A9BE0)
    static let heroBottom = Color(light: 0x5A9BE0, dark: 0x3672B8)

    static func importance(_ value: Importance) -> Color {
        switch value {
        case .high: carnation
        case .medium: parisDaisy
        case .low: sulu
        }
    }

    /// Полоса важности слева на карточке: жёлтый темнее, чтобы читался на белом.
    static func importanceStripe(_ value: Importance) -> Color {
        switch value {
        case .high: carnation
        case .medium: Color(hex: 0xD8DA47)
        case .low: sulu
        }
    }

    static func donut(_ tone: DonutTone) -> Color {
        switch tone {
        case .deferred: Color(hex: 0x8842B3)
        case .today: jordyBlue
        case .high: carnation
        case .medium: parisDaisy
        case .low: sulu
        }
    }

    static func load(_ level: LoadLevel) -> Color {
        switch level {
        case .ok: sulu
        case .warn: parisDaisy
        case .over: carnation
        case .neutral: jordyBlue
        }
    }

    /// Цвет цифры нагрузки на экране стека.
    static func loadInk(_ level: LoadLevel) -> Color {
        switch level {
        case .ok: success
        case .warn: warning
        case .over: error
        case .neutral: textPrimary
        }
    }
}
