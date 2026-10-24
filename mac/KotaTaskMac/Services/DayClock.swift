import AppKit
import Observation

/// Источник «сегодня» для интерфейса. Меняется в полночь, после сна и при возврате
/// в приложение — тогда пересчитываются чипы дедлайнов и переносятся отложенные задачи.
@MainActor
@Observable
final class DayClock {
    private(set) var today: Day = .today()

    @ObservationIgnored var onDayChange: ((Day) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers = [
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh),
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: refresh),
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh),
        ]
    }

    func refresh() {
        let now = Day.today()
        guard now != today else { return }
        today = now
        onDayChange?(now)
    }
}
