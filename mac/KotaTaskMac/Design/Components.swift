import SwiftUI

// MARK: - Чипы

/// Капсула с иконкой и текстом: дедлайн, длительность, важность.
struct Chip: View {
    var text: String
    var symbol: String?
    var foreground: Color
    var background: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
    }
}

/// Точка и подпись важности.
struct ImportanceLabel: View {
    var importance: Importance

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Palette.importance(importance))
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .frame(width: 8, height: 8)
            Text(importance.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

// MARK: - Кнопки

/// Кнопка действия на карточке. Отклик на нажатие мгновенный — сжатие до 0.96.
struct CardActionStyle: ButtonStyle {
    enum Kind {
        case filled(background: Color, foreground: Color)
        case outlined(Color)
    }

    var kind: Kind
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let (fg, bg, stroke): (Color, Color, Color) = switch kind {
        case let .filled(background, foreground): (foreground, background, .clear)
        case let .outlined(color): (color, color.opacity(hovering ? 0.10 : 0.0001), color.opacity(0.45))
        }
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .frame(maxWidth: .infinity)
            .background(bg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(stroke, lineWidth: 1))
            .brightness(hovering ? 0.03 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.snappy, value: hovering)
            .onHover { hovering = $0 }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Карточка-вариант выбора: тема, режим календаря, уровень помощи.
struct ChoiceRow: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Palette.accentInk : Palette.textTertiary)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.borderDefault)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Palette.accentSoft : (hovering ? Palette.surfaceAlt : Palette.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent.opacity(0.6) : Palette.borderSubtle, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: isSelected)
        .animation(Motion.snappy, value: hovering)
    }
}

/// Сжатие при нажатии для произвольных кнопок.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

// MARK: - Шапка экрана

struct ScreenHeader<Accessory: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

extension ScreenHeader where Accessory == EmptyView {
    init(title: String, subtitle: String?) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Прокручиваемый экран с полями и ограничением ширины на очень широких окнах.
struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: 1480, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Palette.canvas)
    }
}

// MARK: - Раскладка «поток»

/// Переносит элементы на новую строку, когда они не помещаются по ширине.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Меню-капсула

/// Выпадающий выбор в виде капсулы — фильтры и сортировка внутри контента.
struct CapsuleMenu<Content: View>: View {
    var title: String
    var symbol: String
    var isActive: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(isActive ? Palette.accentInk : Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(isActive ? Palette.accentSoft : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isActive ? Palette.accent.opacity(0.5) : Palette.borderSubtle, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .menuIndicator(.hidden)
        .fixedSize()
        .animation(Motion.snappy, value: isActive)
    }
}

// MARK: - Пустое состояние

struct EmptyState: View {
    var symbol: String
    var title: String
    var subtitle: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
                .symbolRenderingMode(.hierarchical)
        } description: {
            Text(subtitle)
        }
        .foregroundStyle(Palette.textTertiary)
        .frame(maxWidth: .infinity, minHeight: 260)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

// MARK: - Подсказка ошибки

struct FieldError: View {
    var message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.error)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
