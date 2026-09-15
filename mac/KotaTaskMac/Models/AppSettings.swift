import Foundation
import SwiftData

@Model
final class AppSettings {
    var weightUrgency: Double
    var weightImportance: Double
    var weightEffort: Double
    var weightDeadline: Double
    var dailyTaskLimit: Int
    var notificationsEnabled: Bool
    var notificationHour: Int
    var notificationMinute: Int
    var onboardingCompleted: Bool

    init() {
        self.weightUrgency = 0.35
        self.weightImportance = 0.30
        self.weightEffort = 0.20
        self.weightDeadline = 0.15
        self.dailyTaskLimit = 5
        self.notificationsEnabled = false
        self.notificationHour = 9
        self.notificationMinute = 0
        self.onboardingCompleted = false
    }
}
