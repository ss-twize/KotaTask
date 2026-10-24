import SwiftUI

/// Ячейка-«пончик»: кольцо из равных секторов по числу задач дня.
/// Радиус сектора — длительность по кривой насыщения, цвет — по правилам Android.
struct DonutCell: View {
    let cell: CalendarCell
    let tasks: [TaskItem]
    /// Итоговое время задач по id — радиус сектора считается по нему.
    let minutes: [String: Int]
    let isToday: Bool
    let isSelected: Bool
    let appearDelay: Double
    let selectionNamespace: Namespace.ID
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let maxRadius = side * 0.42
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Palette.accent.opacity(0.18))
                        .overlay(Circle().strokeBorder(Palette.accent.opacity(0.55), lineWidth: 1))
                        .frame(width: (maxRadius + 6) * 2, height: (maxRadius + 6) * 2)
                        .matchedGeometryEffect(id: "selected-day", in: selectionNamespace)
                } else if hovering {
                    Circle()
                        .fill(Palette.surfaceAlt)
                        .frame(width: (maxRadius + 6) * 2, height: (maxRadius + 6) * 2)
                        .transition(.opacity)
                }

                Canvas { context, size in
                    draw(in: &context, size: size, maxRadius: maxRadius)
                }
                .frame(width: side, height: side)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.45)
                .opacity(appeared || reduceMotion ? 1 : 0)

                if isToday {
                    Circle()
                        .strokeBorder(Palette.accent, lineWidth: 2)
                        .frame(width: (maxRadius + 4) * 2, height: (maxRadius + 4) * 2)
                }

                Text("\(cell.day.day)")
                    .font(.system(size: max(side * 0.27, 10), weight: .bold, design: .rounded))
                    .foregroundStyle(numberColor)
                    .shadow(color: tasks.isEmpty ? .clear : .black.opacity(0.75), radius: 3, y: 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .animation(Motion.snappy, value: hovering)
        .onAppear {
            withAnimation(Motion.bouncy.delay(appearDelay)) { appeared = true }
        }
        .accessibilityElement()
        .accessibilityLabel("\(RuFormat.long(cell.day)), \(RuFormat.tasksCount(tasks.count))")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .help(tasks.isEmpty ? RuFormat.long(cell.day) : "\(RuFormat.long(cell.day)) — \(RuFormat.tasksCount(tasks.count))")
    }

    private var numberColor: Color {
        if !cell.isCurrentMonth { return tasks.isEmpty ? Palette.textHint : .white.opacity(0.7) }
        if !tasks.isEmpty { return .white }
        if isToday { return Palette.accentInk }
        return Palette.textPrimary
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, maxRadius: CGFloat) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let strokeWidth = size.width * 0.025
        let outline = Color(hex: 0x111111)

        guard !tasks.isEmpty else {
            if cell.isCurrentMonth {
                let r = maxRadius * 0.68
                let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                context.stroke(ring, with: .color(Palette.borderDefault.opacity(0.5)), lineWidth: 1.5)
            }
            return
        }

        let otherMonthDim = cell.isCurrentMonth ? 1.0 : 0.45
        func radius(_ task: TaskItem) -> CGFloat {
            maxRadius * CalendarMonth.radiusRatio(durationMinutes: minutes[task.id] ?? task.duration ?? TaskItem.defaultDuration)
        }
        func color(_ task: TaskItem) -> Color { Palette.donut(CalendarMonth.tone(for: task, on: cell.day)).opacity(otherMonthDim) }

        if tasks.count == 1, let task = tasks.first {
            let r = radius(task)
            let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.fill(circle, with: .color(color(task)))
            context.stroke(circle, with: .color(outline), lineWidth: strokeWidth)
        } else {
            let sweep = 360.0 / Double(tasks.count)
            func sector(_ index: Int, _ task: TaskItem) -> Path {
                let start = Angle.degrees(-90 + sweep * Double(index))
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius(task), startAngle: start, endAngle: start + .degrees(sweep), clockwise: false)
                path.closeSubpath()
                return path
            }
            // Два прохода: сначала все заливки, затем все обводки — заливка соседа не перекрывает обводку.
            for (i, task) in tasks.enumerated() {
                context.fill(sector(i, task), with: .color(color(task)))
            }
            for (i, task) in tasks.enumerated() {
                context.stroke(sector(i, task), with: .color(outline), style: StrokeStyle(lineWidth: strokeWidth, lineJoin: .round))
            }
        }

        let hub = maxRadius * 0.13
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)),
            with: .color(.white.opacity(0.82))
        )
    }
}
