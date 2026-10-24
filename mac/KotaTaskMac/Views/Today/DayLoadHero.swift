import SwiftUI

/// Hero-блок нагрузки дня: минуты, число задач, шкала с отметками ½ и порога, статус.
/// На широком окне — в строку, на узком — в столбик.
struct DayLoadHero: View {
    let load: DayLoad
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 32) {
                numbers
                    .fixedSize()
                gauge
                    .frame(minWidth: 320)
            }
            VStack(alignment: .leading, spacing: 18) {
                numbers
                gauge
            }
        }
        .padding(22)
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [Palette.heroTop, Palette.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .shadow(color: Palette.heroBottom.opacity(0.35), radius: 18, y: 8)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: load)
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Загрузка дня")
                .font(.system(size: 12.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(load.minutes)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(load.minutes)))
                Text("мин")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .opacity(0.85)
            }
            Text(RuFormat.tasksCount(load.count))
                .font(.system(size: 13, weight: .medium))
                .contentTransition(.numericText(value: Double(load.count)))
                .opacity(0.9)
        }
    }

    private var gauge: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                statusPill
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28))
                    Capsule()
                        .fill(Palette.load(load.level))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .frame(width: max(load.minutes > 0 ? 12 : 0, width * load.fraction))
                        .shadow(color: Palette.load(load.level).opacity(0.6), radius: 6)
                    if load.isControlEnabled {
                        marker.offset(x: width * 0.5 - 1)
                    }
                }
            }
            .frame(height: 12)
            if load.isControlEnabled {
                // Подписи шкалы: 0 у левого края, половина — по центру, лимит — у правого края.
                GeometryReader { proxy in
                    Text(RuFormat.minutes(load.halfMark))
                        .fixedSize()
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .frame(height: 14)
                .overlay(alignment: .leading) { Text("0") }
                .overlay(alignment: .trailing) { Text(RuFormat.minutes(load.limit)).fixedSize() }
                .font(.system(size: 11, weight: .medium))
                .opacity(0.8)
            }
        }
    }

    private var marker: some View {
        Capsule()
            .fill(.white.opacity(0.85))
            .frame(width: 2, height: 18)
    }

    private var statusPill: some View {
        Text(load.level.title)
            .font(.system(size: 12, weight: .bold))
            // На жёлтом и зелёном белый текст не читается — тёмные чернила в обеих темах.
            .foregroundStyle(load.level == .neutral ? .white : Color(hex: 0x1F2227))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(load.level == .neutral ? .white.opacity(0.25) : Palette.load(load.level), in: Capsule())
            .contentTransition(.interpolate)
    }
}
