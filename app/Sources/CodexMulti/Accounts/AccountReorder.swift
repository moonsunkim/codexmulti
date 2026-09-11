import CoreGraphics



enum AccountReorder {


    static func destinationIndex(rowMidpoints: [CGFloat], draggedIndex: Int,
                                 draggedMidY: CGFloat) -> Int? {
        guard rowMidpoints.indices.contains(draggedIndex) else { return nil }
        guard rowMidpoints.count > 1 else { return 0 }

        let crossedRows = rowMidpoints.enumerated().reduce(into: 0) { count, entry in
            guard entry.offset != draggedIndex else { return }
            if draggedMidY > entry.element { count += 1 }
        }
        return min(max(crossedRows, 0), rowMidpoints.count - 1)
    }
}



struct OptimisticAccountOrder: Equatable, Sendable {
    private(set) var keys: [UInt32]
    private(set) var awaitingProjection = false

    init(projectedKeys: [UInt32]) {
        keys = projectedKeys
    }

    @discardableResult
    mutating func move(from source: Int, to destination: Int) -> Bool {
        guard keys.indices.contains(source), keys.indices.contains(destination), source != destination else {
            return false
        }
        let key = keys.remove(at: source)
        keys.insert(key, at: destination)
        awaitingProjection = true
        return true
    }

    mutating func receiveProjection(keys projectedKeys: [UInt32]) {
        keys = projectedKeys
        awaitingProjection = false
    }

    func rows(from projectedRows: [UnifiedRowView]) -> [UnifiedRowView] {
        guard awaitingProjection, projectedRows.count == keys.count else { return projectedRows }
        var rowsByKey: [UInt32: UnifiedRowView] = [:]
        for row in projectedRows {
            guard rowsByKey.updateValue(row, forKey: row.key) == nil else { return projectedRows }
        }
        let ordered = keys.compactMap { rowsByKey[$0] }
        return ordered.count == projectedRows.count ? ordered : projectedRows
    }
}
