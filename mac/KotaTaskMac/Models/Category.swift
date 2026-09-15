import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var kindRaw: String
    var colorHex: String

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .project }
        set { kindRaw = newValue.rawValue }
    }

    init(name: String, kind: CategoryKind, colorHex: String = "#0A84FF") {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorHex = colorHex
    }
}
