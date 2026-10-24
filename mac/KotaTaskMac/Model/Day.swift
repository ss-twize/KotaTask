import Foundation

extension Calendar {
    /// Григорианский календарь с понедельником в начале недели и русской локалью.
    /// Часовой пояс — autoupdating, чтобы смена пояса на лету не ломала «сегодня».
    static let kota: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.timeZone = .autoupdatingCurrent
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()
}

/// Календарный день без времени и часового пояса.
///
/// Аналог ISO-строк `yyyy-MM-dd`, которыми Android-версия хранит дедлайны (ADR-005):
/// дедлайн — это день, а не момент, и он не должен «уезжать» при смене пояса.
/// В JSON кодируется той же строкой, поэтому формат совместим с Android-бэкапом.
struct Day: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .kota) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Разбирает `yyyy-MM-dd`. Пустая или кривая строка — nil (как `catch → 0.3f` в Android).
    init?(iso: String) {
        let parts = iso.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        // Отсекаем несуществующие даты вроде 2026-02-31.
        let probe = DateComponents(calendar: .kota, year: y, month: m, day: d)
        guard probe.isValidDate(in: .kota) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    static func today(now: Date = .now) -> Day { Day(now) }

    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Полночь этого дня в текущем часовом поясе.
    func date(calendar: Calendar = .kota) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    func adding(days n: Int) -> Day {
        Day(Calendar.kota.date(byAdding: .day, value: n, to: date()) ?? date())
    }

    /// Сколько дней от `self` до `other` (отрицательно, если `other` раньше).
    func days(until other: Day) -> Int {
        Calendar.kota.dateComponents([.day], from: date(), to: other.date()).day ?? 0
    }

    /// День недели, где 0 — понедельник, 6 — воскресенье.
    var weekdayIndex: Int {
        let weekday = Calendar.kota.component(.weekday, from: date()) // 1 = вс
        return (weekday + 5) % 7
    }

    static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension Day: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = Day(iso: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Некорректная дата: \(raw)")
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}

/// Месяц года — единица навигации календаря.
struct YearMonth: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ day: Day) {
        self.init(year: day.year, month: day.month)
    }

    var firstDay: Day { Day(year: year, month: month, day: 1) }

    var numberOfDays: Int {
        Calendar.kota.range(of: .day, in: .month, for: firstDay.date())?.count ?? 30
    }

    func adding(months n: Int) -> YearMonth {
        let shifted = Calendar.kota.date(byAdding: .month, value: n, to: firstDay.date()) ?? firstDay.date()
        return YearMonth(Day(shifted))
    }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}
