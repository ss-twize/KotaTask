import CoreGraphics

/// Куда упадёт карточка по вертикали курсора: позиция вставки или вложение в карточку.
enum DropGeometry {
    static let gap: CGFloat = 8

    /// - Parameters:
    ///   - frames: кадры карточек списка в его координатах, по порядку, без перетаскиваемой.
    ///   - slotIndex, slotHeight: уже раскрытый слот. Карточки ниже него на экране сдвинуты —
    ///     без поправки позиция прыгала бы туда-обратно на каждом кадре.
    ///   - canNest: можно ли сделать перетаскиваемую задачу подзадачей этой карточки.
    /// - Returns: позиция вставки и, если курсор в средней половине подходящей карточки, её id.
    static func target(
        at y: CGFloat,
        frames: [(id: String, frame: CGRect)],
        slotIndex: Int?,
        slotHeight: CGFloat,
        canNest: (String) -> Bool
    ) -> (position: Int, nestInto: String?) {
        for (k, entry) in frames.enumerated() {
            var frame = entry.frame
            if let slotIndex, k >= slotIndex { frame.origin.y -= slotHeight + gap }
            let middleHalf = frame.insetBy(dx: 0, dy: frame.height / 4)
            if y >= middleHalf.minY && y <= middleHalf.maxY && canNest(entry.id) {
                return (k, entry.id)
            }
            if y < frame.midY { return (k, nil) }
        }
        return (frames.count, nil)
    }
}
