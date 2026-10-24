import Foundation
import Observation

/// Настройки и feature-флаги. Хранятся в `UserDefaults` под теми же ключами,
/// что и `mark_prefs` в Android (ADR-003), и пишутся мгновенно при изменении.
@MainActor
@Observable
final class AppSettings {

    enum Key {
        static let theme = "theme_mode"
        static let calendarMode = "calendar_mode"
        static let onboardingDone = "onboarding_done"
        static let notifEnabled = "notif_enabled"
        static let notifHour = "notif_hour"
        static let notifMinute = "notif_minute"
        static let featSplitToday = "feat_split_today"
        static let featCalendar = "feat_calendar"
        static let featProjects = "feat_projects"
        static let featLocations = "feat_locations"
        static let featTaskTypes = "feat_task_types"
        static let featSmartSort = "feat_smart_sort"
        static let featOverload = "feat_overload"
        static let featDefer = "feat_defer"
        static let fieldDuration = "field_duration"
        static let fieldPurpose = "field_purpose"
        static let fieldProject = "field_project"
        static let fieldLocation = "field_location"
        static let fieldTaskType = "field_task_type"
        static let assistanceLevel = "assistance_level"
        static let coeffDeadline = "coeff_deadline"
        static let coeffImportance = "coeff_importance"
        static let coeffDuration = "coeff_duration"
        static let coeffAge = "coeff_age"
        static let overloadLimit = "overload_limit_minutes"
        static let loadDurationBoost = "load_duration_boost"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var theme: ThemeMode { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    var calendarMode: CalendarMode { didSet { defaults.set(calendarMode.rawValue, forKey: Key.calendarMode) } }
    var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: Key.onboardingDone) } }

    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notifEnabled) } }
    var notificationHour: Int { didSet { defaults.set(notificationHour, forKey: Key.notifHour) } }
    var notificationMinute: Int { didSet { defaults.set(notificationMinute, forKey: Key.notifMinute) } }

    var splitToday: Bool { didSet { defaults.set(splitToday, forKey: Key.featSplitToday) } }
    var calendarEnabled: Bool { didSet { defaults.set(calendarEnabled, forKey: Key.featCalendar) } }
    var projectsEnabled: Bool { didSet { defaults.set(projectsEnabled, forKey: Key.featProjects) } }
    var locationsEnabled: Bool { didSet { defaults.set(locationsEnabled, forKey: Key.featLocations) } }
    var taskTypesEnabled: Bool { didSet { defaults.set(taskTypesEnabled, forKey: Key.featTaskTypes) } }
    var smartSort: Bool { didSet { defaults.set(smartSort, forKey: Key.featSmartSort) } }
    var overloadControl: Bool { didSet { defaults.set(overloadControl, forKey: Key.featOverload) } }
    var deferEnabledFlag: Bool { didSet { defaults.set(deferEnabledFlag, forKey: Key.featDefer) } }

    var showDurationField: Bool { didSet { defaults.set(showDurationField, forKey: Key.fieldDuration) } }
    var showPurposeField: Bool { didSet { defaults.set(showPurposeField, forKey: Key.fieldPurpose) } }
    var showProjectField: Bool { didSet { defaults.set(showProjectField, forKey: Key.fieldProject) } }
    var showLocationField: Bool { didSet { defaults.set(showLocationField, forKey: Key.fieldLocation) } }
    var showTaskTypeField: Bool { didSet { defaults.set(showTaskTypeField, forKey: Key.fieldTaskType) } }

    var assistanceLevel: AssistanceLevel { didSet { defaults.set(assistanceLevel.rawValue, forKey: Key.assistanceLevel) } }
    var customRequired: Set<RequirableField> {
        didSet {
            for field in RequirableField.allCases {
                defaults.set(customRequired.contains(field), forKey: field.defaultsKey)
            }
        }
    }

    var coefficients: Coefficients {
        didSet {
            defaults.set(coefficients.deadline, forKey: Key.coeffDeadline)
            defaults.set(coefficients.importance, forKey: Key.coeffImportance)
            defaults.set(coefficients.duration, forKey: Key.coeffDuration)
            defaults.set(coefficients.age, forKey: Key.coeffAge)
        }
    }
    var overloadLimitMinutes: Int { didSet { defaults.set(overloadLimitMinutes, forKey: Key.overloadLimit) } }
    var loadDurationBoost: Double { didSet { defaults.set(loadDurationBoost, forKey: Key.loadDurationBoost) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        func double(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        }
        func int(_ key: String, _ fallback: Int) -> Int {
            defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
        }

        theme = ThemeMode(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        calendarMode = CalendarMode(rawValue: defaults.string(forKey: Key.calendarMode) ?? "") ?? .range
        onboardingDone = bool(Key.onboardingDone, false)

        notificationsEnabled = bool(Key.notifEnabled, false)
        notificationHour = min(max(int(Key.notifHour, 8), 0), 23)
        notificationMinute = min(max(int(Key.notifMinute, 0), 0), 59)

        splitToday = bool(Key.featSplitToday, true)
        calendarEnabled = bool(Key.featCalendar, true)
        projectsEnabled = bool(Key.featProjects, true)
        locationsEnabled = bool(Key.featLocations, true)
        taskTypesEnabled = bool(Key.featTaskTypes, true)
        smartSort = bool(Key.featSmartSort, true)
        overloadControl = bool(Key.featOverload, true)
        deferEnabledFlag = bool(Key.featDefer, false)

        showDurationField = bool(Key.fieldDuration, true)
        showPurposeField = bool(Key.fieldPurpose, true)
        showProjectField = bool(Key.fieldProject, true)
        showLocationField = bool(Key.fieldLocation, true)
        showTaskTypeField = bool(Key.fieldTaskType, true)

        assistanceLevel = AssistanceLevel(rawValue: defaults.string(forKey: Key.assistanceLevel) ?? "") ?? .standard
        customRequired = Set(RequirableField.allCases.filter { bool($0.defaultsKey, false) })

        let d = Coefficients.defaults
        coefficients = Coefficients(
            deadline: double(Key.coeffDeadline, d.deadline),
            importance: double(Key.coeffImportance, d.importance),
            duration: double(Key.coeffDuration, d.duration),
            age: double(Key.coeffAge, d.age)
        )
        overloadLimitMinutes = min(max(int(Key.overloadLimit, DayLoad.defaultLimit), DayLoad.limitRange.lowerBound), DayLoad.limitRange.upperBound)
        loadDurationBoost = min(max(double(Key.loadDurationBoost, DayLoad.defaultBoost), 0), 1)
    }

    // MARK: - Производные правила

    /// Отложенное планирование требует раздельных «Сегодня» и «Стек» — без них откладывать некуда.
    var isDeferEnabled: Bool { deferEnabledFlag && splitToday }

    var defaultSortMode: SortMode { smartSort ? .priority : .alphabetical }

    func isCategoryEnabled(_ kind: CategoryKind) -> Bool {
        switch kind {
        case .project: projectsEnabled
        case .location: locationsEnabled
        case .taskType: taskTypesEnabled
        }
    }

    func setCategoryEnabled(_ kind: CategoryKind, _ value: Bool) {
        switch kind {
        case .project: projectsEnabled = value
        case .location: locationsEnabled = value
        case .taskType: taskTypesEnabled = value
        }
    }

    func isCategoryFieldShown(_ kind: CategoryKind) -> Bool {
        switch kind {
        case .project: showProjectField
        case .location: showLocationField
        case .taskType: showTaskTypeField
        }
    }

    func setCategoryFieldShown(_ kind: CategoryKind, _ value: Bool) {
        switch kind {
        case .project: showProjectField = value
        case .location: showLocationField = value
        case .taskType: showTaskTypeField = value
        }
    }

    /// Поле категории видно в форме, только если включены и ось, и само поле.
    func isCategoryVisibleInForm(_ kind: CategoryKind) -> Bool {
        isCategoryEnabled(kind) && isCategoryFieldShown(kind)
    }

    var hasAnyCategories: Bool { CategoryKind.allCases.contains(where: isCategoryEnabled) }

    var formConfig: FormConfig {
        FormConfig(
            assistance: assistanceLevel,
            customRequired: customRequired,
            showDuration: showDurationField,
            showPurpose: showPurposeField,
            visibleCategories: Set(CategoryKind.allCases.filter(isCategoryVisibleInForm))
        )
    }

    func loadContext(todayMinutes: Int) -> LoadContext {
        overloadControl
            ? LoadContext(dayLoadMinutes: todayMinutes, overloadLimitMinutes: overloadLimitMinutes, loadDurationBoost: loadDurationBoost)
            : .disabled(dayLoadMinutes: todayMinutes)
    }

    func dayLoad(minutes: Int, count: Int) -> DayLoad {
        DayLoad(minutes: minutes, count: count, limit: overloadLimitMinutes, isControlEnabled: overloadControl)
    }

    /// Время уведомления для `DatePicker`.
    var notificationTime: Date {
        get {
            Calendar.kota.date(bySettingHour: notificationHour, minute: notificationMinute, second: 0, of: .now) ?? .now
        }
        set {
            let c = Calendar.kota.dateComponents([.hour, .minute], from: newValue)
            notificationHour = c.hour ?? 8
            notificationMinute = c.minute ?? 0
        }
    }
}
