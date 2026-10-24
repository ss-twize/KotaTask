import Foundation

/// Всё содержимое хранилища — то, что пишется в файл и снимается для отмены.
struct StoreSnapshot: Equatable, Sendable {
    /// 2 — появились ручной порядок, подзадачи и необязательная длительность.
    static let currentVersion = 2

    var tasks: [TaskItem] = []
    var projects: [Category] = []
    var locations: [Category] = []
    var taskTypes: [Category] = []
    /// Версия формата прочитанного файла; для новых снимков — текущая. В сравнении не участвует.
    var formatVersion: Int = StoreSnapshot.currentVersion

    static func == (lhs: StoreSnapshot, rhs: StoreSnapshot) -> Bool {
        lhs.tasks == rhs.tasks && lhs.projects == rhs.projects
            && lhs.locations == rhs.locations && lhs.taskTypes == rhs.taskTypes
    }

    func categories(_ kind: CategoryKind) -> [Category] {
        switch kind {
        case .project: projects
        case .location: locations
        case .taskType: taskTypes
        }
    }

    mutating func setCategories(_ list: [Category], for kind: CategoryKind) {
        switch kind {
        case .project: projects = list
        case .location: locations = list
        case .taskType: taskTypes = list
        }
    }
}

extension StoreSnapshot: Codable {
    private enum CodingKeys: String, CodingKey { case version, savedAt, tasks, projects, locations, taskTypes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        projects = try c.decodeIfPresent([Category].self, forKey: .projects) ?? []
        locations = try c.decodeIfPresent([Category].self, forKey: .locations) ?? []
        taskTypes = try c.decodeIfPresent([Category].self, forKey: .taskTypes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(Date.now.milliseconds, forKey: .savedAt)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(projects, forKey: .projects)
        try c.encode(locations, forKey: .locations)
        try c.encode(taskTypes, forKey: .taskTypes)
    }
}

/// Файловое хранилище: один JSON в Application Support плюс ежедневные копии.
///
/// Принцип тот же, что у Android ADR-001: потеря задач — худший сценарий для таск-менеджера.
/// Поэтому запись атомарная, повреждённый файл никогда не перезаписывается, а откладывается
/// рядом, и данные поднимаются из последней копии.
struct Persistence: Sendable {
    static let fileName = "kotatask.json"
    static let backupsToKeep = 7

    let directory: URL

    var fileURL: URL { directory.appending(path: Self.fileName) }
    var backupsDirectory: URL { directory.appending(path: "Backups", directoryHint: .isDirectory) }

    /// `~/Library/Application Support/KotaTask/`
    static func standard() -> Persistence {
        Persistence(directory: dataDirectory(environment: [:], isDebug: false))
    }

    /// Папка данных. Release — «KotaTask». Debug никогда не берёт настоящие данные: папка из
    /// `KOTATASK_DATA_DIR` (демо-данные) или «KotaTask Debug» — даже если сборку открыли из Finder или Spotlight.
    static func dataDirectory(environment: [String: String], isDebug: Bool,
                              applicationSupport: URL = applicationSupportDirectory) -> URL {
        if isDebug, let custom = environment["KOTATASK_DATA_DIR"] {
            return URL(filePath: custom, directoryHint: .isDirectory)
        }
        return applicationSupport.appending(path: isDebug ? "KotaTask Debug" : "KotaTask", directoryHint: .isDirectory)
    }

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
    }

    enum LoadResult: Equatable {
        /// Файла ещё нет — первый запуск.
        case empty
        case loaded(StoreSnapshot)
        /// Основной файл повреждён, данные подняты из копии.
        case recovered(StoreSnapshot, message: String)
        /// Основной файл повреждён, копий нет. Повреждённый файл сохранён рядом.
        case failed(message: String)
    }

    func load() -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return .empty }
        if let data = try? Data(contentsOf: fileURL), let snapshot = try? Self.decode(data) {
            return .loaded(snapshot)
        }

        let quarantined = quarantineCorruptFile()
        let note = quarantined.map { " Повреждённый файл сохранён как «\($0.lastPathComponent)»." } ?? ""
        for backup in backupFiles() {
            if let data = try? Data(contentsOf: backup), let snapshot = try? Self.decode(data) {
                let message = "Файл данных был повреждён. Задачи восстановлены из копии «\(backup.lastPathComponent)».\(note)"
                return .recovered(snapshot, message: message)
            }
        }
        return .failed(message: "Файл данных повреждён, и подходящей копии нет.\(note)")
    }

    func save(_ snapshot: StoreSnapshot, now: Date = .now) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // Сбой копии (например, вместо папки Backups лежит файл) не должен блокировать основную запись.
        try? backupIfNeeded(now: now)
        let data = try Self.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    // MARK: - Кодирование

    static func encode(_ snapshot: StoreSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> StoreSnapshot {
        try JSONDecoder().decode(StoreSnapshot.self, from: data)
    }

    // MARK: - Копии

    /// Раз в день перед первой записью копирует текущий файл в Backups/ и оставляет последние 7.
    private func backupIfNeeded(now: Date) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let target = backupsDirectory.appending(path: "kotatask-\(Day(now).iso).json")
        guard !fm.fileExists(atPath: target.path(percentEncoded: false)) else { return }
        // Копируем только читаемый файл: повреждённый не должен вытеснить хорошие копии.
        guard let data = try? Data(contentsOf: fileURL), (try? Self.decode(data)) != nil else { return }
        try data.write(to: target, options: [.atomic])
        for old in backupFiles().dropFirst(Self.backupsToKeep) {
            try? fm.removeItem(at: old)
        }
    }

    /// Копии от новых к старым (имя содержит ISO-дату, поэтому сортировка по имени корректна).
    func backupFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path(percentEncoded: false))) ?? []
        return names
            .filter { $0.hasPrefix("kotatask-") && $0.hasSuffix(".json") }
            .sorted(by: >)
            .map { backupsDirectory.appending(path: $0) }
    }

    private func quarantineCorruptFile() -> URL? {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let target = directory.appending(path: "kotatask.corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: target)
            return target
        } catch {
            return nil
        }
    }
}
